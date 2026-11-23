package name.rafaismy.retrotoolbox

import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/// Retro Toolbox as the device's home app: the HomeAlias that carries the
/// HOME filter, whether this app holds the home role now, and the intent
/// that opens the home task.
internal object HomeRole {
    /// On an intent ExternalEntryActivity forwarded: an app start, not a
    /// Home press.
    const val EXTRA_ENTRY = "name.rafaismy.retrotoolbox.ENTRY"

    // By the class's own package: a debug build's applicationId ends in
    // ".dev", its classes do not.
    private fun alias(context: Context) =
        ComponentName(context.packageName, "${MainActivity::class.java.name.substringBeforeLast('.')}.HomeAlias")

    /// Off is the manifest's own state, so a reinstall starts from it too.
    fun setAliasEnabled(context: Context, on: Boolean) {
        val state = if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        context.packageManager.setComponentEnabledSetting(alias(context), state, PackageManager.DONT_KILL_APP)
    }

    fun aliasEnabled(context: Context): Boolean =
        context.packageManager.getComponentEnabledSetting(alias(context)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    /// Valid on every API level: the role where Android has one, else the
    /// app a HOME intent resolves to (below API 29, where there is no
    /// RoleManager, or a TV or OEM build without the home role).
    fun held(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = context.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME)) return roles.isRoleHeld(RoleManager.ROLE_HOME)
        }
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        return context.packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName == context.packageName
    }

    /// Retro Toolbox is the home app now: offered as one, and the one picked.
    fun isHome(context: Context): Boolean = aliasEnabled(context) && held(context)

    /// The system dialog that asks for the home role, or null where there is
    /// no role to ask for: the home settings page is the way there.
    fun requestIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val roles = context.getSystemService(RoleManager::class.java) ?: return null
        return if (roles.isRoleAvailable(RoleManager.ROLE_HOME)) roles.createRequestRoleIntent(RoleManager.ROLE_HOME) else null
    }

    /// The app stopped being the home app: HOME was turned off, or another
    /// home app was picked. Not the same as !isHome: with no home app picked
    /// ("ask every time", which below API 29 comes back whenever another app
    /// with a HOME filter is installed) the held check reads false, and yet
    /// the user may pick Retro Toolbox just once, so a HOME activity started
    /// that way is still the home app.
    fun homeLost(context: Context): Boolean = !aliasEnabled(context) || otherHome(context)

    private fun otherHome(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = context.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME)) return !roles.isRoleHeld(RoleManager.ROLE_HOME)
        }
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val preferred = pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        @Suppress("DEPRECATION")
        val homes = pm.queryIntentActivities(home, 0).mapNotNull { it.activityInfo?.packageName }
        return pickedOther(preferred, homes, context.packageName)
    }

    /// [preferred] is what a HOME intent resolves to: the home app when one
    /// is picked, else the system's chooser, which is none of [homes] (its
    /// package differs between Android builds, so it is not named here).
    fun pickedOther(preferred: String?, homes: Collection<String>, own: String): Boolean =
        preferred != null && preferred != own && preferred in homes

    /// What the plugins are handed for [intent]. An app start forwarded to
    /// the home task goes to them in its launcher shape, MAIN with LAUNCHER,
    /// as getLaunchIntentForPackage gave it before HOME: flutter_foreground_task
    /// answers a notification tap only on that shape. The HOME intent itself
    /// keeps its HOME category, the one that makes the activity a home one.
    /// Anything else, a Home press too, goes as it is.
    fun forPlugins(intent: Intent): Intent {
        if (!intent.hasCategory(Intent.CATEGORY_HOME) || !intent.getBooleanExtra(EXTRA_ENTRY, false)) return intent
        return Intent(intent).setAction(Intent.ACTION_MAIN).apply {
            removeCategory(Intent.CATEGORY_HOME)
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
    }

    /// [base], the cached engine intent of a handover to a standard task, with
    /// the app start that set it off: its data and extras, and the launcher
    /// shape the plugins look for (see forPlugins). With no app start it is
    /// no launcher intent.
    fun standardEntry(base: Intent, incoming: Intent?): Intent {
        if (incoming == null) return base
        incoming.data?.let { base.data = it }
        incoming.extras?.let { base.putExtras(it) }
        return base.setAction(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    }

    /// Names no component, so the activity it starts gets the HOME activity
    /// type, as one a Home press starts does; a standard task is never reused
    /// for it.
    fun homeIntent(context: Context): Intent =
        Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .setPackage(context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
