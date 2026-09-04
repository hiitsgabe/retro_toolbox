import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/widgets/footer/task_panel_modal.dart';
import 'package:roms_downloader/screens/console_grid_screen.dart';
import 'package:roms_downloader/screens/menu_grid_screen.dart';
import 'package:roms_downloader/screens/settings_screen.dart';
import 'package:roms_downloader/screens/about_screen.dart';
import 'package:roms_downloader/screens/setup_wizard_screen.dart';
import 'package:roms_downloader/screens/tinfoil_server_screen.dart';
import 'package:roms_downloader/screens/jdkv_server_screen.dart';
import 'package:roms_downloader/screens/smb_screen.dart';
import 'package:roms_downloader/screens/ftp_screen.dart';
import 'package:roms_downloader/screens/nsz_decompress_screen.dart';
import 'package:roms_downloader/screens/steam_shortcut_screen.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';

/// Root 3DS-style grid: the app's home screen. Owns the first-run setup wizard.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  bool _wizardChecked = false;

  Future<void> _maybeShowWizard() async {
    if (_wizardChecked) return;
    _wizardChecked = true;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(SetupWizardScreen.seenKey) ?? false;
    if (seen || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SetupWizardScreen()),
    );
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(appStateProvider.select((s) => s.loading));
    if (!loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWizard());
    }

    final hasConsoles = ref.watch(appStateProvider.select((s) => s.consolesList.isNotEmpty));

    final runningCounts = ref.watch(taskQueueProvider.select((s) => s.runningCounts));
    final activeTasks = runningCounts.values.fold<int>(0, (a, b) => a + b);

    final tiles = [
      if (hasConsoles)
        MenuTile(
          label: 'Download Games',
          icon: Icons.download,
          accentColor: const Color(0xFF2E6DB4),
          onTap: () => _push(const ConsoleGridScreen()),
        ),
      MenuTile(
        label: 'Servers',
        icon: Icons.dns,
        accentColor: const Color(0xFF167C80),
        onTap: () => _push(MenuGridScreen(title: 'Servers', tiles: [
          MenuTile(label: 'Tinfoil Server', icon: Icons.cloud_upload, accentColor: const Color(0xFF167C80), onTap: () => _push(TinfoilServerScreen())),
          MenuTile(label: 'JDKV Server', icon: Icons.folder_shared, accentColor: const Color(0xFF2E7D5B), onTap: () => _push(const JdkvServerScreen())),
          MenuTile(label: 'SMB Share', icon: Icons.folder_open, accentColor: const Color(0xFF7A5CA8), onTap: () => _push(const SmbScreen())),
          MenuTile(label: 'FTP', icon: Icons.cloud_sync, accentColor: const Color(0xFFB4632E), onTap: () => _push(const FtpScreen())),
        ])),
      ),
      MenuTile(
        label: 'Tools',
        icon: Icons.build,
        accentColor: const Color(0xFFE56717),
        onTap: () => _push(MenuGridScreen(title: 'Tools', tiles: [
          MenuTile(label: 'NSZ Decompress', icon: Icons.unarchive, accentColor: const Color(0xFFE56717), onTap: () => _push(const NszDecompressScreen())),
          MenuTile(label: 'Steam Shortcuts', icon: Icons.videogame_asset, accentColor: const Color(0xFF3B6FB5), onTap: () => _push(SteamShortcutScreen())),
        ])),
      ),
      MenuTile(
        label: 'Settings',
        icon: Icons.settings,
        accentColor: const Color(0xFF55606E),
        onTap: () => _push(const SettingsScreen(consoleId: null)),
      ),
      MenuTile(
        label: 'About',
        icon: Icons.info_outline,
        accentColor: const Color(0xFF6C4AB6),
        onTap: () => _push(AboutScreen()),
      ),
    ];

    // Task manager surfaces as a menu tile only while work is running.
    if (activeTasks > 0) {
      tiles.insert(
        0,
        MenuTile(
          label: 'Tasks ($activeTasks)',
          icon: Icons.sync,
          accentColor: const Color(0xFF8A5CF0),
          onTap: () => TaskPanelModal.show(context),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon.png', height: 30),
            const SizedBox(width: 10),
            const Text('Retro Toolbox', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: MenuGrid(tiles: tiles),
    );
  }
}
