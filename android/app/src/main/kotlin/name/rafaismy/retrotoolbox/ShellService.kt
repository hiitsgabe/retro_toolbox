package name.rafaismy.retrotoolbox

import android.content.Context
import androidx.annotation.Keep
import org.json.JSONObject
import kotlin.concurrent.thread
import kotlin.system.exitProcess

/** Runs inside Shizuku's process (uid 2000 over ADB, 0 when Shizuku runs on root). */
class ShellService : IShellService.Stub {
    @Keep
    constructor() : super()

    @Keep
    @Suppress("UNUSED_PARAMETER")
    constructor(context: Context) : super()

    override fun destroy() {
        exitProcess(0)
    }

    override fun exec(argv: Array<String>): String {
        val process = try {
            ProcessBuilder(*argv).start()
        } catch (e: Exception) {
            return reply(127, "", e.message ?: "could not start ${argv.firstOrNull()}")
        }
        process.outputStream.close()
        // A command that hangs is killed before the Dart side gives up (2 minutes).
        val killer = thread {
            try {
                Thread.sleep(KILL_AFTER_MS)
                process.destroy()
            } catch (e: InterruptedException) {
            }
        }
        var err = ""
        val errReader = thread { err = process.errorStream.bufferedReader().readText() }
        val out = process.inputStream.bufferedReader().readText()
        val code = process.waitFor()
        killer.interrupt()
        errReader.join()
        // One binder transaction holds about 1 MB: refuse a huge reply instead of failing the call.
        if (out.length + err.length > MAX_REPLY_CHARS) {
            return reply(75, "", "output too large: ${out.length} chars from ${argv.firstOrNull()}")
        }
        return reply(code, out, err)
    }

    private fun reply(code: Int, out: String, err: String): String =
        JSONObject().put("code", code).put("out", out).put("err", err).toString()

    private companion object {
        const val MAX_REPLY_CHARS = 200_000
        const val KILL_AFTER_MS = 110_000L
    }
}
