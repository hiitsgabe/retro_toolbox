import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';

import 'package:roms_downloader/services/tinfoil_server_service.dart';

typedef FtpProgress = void Function(int done, int total);

/// FTP client wrapper over [ftpconnect]. Directory navigation is cwd-based:
/// [cd] changes the working directory, [list] returns its contents.
class FtpClientService {
  FTPConnect? _c;
  // Kept in memory only (never persisted) so a background transfer can open
  // its own connection.
  ({String host, int port, String user, String pass})? _login;

  bool get connected => _c != null;

  Future<void> connect({required String host, required int port, required String user, required String pass}) async {
    await disconnect();
    final c = FTPConnect(host, port: port, user: user.isEmpty ? 'anonymous' : user, pass: pass);
    if (!await c.connect()) throw 'Login failed';
    await c.setTransferType(TransferType.binary); // ROMs are binary, never ASCII
    _c = c;
    _login = (host: host, port: port, user: user, pass: pass);
  }

  /// A separate connection to the same server, already in [path]. Background
  /// transfers use one: FTP paths are relative to the working directory, which
  /// moves as the user browses on the main connection.
  Future<FtpClientService> openAt(String path) async {
    final login = _login;
    if (login == null) throw 'Not connected';
    final other = FtpClientService();
    await other.connect(host: login.host, port: login.port, user: login.user, pass: login.pass);
    if (!await other.cd(path)) {
      await other.disconnect();
      throw 'Cannot open folder $path';
    }
    return other;
  }

  Future<void> disconnect() async {
    final c = _c;
    _c = null;
    _login = null;
    try {
      await c?.disconnect();
    } catch (_) {}
  }

  Future<String> pwd() => _c!.currentDirectory();
  Future<List<FTPEntry>> list() => _c!.listDirectoryContent();
  Future<bool> cd(String dir) => _c!.changeDirectory(dir);

  /// Lists [relDir] (relative to the current directory) and returns to where
  /// it started, since FTP listing only covers the working directory.
  Future<List<FTPEntry>> listAt(String relDir) async {
    final home = await pwd();
    if (!await cd(relDir)) throw 'Cannot open folder $relDir';
    try {
      return await list();
    } finally {
      await cd(home);
    }
  }

  Future<void> download(String name, String localPath, FtpProgress onProgress) async {
    await _c!.downloadFile(name, File(localPath), onProgress: (_, received, total) => onProgress(received, total));
  }

  Future<void> upload(String localPath, FtpProgress onProgress) async {
    await _c!.uploadFile(File(localPath), onProgress: (_, sent, total) => onProgress(sent, total));
  }

  Future<void> delete(FTPEntry e) async {
    if (e.type == FTPEntryType.dir) {
      await _c!.deleteDirectory(e.name);
    } else {
      await _c!.deleteFile(e.name);
    }
  }
}

/// FTP server wrapper over [ftp_server], sharing one folder on the LAN.
class FtpServerService {
  FtpServer? _server;

  bool get running => _server != null;

  Future<void> start({required String dir, required int port, String? user, String? pass, bool readOnly = false}) async {
    await stop();
    final s = FtpServer(
      port,
      username: (user?.isEmpty ?? true) ? null : user,
      password: (pass?.isEmpty ?? true) ? null : pass,
      fileOperations: PhysicalFileOperations(dir),
      serverType: readOnly ? ServerType.readOnly : ServerType.readAndWrite,
    );
    await s.startInBackground();
    _server = s;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.stop();
  }

  /// Local IPv4 addresses to hand out, home-LAN ones first (reuses the ranking
  /// already used by the Tinfoil server).
  static Future<List<String>> localAddresses() => TinfoilServerService.localAddresses();
}
