import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/services/rts_server_service.dart';

const _portKey = 'rts_server_port';
const _foldersKey = 'rts_server_folders';

class RtsServerState {
  final bool running;
  final int port;
  final List<String> addresses;
  final List<RtsFolder> folders;
  final int activeTransfers;
  final String? error;

  const RtsServerState({
    this.running = false,
    this.port = 8090,
    this.addresses = const [],
    this.folders = const [],
    this.activeTransfers = 0,
    this.error,
  });

  RtsServerState copyWith({
    bool? running,
    int? port,
    List<String>? addresses,
    List<RtsFolder>? folders,
    int? activeTransfers,
    String? error,
    bool clearError = false,
  }) =>
      RtsServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        folders: folders ?? this.folders,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        error: clearError ? null : (error ?? this.error),
      );
}

final rtsServerProvider = StateNotifierProvider<RtsServerNotifier, RtsServerState>((ref) => RtsServerNotifier());

class RtsServerNotifier extends StateNotifier<RtsServerState> {
  final _service = RtsServerService();

  RtsServerNotifier() : super(const RtsServerState()) {
    _service.activeTransfers.addListener(() {
      if (mounted) state = state.copyWith(activeTransfers: _service.activeTransfers.value);
    });
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final port = prefs.getInt(_portKey);
    final raw = prefs.getString(_foldersKey);
    final folders = raw == null
        ? <RtsFolder>[]
        : (jsonDecode(raw) as List).map((e) => RtsFolder.fromJson(Map<String, dynamic>.from(e))).toList();
    if (mounted) state = state.copyWith(port: port ?? state.port, folders: folders);
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_foldersKey, jsonEncode(state.folders.map((f) => f.toJson()).toList()));
    if (state.running) _service.setFolders(state.folders);
  }

  Future<void> addFolder(RtsFolder folder) async {
    if (state.folders.any((f) => f.path == folder.path)) return;
    state = state.copyWith(folders: [...state.folders, folder]);
    await _saveFolders();
  }

  Future<void> updateFolder(int index, RtsFolder folder) async {
    final list = [...state.folders];
    list[index] = folder;
    state = state.copyWith(folders: list);
    await _saveFolders();
  }

  Future<void> removeFolder(int index) async {
    final list = [...state.folders]..removeAt(index);
    state = state.copyWith(folders: list);
    await _saveFolders();
  }

  Future<void> setPort(int port) async {
    state = state.copyWith(port: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portKey, port);
  }

  Future<void> enable() async {
    try {
      await _service.start(port: state.port, folders: state.folders);
      final addresses = await RtsServerService.localAddresses();
      state = state.copyWith(running: true, addresses: addresses, port: _service.port, clearError: true);
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          serviceId: 3,
          notificationTitle: 'Retro Tools Server running',
          notificationText: 'Sharing your library on port ${_service.port}',
          notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
          callback: rtsKeepAliveCallback,
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

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }
}

@pragma('vm:entry-point')
void rtsKeepAliveCallback() {
  // ponytail: no-op handler — the HTTP server lives in the main isolate; this
  // only keeps the process alive. Shares the single foreground slot with the
  // other servers/extraction (last one started wins).
  FlutterForegroundTask.setTaskHandler(_RtsKeepAliveHandler());
}

class _RtsKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
