package name.rafaismy.retrotoolbox

import android.content.Context
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// The second screen. Touch scrolls it; the controller always drives the
/// main screen.
///
/// Its window takes focus. Each display keeps its own focused window, and a
/// touch here makes this display the one the controller's keys go to: with no
/// focusable window on it, every press waited for one and the system reported
/// the app as not responding. Now they arrive here and are handed to the main
/// screen, whose window never loses its own focus.
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
        CompanionBridge.attach(this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        CompanionBridge.mainActivity?.dispatchKeyEvent(event) ?: super.dispatchKeyEvent(event)

    // Sticks and hat d-pads come as motion, not keys. Pointer motion (mouse,
    // touchpad) stays here.
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val main = CompanionBridge.mainActivity
        val controller = event.isFromSource(InputDevice.SOURCE_JOYSTICK) || event.isFromSource(InputDevice.SOURCE_GAMEPAD)
        return if (main != null && controller) main.dispatchGenericMotionEvent(event) else super.dispatchGenericMotionEvent(event)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = CompanionBridge.engine(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onDestroy() {
        CompanionBridge.detach(this)
        super.onDestroy()
    }
}
