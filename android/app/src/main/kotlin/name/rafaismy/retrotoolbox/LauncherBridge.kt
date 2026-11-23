package name.rafaismy.retrotoolbox

import android.app.Activity
import android.app.ActivityOptions
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.view.Display
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// retro_toolbox/launcher: reports which emulator packages are installed and
/// starts one on a game. Dart decides everything (the variant, the ROM mode,
/// the extras' values); this side builds the Intent it is given and answers
/// with a code, never an exception.
class LauncherBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "retro_toolbox/launcher")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "detect" -> detect(call, result)
                "launch" -> result.success(
                    try {
                        launch(call)
                    } catch (e: Exception) {
                        code("refused", e.toString())
                    }
                )
                "openApp" -> result.success(openApp(call.argument<String>("package")))
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    /// One entry per installed variant whose activity is exported. A package
    /// is visible through the MAIN/LAUNCHER and MAIN/LEANBACK_LAUNCHER
    /// queries; resolving a component also finds unexported activities, so
    /// `exported` is checked here.
    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        val presets = call.argument<List<Map<String, Any?>>>("presets").orEmpty()
        Thread {
            val out = ArrayList<Map<String, Any?>>()
            val pm = activity.packageManager
            for (preset in presets) {
                val id = preset["id"] as? String ?: continue
                val activityName = preset["activity"] as? String ?: continue
                val packages = (preset["packages"] as? List<*>)?.filterIsInstance<String>().orEmpty()
                for (pkg in packages) {
                    try {
                        @Suppress("DEPRECATION")
                        val info = pm.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
                        @Suppress("DEPRECATION")
                        val component = pm.getActivityInfo(ComponentName(pkg, activityName), 0)
                        if (!component.exported) continue
                        val app = info.applicationInfo ?: continue
                        val requested = info.requestedPermissions?.toSet().orEmpty()
                        val entry = HashMap<String, Any?>()
                        entry["id"] = id
                        entry["package"] = pkg
                        entry["label"] = pm.getApplicationLabel(app).toString()
                        entry["versionName"] = info.versionName
                        entry["dataDir"] = app.dataDir
                        entry["targetSdk"] = app.targetSdkVersion
                        entry["legacyStorage"] = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && app.hasRequestedLegacyExternalStorage()
                        entry["requestsManage"] = "android.permission.MANAGE_EXTERNAL_STORAGE" in requested
                        entry["requestsRead"] = "android.permission.READ_EXTERNAL_STORAGE" in requested
                        entry["sdkInt"] = Build.VERSION.SDK_INT
                        iconPng(pm.getApplicationIcon(app))?.let { entry["icon"] = it }
                        out.add(entry)
                    } catch (_: Exception) {
                        // Not installed, or the activity is gone: not detected.
                    }
                }
            }
            activity.runOnUiThread { result.success(out) }
        }.start()
    }

    private fun code(code: String, message: String? = null): Map<String, Any?> = mapOf("code" to code, "message" to message)

    private fun launch(call: MethodCall): Map<String, Any?> {
        val pkg = call.argument<String>("package") ?: return code("refused", "no package")
        val activityName = call.argument<String>("activity") ?: return code("refused", "no activity")
        val action = call.argument<String>("action") ?: return code("refused", "no action")
        val rom = call.argument<Map<String, Any?>>("rom") ?: return code("refused", "no rom")
        val pm = activity.packageManager
        try {
            pm.getPackageInfo(pkg, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            return code("notInstalled")
        }
        val exported = try {
            pm.getActivityInfo(ComponentName(pkg, activityName), 0).exported
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
        if (!exported) return code("componentGone")

        val path = rom["path"] as? String ?: return code("romUnreadable")
        val file = File(path).canonicalFile
        if (!file.path.startsWith("/storage/") || !file.isFile) return code("romUnreadable")
        val extra = rom["extra"] as? String
        val mime = call.argument<String>("mimeType")
        val intent = Intent(action)
            .setComponent(ComponentName(pkg, activityName))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        for (c in call.argument<List<String>>("categories").orEmpty()) intent.addCategory(c)
        for (f in call.argument<List<String>>("flags").orEmpty()) {
            when (f) {
                "clearTask" -> intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                "clearTop" -> intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                "noHistory" -> intent.addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
            }
        }

        // Only in provider mode: the URI that {rom} and {rom.uri} stand for.
        var romUri: String? = null
        val toGrant = ArrayList<Uri>()
        when (rom["mode"]) {
            "path" -> {
                if (extra == null) return code("refused", "a path needs an extra")
                intent.putExtra(extra, file.path)
            }
            "saf" -> {
                val uri = Uri.parse(rom["uri"] as? String ?: return code("romUnreadable"))
                if (extra != null) intent.putExtra(extra, uri.toString()) else setData(intent, uri, mime)
            }
            "provider" -> {
                val discs = if (rom["clipDataDiscs"] == true) (rom["discPaths"] as? List<*>)?.filterIsInstance<String>().orEmpty() else emptyList()
                for (d in discs.ifEmpty { listOf(file.path) }) {
                    val f = File(d).canonicalFile
                    if (!f.path.startsWith("/storage/") || !f.isFile) return code("romUnreadable")
                    toGrant.add(FileProvider.getUriForFile(activity, "${activity.packageName}.roms", f))
                }
                val first = toGrant[0]
                // Grants travel only on the data and the ClipData, so the URI
                // goes in both even when an extra carries it too.
                setData(intent, first, mime)
                val clip = ClipData.newRawUri("rom", first)
                for (u in toGrant.drop(1)) clip.addItem(ClipData.Item(u))
                intent.clipData = clip
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                if (extra != null) intent.putExtra(extra, first.toString())
                romUri = first.toString()
            }
            else -> return code("refused", "unknown rom mode ${rom["mode"]}")
        }
        if (mime != null && intent.data == null) intent.type = mime

        fun render(s: String): String = romUri?.let { s.replace("{rom.uri}", it).replace("{rom}", it) } ?: s
        for (e in call.argument<List<Map<String, Any?>>>("extras").orEmpty()) {
            val key = e["key"] as? String ?: continue
            when (e["type"]) {
                "string" -> intent.putExtra(key, render(e["value"] as String))
                "bool" -> intent.putExtra(key, e["value"] as Boolean)
                "int" -> intent.putExtra(key, (e["value"] as Number).toInt())
                "long" -> intent.putExtra(key, (e["value"] as Number).toLong())
                "stringArray" -> intent.putExtra(key, (e["value"] as List<*>).map { render(it as String) }.toTypedArray())
            }
        }

        // The grant must come from this process: Dolphin finishes the
        // activity it was sent to, and an Intent's grant dies with it.
        revokeGrants()
        for (u in toGrant) {
            activity.grantUriPermission(pkg, u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            grants.add(pkg to u)
        }
        return try {
            // The default display: on a dual screen device with this app on
            // the bottom screen, the game still goes to the top one.
            val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ActivityOptions.makeBasic().setLaunchDisplayId(Display.DEFAULT_DISPLAY).toBundle()
            } else {
                null
            }
            activity.startActivity(intent, options)
            code("ok")
        } catch (e: ActivityNotFoundException) {
            code("refused", e.toString())
        } catch (e: SecurityException) {
            code("refused", e.toString())
        }
    }

    private fun setData(intent: Intent, uri: Uri, mime: String?) {
        if (mime != null) intent.setDataAndType(uri, mime) else intent.data = uri
    }

    /// The grants of the previous launch: one game's files at a time.
    private fun revokeGrants() {
        for ((pkg, uri) in grants) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activity.revokeUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } else {
                    activity.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } catch (_: Exception) {
                // Already gone with the package.
            }
        }
        grants.clear()
    }

    private fun openApp(pkg: String?): Boolean {
        if (pkg == null) return false
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        /// Outlives a bridge: a moved MainActivity gets a new one, and the
        /// grants it made must still be revoked.
        val grants = ArrayList<Pair<String, Uri>>()
    }
}
