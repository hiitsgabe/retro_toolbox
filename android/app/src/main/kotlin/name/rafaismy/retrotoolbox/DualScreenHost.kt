package name.rafaismy.retrotoolbox

import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = changed()
        override fun onDisplayRemoved(displayId: Int) = changed()
        override fun onDisplayChanged(displayId: Int) = changed()
    }
    private val attached: () -> Unit = { changed() }

    // Set once this activity has handed its engine to the one on the other
    // display. Its Dart can still ask to close the companion while this one
    // goes down, and by then the companion may belong to the new one.
    private var moved = false

    // Until when a lost window focus is put down to the companion launch.
    private var refocusUntil = 0L

    init {
        displays.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
        CompanionBridge.onAttached = attached
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
        refocusUntil = SystemClock.uptimeMillis() + REFOCUS_MS
    }

    private fun closeCompanion() {
        if (!moved) CompanionBridge.close()
    }

    /// MainActivity lost window focus. The new companion's display becomes
    /// the top focused one even though its window is not focusable (focus
    /// follows the activity, not the window flag), and with one focus for all
    /// displays the main screen is then left without key input. Bring this
    /// task back to the front, once per launch so it can never loop. Whether
    /// a device needs it is in docs/dual-screen-checklist.md.
    fun onFocusLost() {
        if (SystemClock.uptimeMillis() >= refocusUntil) return
        refocusUntil = 0L
        (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).moveTaskToFront(activity.taskId, 0)
    }

    /// The same engine carries on in a new MainActivity on [displayId]:
    /// running downloads, imports and extractions are not interrupted, and
    /// the background downloader keeps the engine it reports to.
    private fun moveMain(displayId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || moved) return
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
        activity.finish()
    }

    fun dispose() {
        displays.unregisterDisplayListener(listener)
        channel.setMethodCallHandler(null)
        if (CompanionBridge.onAttached === attached) CompanionBridge.onAttached = null
        closeCompanion()
    }

    private companion object {
        const val REFOCUS_MS = 2000L
    }
}
