import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/permission_service.dart';

const _viewModeKey = 'view_mode';
const _consoleViewModeKey = 'console_view_mode';
const _selectedConsoleKey = 'selected_console';

ViewMode _parseViewMode(String? name) =>
    ViewMode.values.firstWhere((m) => m.name == name, orElse: () => ViewMode.grid);

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  final catalogService = CatalogService();
  final catalogNotifier = ref.read(catalogProvider.notifier);
  return AppStateNotifier(ref, catalogService, catalogNotifier);
});

class AppStateNotifier extends StateNotifier<AppState> {
  final Ref _ref;
  final CatalogService catalogService;
  final CatalogNotifier catalogNotifier;

  AppStateNotifier(this._ref, this.catalogService, this.catalogNotifier) : super(const AppState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    await PermissionService.ensurePermissions();

    final prefs = await SharedPreferences.getInstance();
    final savedViewMode = _parseViewMode(prefs.getString(_viewModeKey));
    final savedConsoleViewMode = _parseViewMode(prefs.getString(_consoleViewModeKey));

    final consoles = await catalogService.getConsoles();
    
    final savedConsoleId = prefs.getString(_selectedConsoleKey);
    final selectedConsole = (savedConsoleId != null && consoles.containsKey(savedConsoleId))
        ? consoles[savedConsoleId]
        : consoles.isNotEmpty ? consoles.values.first : null;

    state = state.copyWith(
      consoles: consoles,
      selectedConsole: selectedConsole,
      viewMode: savedViewMode,
      consoleViewMode: savedConsoleViewMode,
    );

    _listenToLoadingNotifications();
    // The saved console is only a highlight: a catalog loads when the user
    // opens a console (selectConsole), never on startup.
  }

  /// Re-reads the console list after the catalog source changes.
  Future<void> reloadConsoles() async {
    final consoles = await catalogService.getConsoles();
    final prefs = await SharedPreferences.getInstance();
    final savedConsoleId = prefs.getString(_selectedConsoleKey);
    final selectedConsole = (savedConsoleId != null && consoles.containsKey(savedConsoleId))
        ? consoles[savedConsoleId]
        : consoles.isNotEmpty
            ? consoles.values.first
            : null;

    state = state.copyWith(
      consoles: consoles,
      selectedConsole: selectedConsole,
      clearSelectedConsole: selectedConsole == null,
    );
    // Refresh the open games screen only; nothing loads from the console list.
    final c = catalogNotifier.state;
    if (selectedConsole != null && (c.loading || c.games.isNotEmpty || c.errorMessage.isNotEmpty)) {
      catalogNotifier.loadCatalog(selectedConsole);
    }
  }

  void _listenToLoadingNotifications() {
    _ref.listen<CatalogState>(catalogProvider, (previous, next) {
      if (previous?.loading != next.loading) {
        state = state.copyWith(loading: next.loading);
      }
    });
  }

  void selectConsole(Console console) {
    state = state.copyWith(selectedConsole: console);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_selectedConsoleKey, console.id));
    catalogNotifier.loadCatalog(console);
  }

  void setLoading(bool loading) {
    state = state.copyWith(loading: loading);
  }

  void toggleViewMode() {
    // Cycle grid -> list -> coverflow -> grid
    final newMode = ViewMode.values[(state.viewMode.index + 1) % ViewMode.values.length];
    state = state.copyWith(viewMode: newMode);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_viewModeKey, newMode.name));
  }

  void toggleConsoleViewMode() {
    final newMode = ViewMode.values[(state.consoleViewMode.index + 1) % ViewMode.values.length];
    state = state.copyWith(consoleViewMode: newMode);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_consoleViewModeKey, newMode.name));
  }

  void setViewMode(ViewMode mode) {
    state = state.copyWith(viewMode: mode);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_viewModeKey, mode.name));
  }
}
