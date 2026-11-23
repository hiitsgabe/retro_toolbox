package name.rafaismy.retrotoolbox

import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/// Main-engine side of the second screen: lists displays, opens and closes
/// the companion on another display, moves the main activity, and relays
/// payloads to the companion engine. Which display gets what is decided in
/// Dart (dual_screen_plan.dart).
class DualScreenHost(private val activity: MainActivity, private val engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "retro_toolbox/dual_screen")
    private val displays = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    // Whether each display was on when Dart last heard. onDisplayChanged also
    // fires for brightness, refresh rate and the like, often, and only on/off
    // can change the plan.
    private val wasOn = HashMap<Int, Boolean>()
    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {
            wasOn[displayId] = isOn(displayId)
            changed()
        }
        override fun onDisplayRemoved(displayId: Int) {
            wasOn.remove(displayId)
            changed()
        }
        override fun onDisplayChanged(displayId: Int) {
            val on = isOn(displayId)
            if (wasOn.put(displayId, on) != on) changed()
        }
    }
    private val attached: () -> Unit = { changed() }
    private val action: (String) -> Unit = { json -> channel.invokeMethod("companionAction", json) }

    // Set once this activity has handed its engine to the one on the other
    // display. Its Dart can still ask to close the companion while this one
    // goes down, and by then the companion may belong to the new one.
    private var moved = false

    init {
        for (d in displays.displays) wasOn[d.displayId] = d.state == Display.STATE_ON
        displays.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
        CompanionBridge.onAttached = attached
        CompanionBridge.onAction = action
        CompanionBridge.mainActivity = activity
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "displays" -> {
                        val current = currentDisplayId()
                        // Launching on a given display needs API 26: below
                        // that, list only this one, so Dart sees no second screen.
                        val listed = displays.displays.filter {
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O || it.displayId == current
                        }
                        result.success(mapOf(
                            "current" to current,
                            "displays" to listed.map {
                                mapOf(
                                    "id" to it.displayId,
                                    "isDefault" to (it.displayId == Display.DEFAULT_DISPLAY),
                                    "on" to (it.state == Display.STATE_ON),
                                )
                            },
                        ))
                    }
                    "openCompanion" -> { openCompanion(call.argument<Int>("displayId")!!); result.success(null) }
                    "closeCompanion" -> { closeCompanion(); result.success(null) }
                    "moveMain" -> { moveMain(call.argument<Int>("displayId")!!); result.success(null) }
                    "send" -> { CompanionBridge.send(call.argument<String>("json")!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("dual_screen", e.message, null)
            }
        }
    }

    private fun changed() {
        channel.invokeMethod("displaysChanged", null)
    }

    private fun isOn(displayId: Int): Boolean = displays.getDisplay(displayId)?.state == Display.STATE_ON

    /// The display this activity is on, which is not the default one once it
    /// has moved.
    @Suppress("DEPRECATION")
    private fun currentDisplayId(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display?.displayId ?: Display.DEFAULT_DISPLAY
        else activity.windowManager.defaultDisplay.displayId

    @Suppress("DEPRECATION")
    private fun companionDisplayId(): Int? {
        val a = CompanionBridge.activity?.takeUnless { it.isFinishing } ?: return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) a.display?.displayId else a.windowManager.defaultDisplay.displayId
    }

    /// Nothing to do when the companion is up, or coming up, on [displayId]:
    /// starting it again could take focus from the main screen. While one is
    /// on its way anywhere, wait for it: its arrival plans again.
    private fun openCompanion(displayId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || moved) return
        if (companionDisplayId() == displayId) return
        val launching = CompanionBridge.launching()
        if (launching != null) {
            if (launching == displayId) CompanionBridge.keepLaunch()
            return
        }
        CompanionBridge.close()
        CompanionBridge.engine(activity)
        val intent = Intent(activity, CompanionActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        activity.startActivity(intent, ActivityOptions.makeBasic().setLaunchDisplayId(displayId).toBundle())
        CompanionBridge.launched(displayId)
    }

    private fun closeCompanion() {
        if (!moved) CompanionBridge.close()
    }

    /// The same engine carries on in a new MainActivity on [displayId]:
    /// running downloads, imports and extractions are not interrupted, and
    /// the background downloader keeps the engine it reports to.
    private fun moveMain(displayId: Int) {
        // The home app cannot move: finishing it here would leave Android to
        // start a second engine for the default display. The settings never
        // offer Main on bottom with HOME on; this holds if one slips through.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || moved || activity.isHome) return
        CompanionBridge.close()
        FlutterEngineCache.getInstance().put(MainActivity.ENGINE_ID, engine)
        val intent = FlutterActivity.CachedEngineIntentBuilder(MainActivity::class.java, MainActivity.ENGINE_ID)
            .destroyEngineWithActivity(true)
            .build(activity)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        activity.handingOver = true
        try {
            activity.startActivity(intent, ActivityOptions.makeBasic().setLaunchDisplayId(displayId).toBundle())
        } catch (e: Exception) {
            activity.handingOver = false
            // Unlisted again, unless this activity itself came from the cache.
            if (activity.cachedEngineId == null) FlutterEngineCache.getInstance().remove(MainActivity.ENGINE_ID)
            throw e
        }
        moved = true
        releaseKeys()
        removeDeadTasks()
        // Its task too: holds only this activity, and left behind it stayed in
        // recents as one more Retro Toolbox for every start that moved.
        activity.finishAndRemoveTask()
    }

    /// A moved MainActivity lives in a task of its own, which outlives the
    /// process in recents: each start that moved left one more Retro Toolbox
    /// there. Drop the ones with nothing running in them.
    private fun removeDeadTasks() {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (task in am.appTasks) {
            val info = try { task.taskInfo } catch (e: IllegalArgumentException) { continue }
            if (info.numActivities == 0 && info.baseIntent.component?.className == MainActivity::class.java.name) {
                task.finishAndRemoveTask()
            }
        }
    }

    fun dispose() {
        displays.unregisterDisplayListener(listener)
        channel.setMethodCallHandler(null)
        if (CompanionBridge.onAttached === attached) CompanionBridge.onAttached = null
        if (CompanionBridge.onAction === action) CompanionBridge.onAction = null
        releaseKeys()
        closeCompanion()
    }

    /// This activity is going: the companion's keys wait for the next host.
    private fun releaseKeys() {
        if (CompanionBridge.mainActivity === activity) CompanionBridge.mainActivity = null
    }
}
