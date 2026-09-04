import 'package:roms_downloader/models/console_model.dart';

enum ViewMode { list, grid, coverflow }

class AppState {
  final bool loading;
  final Map<String, Console> consoles;
  final Console? selectedConsole;

  /// View for the games list (HomeScreen).
  final ViewMode viewMode;

  /// View for the console picker (ConsoleGridScreen). Independent from games.
  final ViewMode consoleViewMode;

  const AppState({
    this.loading = false,
    this.consoles = const {},
    this.selectedConsole,
    this.viewMode = ViewMode.grid,
    this.consoleViewMode = ViewMode.grid,
  });

  AppState copyWith({
    bool? loading,
    Map<String, Console>? consoles,
    Console? selectedConsole,
    bool clearSelectedConsole = false,
    ViewMode? viewMode,
    ViewMode? consoleViewMode,
  }) {
    return AppState(
      loading: loading ?? this.loading,
      consoles: consoles ?? this.consoles,
      selectedConsole: clearSelectedConsole ? null : (selectedConsole ?? this.selectedConsole),
      viewMode: viewMode ?? this.viewMode,
      consoleViewMode: consoleViewMode ?? this.consoleViewMode,
    );
  }

  List<Console> get consolesList => consoles.values.toList();
}
