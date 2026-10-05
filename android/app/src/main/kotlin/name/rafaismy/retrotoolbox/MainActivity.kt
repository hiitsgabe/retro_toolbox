package name.rafaismy.retrotoolbox

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        // In-app updater: opens the system installer for a downloaded APK.
        // Returns false (after opening the "install unknown apps" settings)
        // when the app may not install packages yet.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retro_toolbox/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Play installs must not self-update; the app links out instead.
                    "installerPackage" -> result.success(
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                packageManager.getInstallSourceInfo(packageName).installingPackageName
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getInstallerPackageName(packageName)
                            }
                        } catch (e: Exception) {
                            null
                        }
                    )
                    "installApk" -> {
                        // Only an APK the updater downloaded: <cache>/updates/*.apk.
                        val updates = File(cacheDir, "updates").canonicalFile
                        val apk = call.argument<String>("path")?.let { File(it).canonicalFile }
                        if (apk == null || apk.parentFile != updates || !apk.name.endsWith(".apk")) {
                            result.error("ARGS", "not an update APK", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                            ) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
