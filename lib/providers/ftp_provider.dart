import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roms_downloader/services/ftp_service.dart';

enum FtpMode { client, server }

const _hostKey = 'ftp_host';
const _portKey = 'ftp_port';
const _userKey = 'ftp_user';
const _srvDirKey = 'ftp_server_dir';
const _srvPortKey = 'ftp_server_port';

class FtpTransfer {
  final String name;
  final int done;
  final int total;
  final bool upload;
  const FtpTransfer({required this.name, required this.done, required this.total, required this.upload});
  double get fraction => total > 0 ? done / total : 0;
}

class FtpState {
  final FtpMode mode;

  // Client
  final bool connected;
  final bool busy;
  final String host;
  final int port;
  final String username;
  final String path;
  final List<FTPEntry> entries;
  final Set<String> selected; // selected entry names in the current dir
  final FtpTransfer? transfer;
  final String? error;

  // Server
  final bool serverRunning;
  final String serverDir;
  final int serverPort;
  final bool serverReadOnly;
  final List<String> serverAddresses;
  final String? serverError;

  const FtpState({
    this.mode = FtpMode.client,
    this.connected = false,
    this.busy = false,
    this.host = '',
    this.port = 21,
    this.username = '',
    this.path = '/',
    this.entries = const [],
    this.selected = const {},
    this.transfer,
    this.error,
    this.serverRunning = false,
    this.serverDir = '',
    this.serverPort = 2121,
    this.serverReadOnly = false,
    this.serverAddresses = const [],
    this.serverError,
  });

  List<FTPEntry> get selectedEntries => entries.where((e) => selected.contains(e.name)).toList();
  List<FTPEntry> get selectedFiles => selectedEntries.where((e) => e.type != FTPEntryType.dir).toList();

  FtpState copyWith({
    FtpMode? mode,
    bool? connected,
    bool? busy,
    String? host,
    int? port,
    String? username,
    String? path,
    List<FTPEntry>? entries,
    Set<String>? selected,
    FtpTransfer? transfer,
    bool clearTransfer = false,
    String? error,
    bool clearError = false,
    bool? serverRunning,
    String? serverDir,
    int? serverPort,
    bool? serverReadOnly,
    List<String>? serverAddresses,
    String? serverError,
    bool clearServerError = false,
  }) =>
      FtpState(
        mode: mode ?? this.mode,
        connected: connected ?? this.connected,
        busy: busy ?? this.busy,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        path: path ?? this.path,
        entries: entries ?? this.entries,
        selected: selected ?? this.selected,
        transfer: clearTransfer ? null : (transfer ?? this.transfer),
        error: clearError ? null : (error ?? this.error),
        serverRunning: serverRunning ?? this.serverRunning,
        serverDir: serverDir ?? this.serverDir,
        serverPort: serverPort ?? this.serverPort,
        serverReadOnly: serverReadOnly ?? this.serverReadOnly,
        serverAddresses: serverAddresses ?? this.serverAddresses,
        serverError: clearServerError ? null : (serverError ?? this.serverError),
      );
}

final ftpProvider = StateNotifierProvider<FtpNotifier, FtpState>((ref) => FtpNotifier());

class FtpNotifier extends StateNotifier<FtpState> {
  final _client = FtpClientService();
  final _server = FtpServerService();

  FtpNotifier() : super(const FtpState()) {
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      state = state.copyWith(
        host: prefs.getString(_hostKey) ?? '',
        port: prefs.getInt(_portKey) ?? 21,
        username: prefs.getString(_userKey) ?? '',
        serverDir: prefs.getString(_srvDirKey) ?? '',
        serverPort: prefs.getInt(_srvPortKey) ?? 2121,
      );
    });
  }

  void setMode(FtpMode mode) => state = state.copyWith(mode: mode, clearError: true, clearServerError: true);

  // ---- Client --------------------------------------------------------------

  Future<void> connect({required String host, required int port, required String username, required String password}) async {
    state = state.copyWith(busy: true, clearError: true, host: host, port: port, username: username);
    try {
      await _client.connect(host: host, port: port, user: username, pass: password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, host);
      await prefs.setInt(_portKey, port);
      await prefs.setString(_userKey, username);
      state = state.copyWith(connected: true);
      await refresh();
    } catch (e) {
      state = state.copyWith(busy: false, connected: false, error: '$e');
    }
  }

  Future<void> disconnect() async {
    await _client.disconnect();
    state = state.copyWith(connected: false, path: '/', entries: const [], selected: const {}, clearTransfer: true, clearError: true);
  }

  Future<void> open(FTPEntry dir) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _client.cd(dir.name);
      await _reload();
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  Future<void> goUp() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _client.cd('..');
      await _reload();
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _reload();
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  Future<void> _reload() async {
    final entries = await _client.list();
    entries.sort((a, b) {
      final ad = a.type == FTPEntryType.dir;
      final bd = b.type == FTPEntryType.dir;
      if (ad != bd) return ad ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final path = await _client.pwd();
    state = state.copyWith(busy: false, path: path, entries: entries, selected: const {});
  }

  void toggleSelect(FTPEntry e) {
    final next = Set<String>.of(state.selected);
    next.contains(e.name) ? next.remove(e.name) : next.add(e.name);
    state = state.copyWith(selected: next);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  Future<void> downloadSelected(String outputDir) async {
    final files = state.selectedFiles;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final label = files.length > 1 ? '(${i + 1}/${files.length}) ${f.name}' : f.name;
      await _runTransfer(FtpTransfer(name: label, done: 0, total: f.size ?? 0, upload: false),
          (report) => _client.download(f.name, p.join(outputDir, f.name), report));
    }
    clearSelection();
  }

  Future<void> zipSelected(String outputDir) async {
    final files = state.selectedFiles;
    if (files.isEmpty) return;
    final tmp = await Directory.systemTemp.createTemp('ftp_zip');
    try {
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        await _runTransfer(FtpTransfer(name: '(${i + 1}/${files.length}) ${f.name}', done: 0, total: f.size ?? 0, upload: false),
            (report) => _client.download(f.name, p.join(tmp.path, f.name), report));
      }
      final base = state.path == '/' || state.path.isEmpty ? 'ftp' : p.basename(state.path);
      final outZip = p.join(outputDir, '$base.zip');
      state = state.copyWith(transfer: FtpTransfer(name: 'Zipping $base.zip…', done: 0, total: 0, upload: false));
      await ZipFileEncoder().zipDirectory(tmp, filename: outZip);
      state = state.copyWith(clearTransfer: true);
    } catch (e) {
      state = state.copyWith(clearTransfer: true, error: '$e');
    } finally {
      await tmp.delete(recursive: true);
    }
    clearSelection();
  }

  Future<void> deleteSelected() async {
    for (final e in state.selectedEntries) {
      try {
        await _client.delete(e);
      } catch (err) {
        state = state.copyWith(error: '$err');
      }
    }
    await refresh();
  }

  Future<void> uploadPick() async {
    final picked = await FilePicker.platform.pickFiles();
    final local = picked?.files.single.path;
    if (local == null) return;
    final total = await File(local).length();
    await _runTransfer(FtpTransfer(name: p.basename(local), done: 0, total: total, upload: true), (report) => _client.upload(local, report));
    await refresh();
  }

  Future<void> _runTransfer(FtpTransfer initial, Future<void> Function(FtpProgress) run) async {
    state = state.copyWith(transfer: initial, clearError: true);
    var lastPct = -1;
    try {
      await run((done, total) {
        final pct = total > 0 ? (done * 100 ~/ total) : -1;
        if (pct != lastPct) {
          lastPct = pct;
          state = state.copyWith(transfer: FtpTransfer(name: initial.name, done: done, total: total, upload: initial.upload));
        }
      });
      state = state.copyWith(clearTransfer: true);
    } catch (e) {
      state = state.copyWith(clearTransfer: true, error: '$e');
    }
  }

  // ---- Server --------------------------------------------------------------

  Future<void> pickServerDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose folder to share');
    if (dir == null) return;
    state = state.copyWith(serverDir: dir);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_srvDirKey, dir);
  }

  Future<void> setServerPort(int port) async {
    state = state.copyWith(serverPort: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_srvPortKey, port);
  }

  void setServerReadOnly(bool v) => state = state.copyWith(serverReadOnly: v);

  Future<void> startServer() async {
    if (state.serverDir.isEmpty) {
      state = state.copyWith(serverError: 'Pick a folder to share first');
      return;
    }
    try {
      await _server.start(dir: state.serverDir, port: state.serverPort, readOnly: state.serverReadOnly);
      final addresses = await FtpServerService.localAddresses();
      state = state.copyWith(serverRunning: true, serverAddresses: addresses, clearServerError: true);
    } catch (e) {
      state = state.copyWith(serverRunning: false, serverError: '$e');
    }
  }

  Future<void> stopServer() async {
    await _server.stop();
    state = state.copyWith(serverRunning: false, serverAddresses: const []);
  }

  @override
  void dispose() {
    _client.disconnect();
    _server.stop();
    super.dispose();
  }
}
