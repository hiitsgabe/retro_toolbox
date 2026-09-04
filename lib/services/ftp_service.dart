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

  bool get connected => _c != null;

  Future<void> connect({required String host, required int port, required String user, required String pass}) async {
    await disconnect();
    final c = FTPConnect(host, port: port, user: user.isEmpty ? 'anonymous' : user, pass: pass);
    if (!await c.connect()) throw 'Login failed';
    await c.setTransferType(TransferType.binary); // ROMs are binary, never ASCII
    _c = c;
  }

  Future<void> disconnect() async {
    final c = _c;
    _c = null;
    try {
      await c?.disconnect();
    } catch (_) {}
  }

  Future<String> pwd() => _c!.currentDirectory();
  Future<List<FTPEntry>> list() => _c!.listDirectoryContent();
  Future<bool> cd(String dir) => _c!.changeDirectory(dir);

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
