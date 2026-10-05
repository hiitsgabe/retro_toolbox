import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:retro_toolbox/widgets/game_list/game_list.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid.dart';
import 'package:retro_toolbox/widgets/game_grid/game_cover_flow.dart';
import 'package:retro_toolbox/widgets/footer/footer.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final appStateNotifier = ref.read(appStateProvider.notifier);
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
                        HammerLoader(),
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
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: appState.selectedConsole == null
                                        ? null
                                        : () => ref.read(catalogProvider.notifier).loadCatalog(appState.selectedConsole!),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                  // Never a dead end: a console that fails to load
                                  // leads back to the console list.
                                  OutlinedButton.icon(
                                    autofocus: true,
                                    onPressed: () => Navigator.maybePop(context),
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Choose another console'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : switch (appState.viewMode) {
                        ViewMode.grid => GameGrid(),
                        ViewMode.coverflow => const GameCoverFlow(),
                        ViewMode.list => GameList(),
                      },
          ),
          Footer(),
        ],
      ),
    );
  }
}
