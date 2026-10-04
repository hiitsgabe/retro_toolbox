import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retro_toolbox/services/ftp_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/utils/remote_tree.dart';

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

  /// A background job downloading the current selection into [outputDir]
  /// (folders whole, their tree rebuilt). It runs on its own connection in
  /// the current folder, captured now along with the selection, so browsing
  /// on doesn't move its paths.
  TransferJob downloadJob(String outputDir) {
    final base = state.path;
    final sel = state.selectedEntries;
    clearSelection();
    return (onProgress) => _downloadTree(base, sel, outputDir, onProgress);
  }

  /// Like [downloadJob], then zipped into one file in [outputDir]. A single
  /// selected folder names the zip.
  TransferJob zipJob(String outputDir) {
    final base = state.path;
    final sel = state.selectedEntries;
    final name = sel.length == 1 && sel.single.type == FTPEntryType.dir
        ? sel.single.name
        : (base == '/' || base.isEmpty ? 'ftp' : p.basename(base));
    final outZip = p.join(outputDir, FileOps.uniqueName(outputDir, '$name.zip'));
    clearSelection();
    return (onProgress) => downloadThenZip((dir, pr) => _downloadTree(base, sel, dir, pr), outZip, onProgress);
  }

  /// A label for the task manager: the item's name, or how many items.
  String selectionLabel() {
    final sel = state.selectedEntries;
    return sel.length == 1 ? sel.single.name : '${sel.length} items';
  }

  Future<void> _downloadTree(String base, List<FTPEntry> sel, String root, FileOpsProgress onProgress) async {
    final c = await _client.openAt(base);
    try {
      final files = await collectRemoteFiles<FTPEntry>(
        sel,
        nameOf: (e) => e.name,
        isDir: (e) => e.type == FTPEntryType.dir,
        children: (_, rel) => c.listAt(rel),
      );
      final total = files.fold<int>(0, (a, f) => a + (f.entry.size ?? 0));
      var done = 0;
      for (final f in files) {
        final local = await localPathFor(root, f.relPath);
        var last = 0;
        // RETR takes a path relative to the working directory.
        await c.download(f.relPath, local, (received, _) {
          done += received - last;
          last = received;
          onProgress(done, total);
        });
        done += (f.entry.size ?? 0) - last;
      }
      onProgress(total, total);
    } finally {
      await c.disconnect();
    }
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
