package name.rafaismy.retrotoolbox

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/// The app's launcher entry, so also what getLaunchIntentForPackage opens:
/// Settings > Open, and a tap on the download or foreground service
/// notification. It shows nothing. As the home app it goes on to the home
/// task, so no second MainActivity, and no second Flutter engine, starts
/// beside it; otherwise to MainActivity, whose task a NEW_TASK start by
/// component finds, as the launcher icon did when it named MainActivity,
/// unless the engine is still in a home task the app no longer holds.
class ExternalEntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val home = try {
            HomeRole.isHome(this)
        } catch (_: Exception) {
            false
        }
        val forward = if (home) {
            // A HOME MainActivity this starts takes the engine from a standard
            // task that still holds it (MainActivity.takeStrandedEngine).
            HomeRole.homeIntent(this)
        } else {
            // A HOME intent with data would match no HOME filter, so only
            // this one carries it.
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                .also { f -> intent?.data?.let { f.data = it } }
        }
        intent?.extras?.let { forward.putExtras(it) }
        forward.putExtra(HomeRole.EXTRA_ENTRY, true)
        // Not the home app, while a MainActivity started as one still runs
        // the engine in the home task (another home app was picked in system
        // Settings with Retro Toolbox in the background). A start by
        // component never reaches the home task, so it would begin a second
        // engine beside that one: the engine comes over instead, started from
        // here because this is the activity in front.
        val stranded = if (home) null else MainActivity.runningAsHome()
        if (stranded != null && stranded.handOverToStandard(this, forward)) {
            finish()
            return
        }
        try {
            startActivity(forward)
        } catch (_: Exception) {
            // The alias went off between the check and the start.
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        // Theme.NoDisplay: finished before onResume, or Android stops the app.
        finish()
    }
}
