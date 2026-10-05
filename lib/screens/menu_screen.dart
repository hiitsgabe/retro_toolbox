import 'package:retro_toolbox/utils/handheld.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/sports_grid_screen.dart';
import 'package:retro_toolbox/screens/menu_grid_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/screens/tinfoil_server_screen.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:retro_toolbox/screens/nsz_decompress_screen.dart';
import 'package:retro_toolbox/screens/steam_shortcut_screen.dart';
import 'package:retro_toolbox/screens/add_catalog_source_screen.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/screens/cia_convert_screen.dart';
import 'package:retro_toolbox/screens/m3u_screen.dart';
import 'package:retro_toolbox/screens/chd_convert_screen.dart';
import 'package:retro_toolbox/screens/rts_server_screen.dart';
import 'package:retro_toolbox/screens/fbi_server_screen.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// Root 3DS-style grid: the app's home screen. Owns the first-run setup wizard.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  @override
  void initState() {
    super.initState();
    // Start listening to the downloader at boot: downloads the OS resumed after
    // a crash must reach the task manager before any games screen opens.
    ref.read(downloadProvider);
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// First time into the Games Library, run the setup wizard to configure a
  /// catalog; after that (or once seen) go straight to the console grid. Keeps
  /// setup out of app boot so the rest of the app is usable immediately.
  Future<void> _openGamesLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(SetupWizardScreen.seenKey) ?? false;
    if (!mounted) return;
    if (!seen) {
      await Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SetupWizardScreen()),
      );
      if (!mounted) return;
    }
    _push(const ConsoleGridScreen());
  }

  @override
  Widget build(BuildContext context) {
    // Game states (not queue entries): downloads resumed after a restart have
    // no queue entry but still need the Tasks tile.
    final activeTasks = ref.watch(gameStateManagerProvider.select((m) => m.values.where((g) => g.isActive).length));

    final tiles = [
      MenuTile(
        label: 'Games Library',
        icon: Icons.download,
        accentColor: const Color(0xFF2E6DB4),
        onTap: _openGamesLibrary,
      ),
      MenuTile(
        label: 'Servers',
        icon: Icons.dns,
        accentColor: const Color(0xFF167C80),
        onTap: () => _push(MenuGridScreen(title: 'Servers', tiles: [
          // The handheld keeps the pure-Dart servers that make sense there.
          if (!Handheld.current)
          MenuTile(label: 'Tinfoil Server', icon: Icons.cloud_upload, accentColor: const Color(0xFF167C80), onTap: () => _push(TinfoilServerScreen())),
          if (!Handheld.current)
          MenuTile(label: 'JDKV Server', icon: Icons.folder_shared, accentColor: const Color(0xFF2E7D5B), onTap: () => _push(const JdkvServerScreen())),
          MenuTile(label: 'SMB Share', icon: Icons.folder_open, accentColor: const Color(0xFF7A5CA8), onTap: () => _push(const SmbScreen())),
          MenuTile(label: 'FTP', icon: Icons.cloud_sync, accentColor: const Color(0xFFB4632E), onTap: () => _push(const FtpScreen())),
          MenuTile(label: 'Retro Tools Server', icon: Icons.dns_rounded, accentColor: const Color(0xFF167C80), onTap: () => _push(const RtsServerScreen())),
          if (!Handheld.current)
          MenuTile(label: 'FBI Server', icon: Icons.install_mobile, accentColor: const Color(0xFF9C4DA0), onTap: () => _push(const FbiServerScreen())),
        ])),
      ),
      MenuTile(
        label: 'Tools',
        icon: Icons.build,
        accentColor: const Color(0xFFE56717),
        onTap: () => _push(MenuGridScreen(title: 'Tools', tiles: [
          MenuTile(label: 'NSZ Decompress', icon: Icons.unarchive, accentColor: const Color(0xFFE56717), onTap: () => _push(const NszDecompressScreen())),
          if (!Handheld.current) MenuTile(label: 'Steam Shortcuts', icon: Icons.videogame_asset, accentColor: const Color(0xFF3B6FB5), onTap: () => _push(SteamShortcutScreen())),
          MenuTile(label: 'New Catalog Source', icon: Icons.playlist_add, accentColor: const Color(0xFF2E7D5B), onTap: () => _push(const AddCatalogSourceScreen())),
          MenuTile(label: 'Collection Clean', icon: Icons.cleaning_services, accentColor: const Color(0xFF9C4DA0), onTap: () => _push(const CollectionCleanScreen())),
          MenuTile(label: 'File Explorer', icon: Icons.folder_copy, accentColor: const Color(0xFF2E7D5B), onTap: () => _push(const FileExplorerScreen())),
          if (!Handheld.current || ArchiveExtractService.rarSupported()) MenuTile(label: 'Rar Decompress', icon: Icons.folder_zip, accentColor: const Color(0xFFB4632E), onTap: () => _push(const RarDecompressScreen())),
          MenuTile(label: 'M3U Playlists', icon: Icons.playlist_play, accentColor: const Color(0xFF3B6FB5), onTap: () => _push(const M3uScreen())),
          if (!Handheld.current) MenuTile(label: 'CHD Converter', icon: Icons.compress, accentColor: const Color(0xFF167C80), onTap: () => _push(const ChdConvertScreen())),
          MenuTile(label: '3DS → CIA', icon: Icons.sd_card, accentColor: const Color(0xFF9C4DA0), onTap: () => _push(const CiaConvertScreen())),
        ])),
      ),
      MenuTile(
        label: 'Sports',
        icon: Icons.sports_esports,
        accentColor: const Color(0xFF2E9E4F),
        badge: 'ALPHA',
        onTap: () => _push(const SportsGridScreen()),
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
