package name.rafaismy.retrotoolbox

import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import rikka.shizuku.Shizuku
import kotlin.concurrent.thread

/** `retro_toolbox/shizuku`: status, permission, and argv execution through [ShellService]. */
class ShizukuBridge(packageName: String, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "retro_toolbox/shizuku")
    private val args = Shizuku.UserServiceArgs(ComponentName(packageName, ShellService::class.java.name))
        .daemon(false)
        .processNameSuffix("savesync")
        .debuggable(false)
        .version(SERVICE_VERSION)
    private var service: IShellService? = null
    private var binding = false
    private val waiting = mutableListOf<(IShellService?) -> Unit>()
    private var permissionResult: MethodChannel.Result? = null

    // Shizuku drops a user service that has not started within 30 s and never tells the client.
    private val bindTimeout = Runnable {
        if (binding) {
            binding = false
            flush(null)
        }
    }

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        if (code == PERMISSION_REQUEST) answerPermission(grant == PackageManager.PERMISSION_GRANTED)
    }

    // Shizuku stopped or restarted: nothing bound through it will answer.
    private val deadListener = Shizuku.OnBinderDeadListener {
        service = null
        if (binding) {
            binding = false
            main.removeCallbacks(bindTimeout)
            flush(null)
        }
        answerPermission(false)
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            main.removeCallbacks(bindTimeout)
            val svc = if (binder != null && binder.pingBinder()) IShellService.Stub.asInterface(binder) else null
            service = svc
            binding = false
            flush(svc)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            binding = false
        }
    }

    init {
        channel.setMethodCallHandler(this)
        Shizuku.addRequestPermissionResultListener(permissionListener)
        Shizuku.addBinderDeadListener(deadListener)
    }

    private fun alive(): Boolean = try {
        Shizuku.pingBinder()
    } catch (e: Exception) {
        false
    }

    private fun granted(): Boolean = try {
        alive() && !Shizuku.isPreV11() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (e: Exception) {
        false
    }

    private fun uid(): Int = try {
        Shizuku.getUid()
    } catch (e: Exception) {
        -1
    }

    private fun answerPermission(granted: Boolean) {
        permissionResult?.success(granted)
        permissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val running = alive()
                result.success(mapOf("running" to running, "granted" to granted(), "uid" to if (running) uid() else -1))
            }
            "requestPermission" -> {
                val preV11 = try {
                    Shizuku.isPreV11()
                } catch (e: Exception) {
                    true
                }
                if (!alive() || preV11) {
                    result.success(false)
                } else if (granted()) {
                    result.success(true)
                } else {
                    answerPermission(false) // supersede a request Shizuku never answered
                    permissionResult = result
                    try {
                        Shizuku.requestPermission(PERMISSION_REQUEST)
                    } catch (e: Exception) {
                        answerPermission(false)
                    }
                }
            }
            "exec" -> {
                val argv = call.argument<List<String>>("argv")?.toTypedArray()
                if (argv == null || argv.isEmpty()) {
                    result.error("ARGS", "argv is empty", null)
                    return
                }
                if (!granted()) {
                    result.error("SHIZUKU", "Shizuku is not running or not granted", null)
                    return
                }
                withService { svc ->
                    if (svc == null) {
                        result.error("SHIZUKU", "the shell service did not start", null)
                        return@withService
                    }
                    thread {
                        val reply = try {
                            JSONObject(svc.exec(argv))
                        } catch (e: Exception) {
                            null
                        }
                        main.post {
                            if (reply == null) {
                                if (service === svc) service = null // dead proxy: rebind next time
                                result.error("SHIZUKU", "exec failed", null)
                            } else {
                                result.success(mapOf("code" to reply.getInt("code"), "out" to reply.getString("out"), "err" to reply.getString("err")))
                            }
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun withService(block: (IShellService?) -> Unit) {
        service?.let {
            if (it.asBinder().pingBinder()) {
                block(it)
                return
            }
            service = null
        }
        waiting.add(block)
        if (binding) return
        binding = true
        main.postDelayed(bindTimeout, BIND_TIMEOUT_MS)
        try {
            Shizuku.bindUserService(args, connection)
        } catch (e: Exception) {
            main.removeCallbacks(bindTimeout)
            binding = false
            flush(null)
        }
    }

    private fun flush(svc: IShellService?) {
        val pending = waiting.toList()
        waiting.clear()
        pending.forEach { it(svc) }
    }

    fun dispose() {
        try {
            if (alive()) Shizuku.unbindUserService(args, connection, false)
        } catch (e: Exception) {
        }
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        Shizuku.removeBinderDeadListener(deadListener)
        main.removeCallbacks(bindTimeout)
        binding = false
        flush(null)
        answerPermission(false)
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val PERMISSION_REQUEST = 0x5A5
        const val SERVICE_VERSION = 1
        const val BIND_TIMEOUT_MS = 35_000L
    }
}
