import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';
import 'package:roms_downloader/utils/network.dart';

const _portKey = 'fbi_server_port';
const _ipKey = 'fbi_3ds_ip';

class FbiServerState {
  final bool running;
  final int port;
  final List<String> addresses;
  final String threeDsIp;
  final int activeTransfers;
  final String? error;

  const FbiServerState({
    this.running = false,
    this.port = 8091,
    this.addresses = const [],
    this.threeDsIp = '',
    this.activeTransfers = 0,
    this.error,
  });

  FbiServerState copyWith({bool? running, int? port, List<String>? addresses, String? threeDsIp, int? activeTransfers, String? error, bool clearError = false}) =>
      FbiServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        threeDsIp: threeDsIp ?? this.threeDsIp,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        error: clearError ? null : (error ?? this.error),
      );
}

final fbiServerProvider = StateNotifierProvider<FbiServerNotifier, FbiServerState>((ref) => FbiServerNotifier(ref));

class FbiServerNotifier extends StateNotifier<FbiServerState> {
  final Ref _ref;
  final _service = FbiServerService();
  final _catalogService = CatalogService();

  FbiServerNotifier(this._ref) : super(const FbiServerState()) {
    _service.activeTransfers.addListener(() {
      if (mounted) state = state.copyWith(activeTransfers: _service.activeTransfers.value);
    });
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      state = state.copyWith(port: prefs.getInt(_portKey) ?? state.port, threeDsIp: prefs.getString(_ipKey) ?? '');
    });
  }

  Future<Map<Console, List<Game>>> _loadGames() async {
    final settings = _ref.read(settingsProvider);
    final consoles = await _catalogService.getConsoles();
    final result = <Console, List<Game>>{};
    for (final console in consoles.values.where(FbiServerService.is3dsConsole)) {
      try {
        result[console] = await _catalogService.loadCatalog(
          console.id,
          iaAccessKey: settings.iaAccessKey,
          iaSecretKey: settings.iaSecretKey,
          authToken: settings.consoleSettings[console.id]?.authToken,
        );
      } catch (_) {}
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

  /// 3DS games and their URLs on this server (empty until running).
  Future<List<FbiGame>> loadGameList() async {
    if (!state.running || state.addresses.isEmpty) return [];
    final hostPort = '${state.addresses.first}:${state.port}';
    return FbiServerService.games(await _loadGames(), hostPort);
  }

  Future<void> enable() async {
    try {
      await _service.start(port: state.port, loadGames: _loadGames, authHeaders: _authHeaders);
      final addresses = await FbiServerService.localAddresses();
      state = state.copyWith(running: true, addresses: addresses, port: _service.port, clearError: true);
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          serviceId: 4,
          notificationTitle: 'FBI server running',
          notificationText: 'Serving 3DS titles on port ${_service.port}',
          notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
          callback: fbiKeepAliveCallback,
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

  Future<void> setThreeDsIp(String ip) async {
    state = state.copyWith(threeDsIp: ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipKey, ip);
  }

  Future<void> sendToThreeDs(String url) => FbiServerService.sendUrlsToFbi(state.threeDsIp, [url]);

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void fbiKeepAliveCallback() {
  // ponytail: no-op keep-alive; HTTP server runs in the main isolate. Shares
  // the single foreground slot with the other servers.
  FlutterForegroundTask.setTaskHandler(_FbiKeepAliveHandler());
}

class _FbiKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
