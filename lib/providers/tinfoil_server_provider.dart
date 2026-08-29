import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';
import 'package:roms_downloader/utils/network.dart';

const _portKey = 'tinfoil_server_port';

class TinfoilServerState {
  final bool running;
  final int port;
  final List<String> addresses;
  final int activeTransfers;
  final String? error;

  const TinfoilServerState({
    this.running = false,
    this.port = 8000,
    this.addresses = const [],
    this.activeTransfers = 0,
    this.error,
  });

  TinfoilServerState copyWith({bool? running, int? port, List<String>? addresses, int? activeTransfers, String? error, bool clearError = false}) =>
      TinfoilServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        error: clearError ? null : (error ?? this.error),
      );
}

final tinfoilServerProvider = StateNotifierProvider<TinfoilServerNotifier, TinfoilServerState>((ref) {
  return TinfoilServerNotifier(ref);
});

class TinfoilServerNotifier extends StateNotifier<TinfoilServerState> {
  final Ref _ref;
  final _service = TinfoilServerService();
  final _catalogService = CatalogService();

  TinfoilServerNotifier(this._ref) : super(const TinfoilServerState()) {
    _service.activeTransfers.addListener(() {
      if (mounted) state = state.copyWith(activeTransfers: _service.activeTransfers.value);
    });
    SharedPreferences.getInstance().then((prefs) {
      final port = prefs.getInt(_portKey);
      if (port != null && mounted) state = state.copyWith(port: port);
    });
  }

  Future<Map<Console, List<Game>>> _loadGames() async {
    final settings = _ref.read(settingsProvider);
    final consoles = await _catalogService.getConsoles();
    final result = <Console, List<Game>>{};
    for (final console in consoles.values.where(TinfoilServerService.isSwitchConsole)) {
      try {
        result[console] = await _catalogService.loadCatalog(
          console.id,
          iaAccessKey: settings.iaAccessKey,
          iaSecretKey: settings.iaSecretKey,
          authToken: settings.consoleSettings[console.id]?.authToken,
        );
      } catch (_) {
        // Skip consoles whose catalog fails to load; the rest still serve.
      }
    }
    return result;
  }

  Map<String, String> _authHeaders(Console console) {
    final settings = _ref.read(settingsProvider);
    final headers = buildDownloadHeaders(
      console.url,
      buildConsoleAuthHeaders(console.auth, tokenOverride: settings.consoleSettings[console.id]?.authToken),
    );
    if (console.auth?['type'] == 'ia_s3' && (settings.iaAccessKey?.isNotEmpty ?? false)) {
      headers['Authorization'] = 'LOW ${settings.iaAccessKey}:${settings.iaSecretKey}';
    }
    return headers;
  }

  Future<void> enable() async {
    try {
      await _service.start(port: state.port, loadGames: _loadGames, authHeaders: _authHeaders);
      final addresses = await TinfoilServerService.localAddresses();
      state = state.copyWith(running: true, addresses: addresses, port: _service.port, clearError: true);
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          serviceId: 2,
          notificationTitle: 'Tinfoil server running',
          notificationText: 'Serving the catalog on port ${_service.port}',
          notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
          callback: tinfoilKeepAliveCallback,
        );
      }
    } catch (e) {
      state = state.copyWith(running: false, error: '$e');
    }
  }

  Future<void> disable() async {
    await _service.stop();
    if (Platform.isAndroid) await FlutterForegroundTask.stopService();
    state = state.copyWith(running: false, addresses: const []);
  }

  Future<void> setPort(int port) async {
    state = state.copyWith(port: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portKey, port);
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void tinfoilKeepAliveCallback() {
  // ponytail: no-op handler — the HTTP server lives in the main isolate; this
  // service only keeps the process alive. Known ceiling: the extraction
  // service shares the single foreground slot and may replace/stop it.
  FlutterForegroundTask.setTaskHandler(_TinfoilKeepAliveHandler());
}

class _TinfoilKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
