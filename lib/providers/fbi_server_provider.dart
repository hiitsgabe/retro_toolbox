import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';
import 'package:roms_downloader/services/nsz_service.dart';
import 'package:roms_downloader/utils/network.dart';

const _portKey = 'fbi_server_port_v2';
const _ipKey = 'fbi_3ds_ip';

class FbiServerState {
  final bool running;
  final int port;
  final List<String> addresses;
  final String threeDsIp;
  final int activeTransfers;
  final List<FbiGame> games;
  final bool gamesLoading;
  final String? error;

  const FbiServerState({
    this.running = false,
    this.port = 9094,
    this.addresses = const [],
    this.threeDsIp = '',
    this.activeTransfers = 0,
    this.games = const [],
    this.gamesLoading = false,
    this.error,
  });

  FbiServerState copyWith({
    bool? running,
    int? port,
    List<String>? addresses,
    String? threeDsIp,
    int? activeTransfers,
    List<FbiGame>? games,
    bool? gamesLoading,
    String? error,
    bool clearError = false,
  }) =>
      FbiServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        threeDsIp: threeDsIp ?? this.threeDsIp,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        games: games ?? this.games,
        gamesLoading: gamesLoading ?? this.gamesLoading,
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

  String? get _hostPort => state.addresses.isEmpty
      ? null
      : '${orderAddresses(state.addresses, _ref.read(settingsProvider).preferredLocalIp).first}:${state.port}';

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

  Future<void> refreshGames() async {
    if (!state.running) return;
    state = state.copyWith(gamesLoading: true);
    try {
      final games = FbiServerService.games(await _loadGames());
      if (mounted) state = state.copyWith(games: games, gamesLoading: false);
    } catch (e) {
      if (mounted) state = state.copyWith(gamesLoading: false, error: '$e');
    }
  }

  Future<void> enable() async {
    try {
      final cache = Directory(p.join((await getApplicationSupportDirectory()).path, 'fbi_cache'));
      await _service.start(port: state.port, cacheDir: cache);
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
      refreshGames();
    } catch (e) {
      state = state.copyWith(running: false, error: '$e');
    }
  }

  Future<void> disable() async {
    await _service.stop();
    if (Platform.isAndroid) await FlutterForegroundTask.stopService();
    state = state.copyWith(running: false, addresses: const [], games: const []);
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

  Future<void> sendUrlToThreeDs(String url) => FbiServerService.sendUrlsToFbi(state.threeDsIp, [url]);

  /// Stages [srcPath] into the served cache as a .cia (copying, unzipping and/or
  /// converting as needed), and returns the URL FBI can install it from.
  /// [onProgress] reports 0–1 during conversion. Throws on failure.
  Future<String> prepareLocalFile(String srcPath, void Function(double) onProgress) async {
    final host = _hostPort;
    final cache = _service.cacheDir;
    if (host == null || cache == null) throw StateError('Server is not running.');
    final name = await _stageToCache(srcPath, cache, onProgress);
    return _service.ciaUrl(host, name);
  }

  /// Downloads a catalog title (with source auth), then stages it like a local
  /// file. [onProgress] covers download (0–0.5) then conversion (0.5–1).
  Future<String> prepareCatalog(FbiGame g, void Function(double) onProgress) async {
    final host = _hostPort;
    final cache = _service.cacheDir;
    if (host == null || cache == null) throw StateError('Server is not running.');
    final tmp = Directory(p.join(cache.path, '_dl'))..createSync(recursive: true);
    final dlPath = p.join(tmp.path, p.basename(Uri.parse(g.game.url).path));
    await _download(g.game.url, _authHeaders(g.console), dlPath, (d) => onProgress(d * 0.5));
    try {
      final name = await _stageToCache(dlPath, cache, (c) => onProgress(0.5 + c * 0.5));
      return _service.ciaUrl(host, name);
    } finally {
      try {
        File(dlPath).deleteSync();
      } catch (_) {}
    }
  }

  Future<String> _stageToCache(String srcPath, Directory cache, void Function(double) onProgress) async {
    final ext = p.extension(srcPath).toLowerCase();
    if (ext == '.cia') {
      final dest = File(p.join(cache.path, p.basename(srcPath)));
      await File(srcPath).copy(dest.path);
      onProgress(1.0);
      return p.basename(dest.path);
    }
    if (ext == '.zip') {
      final unz = Directory(p.join(cache.path, '_unz'))..createSync(recursive: true);
      try {
        await extractFileToDisk(srcPath, unz.path);
        final inner = unz
            .listSync(recursive: true)
            .whereType<File>()
            .firstWhere(
              (f) => {'.cia', '.3ds', '.cci'}.contains(p.extension(f.path).toLowerCase()),
              orElse: () => throw StateError('No .cia/.3ds found inside the zip'),
            );
        return await _stageToCache(inner.path, cache, onProgress);
      } finally {
        try {
          unz.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    if (ext == '.3ds' || ext == '.cci') {
      final before = cache.listSync().whereType<File>().map((f) => f.path).toSet();
      await NszService.convert3dsToCia(
        inputFile: srcPath,
        outputDir: cache.path,
        boot9Path: _ref.read(settingsProvider).boot9Path,
        onProgress: onProgress,
      );
      final made = cache.listSync().whereType<File>().where((f) => p.extension(f.path).toLowerCase() == '.cia' && !before.contains(f.path)).toList();
      if (made.isEmpty) throw StateError('Conversion produced no CIA');
      return p.basename(made.first.path);
    }
    throw UnsupportedError('Unsupported file type: $ext');
  }

  Future<void> _download(String url, Map<String, String> headers, String destPath, void Function(double) onProgress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    client.autoUncompress = false;
    try {
      final finalUrl = await resolveRedirects(url, headers);
      final req = await client.getUrl(Uri.parse(finalUrl));
      headers.forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode} downloading $url');
      final total = res.contentLength;
      final sink = File(destPath).openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void fbiKeepAliveCallback() {
  // ponytail: no-op keep-alive; the HTTP server runs in the main isolate.
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
