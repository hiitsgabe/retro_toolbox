package name.rafaismy.retrotoolbox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Exposes the read-only nativeLibraryDir so a bundled executable shipped
        // as a jniLib (libchdman.so) can be exec'd — modern Android forbids
        // running binaries from writable app dirs.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retrotoolbox/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
