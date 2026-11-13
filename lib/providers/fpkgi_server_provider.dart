import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/fpkgi_server_service.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/utils/network.dart';

const _portKey = 'fpkgi_server_port_v3';

class FpkgiServerState {
  final bool running;
  final int port;
  final List<String> addresses;
  final int activeTransfers;
  final String? error;

  const FpkgiServerState({
    this.running = false,
    this.port = 9095,
    this.addresses = const [],
    this.activeTransfers = 0,
    this.error,
  });

  FpkgiServerState copyWith({bool? running, int? port, List<String>? addresses, int? activeTransfers, String? error, bool clearError = false}) => FpkgiServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        error: clearError ? null : (error ?? this.error),
      );
}

final fpkgiServerProvider = StateNotifierProvider<FpkgiServerNotifier, FpkgiServerState>((ref) {
  return FpkgiServerNotifier(ref);
});

class FpkgiServerNotifier extends StateNotifier<FpkgiServerState> {
  final Ref _ref;
  final _service = FpkgiServerService();
  final _catalogService = CatalogService();

  FpkgiServerNotifier(this._ref) : super(const FpkgiServerState()) {
    TinfoilServerService.activeTransfers.addListener(() {
      if (mounted) state = state.copyWith(activeTransfers: TinfoilServerService.activeTransfers.value);
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
    for (final console in consoles.values.where(FpkgiServerService.isPs4Console)) {
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
    // Same auth as the app's own downloads: IA restricted items want session
    // cookies first, S3 keys as fallback.
    return buildDownloadHeaders(
      console.url,
      {
        ...buildConsoleAuthHeaders(console.auth, tokenOverride: settings.consoleSettings[console.id]?.authToken),
        if (console.usesInternetArchive)
          ...iaAuthHeaders(cookies: settings.iaCookies, accessKey: settings.iaAccessKey, secretKey: settings.iaSecretKey),
      },
    );
  }

  Future<void> enable() async {
    try {
      await _service.start(
        port: state.port,
        loadGames: _loadGames,
        authHeaders: _authHeaders,
        // Packages already downloaded here go out from disk, not the internet.
        downloadDir: (c) => _ref.read(settingsProvider.notifier).getDownloadDir(c.id),
      );
      final addresses = await TinfoilServerService.localAddresses();
      state = state.copyWith(running: true, addresses: addresses, port: _service.port, clearError: true);
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          serviceId: 5,
          notificationTitle: 'FPKGi server running',
          notificationText: 'Serving the PS4 catalog on port ${_service.port}',
          notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
          callback: fpkgiKeepAliveCallback,
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
void fpkgiKeepAliveCallback() {
  // ponytail: no-op handler — the HTTP server lives in the main isolate; this
  // service only keeps the process alive.
  FlutterForegroundTask.setTaskHandler(_FpkgiKeepAliveHandler());
}

class _FpkgiKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
