import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/smb_service.dart';
import 'package:roms_downloader/utils/remote_tree.dart';

const _hostKey = 'smb_host';
const _userKey = 'smb_user';
const _domainKey = 'smb_domain';

/// A download or upload in flight. [total] is 0 while unknown.
class SmbTransfer {
  final String name;
  final int done;
  final int total;
  final bool upload;
  const SmbTransfer({required this.name, required this.done, required this.total, required this.upload});

  double get fraction => total > 0 ? done / total : 0;
}

class SmbState {
  final bool connected;
  final bool busy; // connecting or listing — blocks navigation
  final bool scanning;
  final List<SmbHost> discovered;
  final String host;
  final String username;
  final String domain;
  final String path; // '' = shares root
  final List<SmbFile> entries;
  final Set<String> selected; // selected entry paths in the current dir
  final SmbTransfer? transfer;
  final String? error;

  const SmbState({
    this.connected = false,
    this.busy = false,
    this.scanning = false,
    this.discovered = const [],
    this.host = '',
    this.username = '',
    this.domain = '',
    this.path = '',
    this.entries = const [],
    this.selected = const {},
    this.transfer,
    this.error,
  });

  bool get atRoot => path.isEmpty;

  List<SmbFile> get selectedEntries => entries.where((e) => selected.contains(e.path)).toList();

  SmbState copyWith({
    bool? connected,
    bool? busy,
    bool? scanning,
    List<SmbHost>? discovered,
    String? host,
    String? username,
    String? domain,
    String? path,
    List<SmbFile>? entries,
    Set<String>? selected,
    SmbTransfer? transfer,
    bool clearTransfer = false,
    String? error,
    bool clearError = false,
  }) =>
      SmbState(
        connected: connected ?? this.connected,
        busy: busy ?? this.busy,
        scanning: scanning ?? this.scanning,
        discovered: discovered ?? this.discovered,
        host: host ?? this.host,
        username: username ?? this.username,
        domain: domain ?? this.domain,
        path: path ?? this.path,
        entries: entries ?? this.entries,
        selected: selected ?? this.selected,
        transfer: clearTransfer ? null : (transfer ?? this.transfer),
        error: clearError ? null : (error ?? this.error),
      );
}

final smbProvider = StateNotifierProvider<SmbNotifier, SmbState>((ref) => SmbNotifier());

class SmbNotifier extends StateNotifier<SmbState> {
  final _service = SmbService();

  SmbNotifier() : super(const SmbState()) {
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      state = state.copyWith(
        host: prefs.getString(_hostKey) ?? '',
        username: prefs.getString(_userKey) ?? '',
        domain: prefs.getString(_domainKey) ?? '',
      );
    });
  }

  /// Connects and lists the shares. Host/user/domain are remembered; the
  /// password never is (see the SMB screen — asked every connect).
  Future<void> connect({required String host, required String username, required String password, String domain = ''}) async {
    state = state.copyWith(busy: true, clearError: true, host: host, username: username, domain: domain);
    try {
      await _service.connect(host: host, username: username, password: password, domain: domain);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, host);
      await prefs.setString(_userKey, username);
      await prefs.setString(_domainKey, domain);
      state = state.copyWith(connected: true, path: '');
      await _load('');
    } catch (e) {
      state = state.copyWith(busy: false, connected: false, error: '$e');
    }
  }

  /// Probes the local subnet for hosts with SMB (445) open.
  Future<void> scan() async {
    state = state.copyWith(scanning: true, discovered: const [], clearError: true);
    try {
      final hosts = await SmbService.scanHosts();
      state = state.copyWith(scanning: false, discovered: hosts);
    } catch (e) {
      state = state.copyWith(scanning: false, error: '$e');
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    state = state.copyWith(connected: false, path: '', entries: const [], clearTransfer: true, clearError: true);
  }

  /// Opens a share (at root) or a directory entry.
  Future<void> open(SmbFile entry) async {
    final next = state.atRoot ? '/${entry.name}' : entry.path;
    await _load(next);
  }

  Future<void> goUp() async => _load(smbParent(state.path));

  Future<void> refresh() async => _load(state.path);

  Future<void> _load(String path) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final entries = await _service.list(path);
      // Directories first, then files; each group alphabetical.
      entries.sort((a, b) {
        final ad = path.isEmpty || a.isDirectory();
        final bd = path.isEmpty || b.isDirectory();
        if (ad != bd) return ad ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      // Navigating changes the selection context — reset it.
      state = state.copyWith(busy: false, path: path, entries: entries, selected: const {});
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  void toggleSelect(SmbFile entry) {
    final next = Set<String>.of(state.selected);
    next.contains(entry.path) ? next.remove(entry.path) : next.add(entry.path);
    state = state.copyWith(selected: next);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  /// Quick single-file download into the app's default download folder.
  Future<void> download(SmbFile file) async {
    final dir = await DirectoryService().getDownloadDir();
    final localPath = p.join(dir, file.name);
    await _runTransfer(SmbTransfer(name: file.name, done: 0, total: file.size, upload: false), (report) => _service.download(file, localPath, report));
  }

  /// Downloads the selection into [outputDir], one file after another.
  /// Selected folders are downloaded whole, rebuilding their tree locally.
  Future<void> downloadSelected(String outputDir) async {
    await _downloadTree(outputDir);
    clearSelection();
  }

  /// Downloads the selection (folders included, whole) to a temp dir, zips it
  /// into [outputDir], then cleans up. The zip is streamed to disk, so multi-GB
  /// ROMs are fine. A single selected folder names the zip.
  Future<void> zipSelected(String outputDir) async {
    final sel = state.selectedEntries;
    if (sel.isEmpty) return;
    final base = sel.length == 1 && sel.single.isDirectory()
        ? sel.single.name
        : (state.path.isEmpty ? 'smb' : p.basename(state.path));
    final tmp = await Directory.systemTemp.createTemp('smb_zip');
    try {
      if (!await _downloadTree(tmp.path)) return;
      final outZip = p.join(outputDir, '$base.zip');
      state = state.copyWith(transfer: SmbTransfer(name: 'Zipping $base.zip…', done: 0, total: 0, upload: false));
      await ZipFileEncoder().zipDirectory(tmp, filename: outZip);
      state = state.copyWith(clearTransfer: true);
    } catch (e) {
      state = state.copyWith(clearTransfer: true, error: '$e');
    } finally {
      await tmp.delete(recursive: true);
      clearSelection();
    }
  }

  /// Expands the selection into every file inside it and downloads each to
  /// [root] at its relative path. False when the folders couldn't be listed.
  Future<bool> _downloadTree(String root) async {
    state = state.copyWith(transfer: const SmbTransfer(name: 'Listing folders…', done: 0, total: 0, upload: false), clearError: true);
    final List<RemoteFile<SmbFile>> files;
    try {
      files = await collectRemoteFiles<SmbFile>(
        state.selectedEntries,
        nameOf: (e) => e.name,
        isDir: (e) => e.isDirectory(),
        children: (dir, _) => _service.list(dir.path),
      );
    } catch (e) {
      state = state.copyWith(clearTransfer: true, error: '$e');
      return false;
    }
    state = state.copyWith(clearTransfer: true);
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final local = await localPathFor(root, f.relPath);
      final label = files.length > 1 ? '(${i + 1}/${files.length}) ${f.relPath}' : f.relPath;
      await _runTransfer(SmbTransfer(name: label, done: 0, total: f.entry.size, upload: false),
          (report) => _service.download(f.entry, local, report));
    }
    return true;
  }

  /// Deletes the selected entries (files and folders — [SmbService] delete is
  /// recursive) then refreshes.
  Future<void> deleteSelected() async {
    for (final e in state.selectedEntries) {
      try {
        await _service.delete(e);
      } catch (err) {
        state = state.copyWith(error: '$err');
      }
    }
    await refresh();
  }

  /// Picks a local file and uploads it into the current directory.
  Future<void> uploadPick() async {
    if (state.atRoot) return; // can't write to the shares list
    final picked = await FilePicker.platform.pickFiles();
    final local = picked?.files.single.path;
    if (local == null) return;
    final name = p.basename(local);
    final remotePath = '${state.path}/$name';
    await _runTransfer(SmbTransfer(name: name, done: 0, total: 0, upload: true), (report) => _service.upload(local, remotePath, report));
    await refresh();
  }

  Future<void> _runTransfer(SmbTransfer initial, Future<void> Function(SmbProgress) run) async {
    state = state.copyWith(transfer: initial, clearError: true);
    var lastPct = -1;
    try {
      await run((done, total) {
        // Throttle rebuilds to whole-percent steps (files can be multi-GB).
        final pct = total > 0 ? (done * 100 ~/ total) : -1;
        if (pct != lastPct) {
          lastPct = pct;
          state = state.copyWith(transfer: SmbTransfer(name: initial.name, done: done, total: total, upload: initial.upload));
        }
      });
      state = state.copyWith(clearTransfer: true);
    } catch (e) {
      state = state.copyWith(clearTransfer: true, error: '$e');
    }
  }

  @override
  void dispose() {
    _service.disconnect();
    super.dispose();
  }
}
