package name.rafaismy.retrotoolbox

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pickResult: MethodChannel.Result? = null
    private var pickingDir = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // System picker (SAF) that opens where the app asks (EXTRA_INITIAL_URI,
        // which file_picker only passes for saves). Dart maps the picked
        // document id back to a real path; "copy" is the fallback for files
        // from providers with no path (Drive, media).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retro_toolbox/pick")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (pickResult != null) {
                            result.error("BUSY", "a picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pickingDir = call.argument<Boolean>("dir") == true
                        // Any file type: the callers check the extension themselves.
                        val intent = if (pickingDir) Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        else Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                        val docId = call.argument<String>("initialDocId")
                        if (docId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            intent.putExtra(
                                DocumentsContract.EXTRA_INITIAL_URI,
                                DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
                            )
                        }
                        try {
                            pickResult = result
                            startActivityForResult(intent, PICK_REQUEST)
                        } catch (e: Exception) {
                            pickResult = null
                            result.error("PICK", e.message, null)
                        }
                    }
                    "copy" -> {
                        val uri = Uri.parse(call.argument<String>("uri"))
                        Thread {
                            val out = try {
                                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                                    ?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "picked"
                                val file = File(File(cacheDir, "picked").apply { mkdirs() }, File(name).name)
                                contentResolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
                                file.path
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread { result.success(out) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val result = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val docId = try {
            if (pickingDir) DocumentsContract.getTreeDocumentId(uri) else DocumentsContract.getDocumentId(uri)
        } catch (e: Exception) {
            null
        }
        result.success(mapOf("uri" to uri.toString(), "authority" to uri.authority, "docId" to docId))
    }

    private companion object {
        const val PICK_REQUEST = 0x5AF
    }
}
