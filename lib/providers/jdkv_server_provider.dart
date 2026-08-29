import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/jksv_backend.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';
import 'package:roms_downloader/services/webdav_server_service.dart';

const _portKey = 'jdkv_server_port';
const _folderKey = 'jdkv_export_folder';
final _titleIdInUrl = RegExp(r'01[0-9A-Fa-f]{14}');

class JdkvServerState {
  final bool running;
  final int port;
  final String? folder;
  final List<String> addresses;
  final List<IncomingSave> incoming;
  final int activeTransfers;
  final String? error;

  const JdkvServerState({
    this.running = false,
    this.port = 8081,
    this.folder,
    this.addresses = const [],
    this.incoming = const [],
    this.activeTransfers = 0,
    this.error,
  });

  JdkvServerState copyWith({
    bool? running,
    int? port,
    String? folder,
    List<String>? addresses,
    List<IncomingSave>? incoming,
    int? activeTransfers,
    String? error,
    bool clearError = false,
  }) =>
      JdkvServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        folder: folder ?? this.folder,
        addresses: addresses ?? this.addresses,
        incoming: incoming ?? this.incoming,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        error: clearError ? null : (error ?? this.error),
      );
}

final jdkvServerProvider = StateNotifierProvider<JdkvServerNotifier, JdkvServerState>((ref) {
  return JdkvServerNotifier();
});

class JdkvServerNotifier extends StateNotifier<JdkvServerState> {
  final _server = WebDavServerService();
  final _catalogService = CatalogService();
  Map<String, String> _titleNames = {};

  JdkvServerNotifier() : super(const JdkvServerState()) {
    _server.activeTransfers.addListener(() {
      if (mounted) state = state.copyWith(activeTransfers: _server.activeTransfers.value);
    });
    _server.incoming.addListener(() {
      if (mounted) state = state.copyWith(incoming: _server.incoming.value);
    });
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      state = state.copyWith(port: prefs.getInt(_portKey) ?? state.port, folder: prefs.getString(_folderKey));
    });
  }

  /// Title id → game name, harvested from the Switch catalog (title id lives in
  /// each game's download URL). Falls back to the raw id when unmapped.
  Future<void> _buildNameMap() async {
    if (_titleNames.isNotEmpty) return;
    final map = <String, String>{};
    try {
      final consoles = await _catalogService.getConsoles();
      for (final c in consoles.values.where(TinfoilServerService.isSwitchConsole)) {
        final games = await _catalogService.loadCatalog(c.id);
        for (final g in games) {
          final m = _titleIdInUrl.firstMatch(g.url);
          if (m != null) map[m.group(0)!.toUpperCase()] = g.displayTitle;
        }
      }
    } catch (_) {}
    _titleNames = map;
  }

  Future<void> setPort(int port) async {
    state = state.copyWith(port: port);
    (await SharedPreferences.getInstance()).setInt(_portKey, port);
  }

  Future<void> setFolder(String path) async {
    state = state.copyWith(folder: path);
    (await SharedPreferences.getInstance()).setString(_folderKey, path);
  }

  JksvBackend? _backend() {
    final folder = state.folder;
    if (folder == null) return null;
    return JksvBackend(
      root: Directory(folder),
      nameFor: (id) => _titleNames[id.toUpperCase()] ?? id,
    );
  }

  Future<void> enable() async {
    final backend = _backend();
    if (backend == null) {
      state = state.copyWith(error: 'Pick a folder with your emulator save exports first.');
      return;
    }
    try {
      await _buildNameMap();
      await _server.start(port: state.port, backend: backend);
      final addresses = await WebDavServerService.localAddresses();
      state = state.copyWith(running: true, port: _server.port, addresses: addresses, clearError: true);
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          serviceId: 3,
          notificationTitle: 'JDKV server running',
          notificationText: 'Sharing saves on port ${_server.port}',
          notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
          callback: jdkvKeepAliveCallback,
        );
      }
    } catch (e) {
      state = state.copyWith(running: false, error: '$e');
    }
  }

  Future<void> disable() async {
    await _server.stop();
    if (Platform.isAndroid) await FlutterForegroundTask.stopService();
    state = state.copyWith(running: false, addresses: const []);
  }

  /// Pull a confirmed incoming Switch save into the export folder (req #1/#2):
  /// backs up the current export, then writes the new one.
  Future<void> pull(String titleId, {required String timestamp}) async {
    final backend = _backend();
    final bytes = _server.takeStaged(titleId);
    if (backend == null || bytes == null) return;
    try {
      backend.applyIncoming(titleId, bytes, timestamp: timestamp);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void jdkvKeepAliveCallback() {
  // ponytail: no-op handler — the WebDAV server lives in the main isolate; this
  // only keeps the process alive. Shares the single foreground slot.
  FlutterForegroundTask.setTaskHandler(_JdkvKeepAliveHandler());
}

class _JdkvKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
