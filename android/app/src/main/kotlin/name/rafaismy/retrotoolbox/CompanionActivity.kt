package name.rafaismy.retrotoolbox

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// The second screen. Never focusable, so the controller keeps driving the
/// main screen; touch still scrolls it.
class CompanionActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Brought back by the system in a new process, which nothing asked
        // for: the main app opens its own when it plans. A restart in this
        // process finds the engine still cached and stays.
        val restored = savedInstanceState != null && !CompanionBridge.hasEngine()
        super.onCreate(savedInstanceState)
        if (restored) {
            finish()
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
        CompanionBridge.attach(this)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = CompanionBridge.engine(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onDestroy() {
        CompanionBridge.detach(this)
        super.onDestroy()
    }
}
