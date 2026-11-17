package name.rafaismy.retrotoolbox

import android.content.Context
import android.os.SystemClock
import com.tekartik.sqflite.SqflitePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.pathprovider.PathProviderPlugin

/// The companion engine and its channel. Lives for the process: the engine is
/// started on first use and kept, so reopening the second screen is instant.
object CompanionBridge {
    private const val ENGINE_ID = "companion"
    private const val LAUNCH_GRACE_MS = 3000L
    private var channel: MethodChannel? = null
    private var lastJson: String? = null
    var activity: CompanionActivity? = null
        private set

    /// Told when a companion comes up, so the main side can plan again.
    var onAttached: (() -> Unit)? = null

    /// Set by the DualScreenHost of the activity running the app: takes a
    /// request from the companion's buttons (JSON) to its engine.
    var onAction: ((String) -> Unit)? = null

    /// The MainActivity whose engine runs the app, set by its DualScreenHost:
    /// a key that reaches the companion belongs to it.
    var mainActivity: MainActivity? = null

    // One launch in flight at a time. Starting the companion makes Dart plan
    // again (lifecycle, display changes) before it is created, and that open
    // must not start a second one; a close in that gap is kept for when it
    // arrives. Bounded, in case the system never brings it up.
    private var launchingOn: Int? = null
    private var launchedAt = 0L
    private var cancelled = false

    fun hasEngine(): Boolean = FlutterEngineCache.getInstance().contains(ENGINE_ID)

    fun engine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        // Only what the companion's Dart reaches: path_provider for the
        // LaunchBox files, and sqflite plus path_provider for the image cache.
        // The full list would attach the main app's plugins a second time
        // (the downloader, Python, the foreground service) to an engine that
        // never uses them.
        val engine = FlutterEngine(app, null, false)
        engine.plugins.add(PathProviderPlugin())
        engine.plugins.add(SqflitePlugin())
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "retro_toolbox/companion").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        lastJson?.let { ch.invokeMethod("update", it) }
                        result.success(null)
                    }
                    // A button pressed on the companion: the main engine runs it.
                    "action" -> {
                        (call.arguments as? String)?.let { json -> onAction?.invoke(json) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:retro_toolbox/companion/companion_main.dart",
                "companionMain",
            )
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
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
        cancelled = false
    }

    /// The display a launch is still in flight to, if any.
    fun launching(): Int? =
        launchingOn?.takeIf { SystemClock.uptimeMillis() - launchedAt < LAUNCH_GRACE_MS }

    /// An open for the display already being launched to: undoes a close
    /// that came in between.
    fun keepLaunch() {
        cancelled = false
    }

    /// One companion at a time: a newer one replaces any left over, which the
    /// engine has already been taken from. One closed while it was on its way
    /// goes straight away.
    fun attach(a: CompanionActivity) {
        activity?.takeIf { it !== a }?.finish()
        launchingOn = null
        if (cancelled) {
            cancelled = false
            activity = null
            a.finish()
        } else {
            activity = a
        }
        onAttached?.invoke()
    }

    fun detach(a: CompanionActivity) {
        if (activity === a) activity = null
    }

    fun close() {
        // Even past the grace: a late arrival must not outlive the close.
        if (launchingOn != null) cancelled = true
        activity?.finish()
        activity = null
    }
}
