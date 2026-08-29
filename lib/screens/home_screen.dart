import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/app_state_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';
import 'package:roms_downloader/widgets/game_list/game_list.dart';
import 'package:roms_downloader/widgets/game_grid/game_grid.dart';
import 'package:roms_downloader/widgets/footer/footer.dart';
import 'package:roms_downloader/screens/settings_screen.dart';
import 'package:roms_downloader/screens/setup_wizard_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _wizardChecked = false;

  Future<void> _maybeShowWizard() async {
    if (_wizardChecked) return;
    _wizardChecked = true;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(SetupWizardScreen.seenKey) ?? false;
    // Always onboard on first run; the wizard marks itself seen on Finish so it
    // never reappears — even when a catalog is already bundled.
    if (seen || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SetupWizardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final appStateNotifier = ref.read(appStateProvider.notifier);
    // Trigger the first-run wizard once the initial catalog load settles.
    if (!appState.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWizard());
    }
    final loadingStatus = ref.watch(catalogProvider.select((s) => s.loadingStatus));
    final errorMessage = ref.watch(catalogProvider.select((s) => s.errorMessage));

    return Scaffold(
      body: Column(
        children: [
          Header(
            consoles: appState.consolesList,
            selectedConsole: appState.selectedConsole,
            onConsoleSelect: appStateNotifier.selectConsole,
          ),
          Expanded(
            child: appState.consolesList.isEmpty && !appState.loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dataset_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          const Text('No catalog configured', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a console catalog to get started: import a JSON file or load one from a URL.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen(consoleId: null)),
                            ),
                            icon: const Icon(Icons.settings),
                            label: const Text('Open Settings'),
                          ),
                        ],
                      ),
                    ),
                  )
                : appState.loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(loadingStatus.isEmpty ? 'Loading (this can take a while)...' : '$loadingStatus...'),
                      ],
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                              const SizedBox(height: 12),
                              Text(errorMessage, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : appState.viewMode == ViewMode.grid
                        ? GameGrid()
                        : GameList(),
          ),
          Footer(),
        ],
      ),
    );
  }
}
