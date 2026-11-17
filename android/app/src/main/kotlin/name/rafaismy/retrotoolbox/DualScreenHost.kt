package name.rafaismy.retrotoolbox

import android.app.Activity
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Main-engine side of the second screen: lists displays, opens and closes
/// the companion on another display, moves the main activity, and relays
/// payloads to the companion engine. Which display gets what is decided in
/// Dart (dual_screen_plan.dart).
class DualScreenHost(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "retro_toolbox/dual_screen")
    private val displays = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = changed()
        override fun onDisplayRemoved(displayId: Int) = changed()
        override fun onDisplayChanged(displayId: Int) = changed()
    }

    // Set once this activity has handed over to the one on the other display.
    // Its engine can still ask to close the companion while it goes down, and
    // by then the companion may belong to the new one.
    private var moved = false

    init {
        displays.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
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
        val a = CompanionBridge.activity ?: return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) a.display?.displayId else a.windowManager.defaultDisplay.displayId
    }

    /// Nothing to do when the companion is up, or coming up, on [displayId]:
    /// starting it again could take focus from the main screen.
    private fun openCompanion(displayId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || moved) return
        if (companionDisplayId() == displayId || CompanionBridge.isLaunching(displayId)) return
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

    /// The app restarts on [displayId]; downloads carry on in the background
    /// downloader, as they do across any restart.
    private fun moveMain(displayId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || moved) return
        CompanionBridge.close()
        val intent = Intent(activity, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        activity.startActivity(intent, ActivityOptions.makeBasic().setLaunchDisplayId(displayId).toBundle())
        moved = true
        activity.finish()
    }

    fun dispose() {
        displays.unregisterDisplayListener(listener)
        channel.setMethodCallHandler(null)
        closeCompanion()
    }
}
