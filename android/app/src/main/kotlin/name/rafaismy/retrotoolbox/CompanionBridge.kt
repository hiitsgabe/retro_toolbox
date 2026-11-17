package name.rafaismy.retrotoolbox

import android.content.Context
import android.os.SystemClock
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/// The companion engine and its channel. Lives for the process: the engine is
/// started on first use and kept, so reopening the second screen is instant.
object CompanionBridge {
    private const val ENGINE_ID = "companion"
    private const val LAUNCH_GRACE_MS = 3000L
    private var group: FlutterEngineGroup? = null
    private var channel: MethodChannel? = null
    private var lastJson: String? = null
    var activity: CompanionActivity? = null
        private set

    // A companion started but not created yet. The launch itself makes Dart
    // plan again (lifecycle, display changes), and that second open must not
    // start another one. Bounded, in case the system never brings it up.
    private var launchingOn: Int? = null
    private var launchedAt = 0L

    fun engine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val entry = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "package:retro_toolbox/companion/companion_main.dart",
            "companionMain",
        )
        val engine = (group ?: FlutterEngineGroup(app).also { group = it }).createAndRunEngine(app, entry)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "retro_toolbox/companion").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    lastJson?.let { ch.invokeMethod("update", it) }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
        return engine
    }

    /// Keeps the payload for a companion that is not up yet.
    fun send(json: String) {
        lastJson = json
        channel?.invokeMethod("update", json)
    }

    fun launched(displayId: Int) {
        launchingOn = displayId
        launchedAt = SystemClock.uptimeMillis()
    }

    fun isLaunching(displayId: Int): Boolean =
        launchingOn == displayId && SystemClock.uptimeMillis() - launchedAt < LAUNCH_GRACE_MS

    /// One companion at a time: a newer one replaces any left over, which the
    /// engine has already been taken from.
    fun attach(a: CompanionActivity) {
        activity?.takeIf { it !== a }?.finish()
        activity = a
        launchingOn = null
    }

    fun detach(a: CompanionActivity) {
        if (activity === a) activity = null
    }

    fun close() {
        launchingOn = null
        activity?.finish()
        activity = null
    }
}
