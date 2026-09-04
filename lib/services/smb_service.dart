import 'dart:async';
import 'dart:io';

import 'package:smb_connect/smb_connect.dart';

typedef SmbProgress = void Function(int done, int total);

/// Parent of an SMB path in the `/share/dir/file` model. `/a/b` → `/a`,
/// `/a` → `''` (the shares root), `''` → `''`.
String smbParent(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

/// Thin SMB client wrapper over [smb_connect]: connect, browse, transfer.
/// Holds a single live connection; the provider drives it and owns UI state.
class SmbService {
  SmbConnect? _c;

  bool get connected => _c != null;

  Future<void> connect({
    required String host,
    required String username,
    required String password,
    String domain = '',
  }) async {
    await disconnect();
    _c = await SmbConnect.connectAuth(host: host, username: username, password: password, domain: domain);
  }

  Future<void> disconnect() async {
    final c = _c;
    _c = null;
    await c?.close();
  }

  /// Scans the local /24 subnet(s) for hosts with the SMB port (445) open,
  /// resolving each to a hostname (reverse DNS / mDNS) where possible. A TCP
  /// connect is the most universal probe — it finds any SMB server regardless
  /// of how (or whether) it advertises itself on the network.
  static Future<List<SmbHost>> scanHosts({Duration timeout = const Duration(milliseconds: 400)}) async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final prefixes = <String>{};
    for (final i in interfaces) {
      for (final a in i.addresses) {
        final parts = a.address.split('.');
        if (parts.length == 4) prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    final candidates = [for (final pre in prefixes) for (var h = 1; h < 255; h++) '$pre.$h'];
    final ips = <String>[];
    // ponytail: bound open sockets to 64 at a time; a /24 is 4 batches.
    const batch = 64;
    for (var i = 0; i < candidates.length; i += batch) {
      final slice = candidates.skip(i).take(batch).toList();
      final results = await Future.wait(slice.map((ip) => _probe(ip, timeout)));
      for (var j = 0; j < slice.length; j++) {
        if (results[j]) ips.add(slice[j]);
      }
    }
    ips.sort(_byOctet);
    final names = await Future.wait(ips.map(_resolveName));
    return [for (var i = 0; i < ips.length; i++) SmbHost(ip: ips[i], name: names[i])];
  }

  static int _byOctet(String a, String b) {
    final an = a.split('.').map(int.parse).toList();
    final bn = b.split('.').map(int.parse).toList();
    for (var k = 0; k < 4; k++) {
      if (an[k] != bn[k]) return an[k].compareTo(bn[k]);
    }
    return 0;
  }

  static Future<bool> _probe(String ip, Duration timeout) async {
    try {
      final s = await Socket.connect(ip, 445, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolves [ip] to a display name the way Finder does: NetBIOS first (which
  /// is what most Samba/Windows SMB hosts answer with — e.g. "RG"), falling
  /// back to reverse DNS (PTR / mDNS `.local`). Null when neither answers.
  static Future<String?> _resolveName(String ip) async {
    final nb = await _netbiosName(ip);
    if (nb != null) return nb;
    try {
      final r = await InternetAddress(ip).reverse().timeout(const Duration(seconds: 1));
      final host = r.host;
      if (host.isEmpty || host == ip) return null;
      return host.replaceAll(RegExp(r'\.$'), '').split('.').first;
    } catch (_) {
      return null;
    }
  }

  /// Queries the NetBIOS Name Service (UDP 137, NBSTAT) for the host's name.
  /// The request name is the wildcard "*", first-level-encoded as the fixed
  /// 32-char label below.
  static Future<String?> _netbiosName(String ip) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final req = <int>[
        0x00, 0x00, // transaction id
        0x00, 0x00, // flags
        0x00, 0x01, // qdcount
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // an/ns/ar count
        0x20, // encoded name length (32)
        ...'CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.codeUnits, // encoded "*"
        0x00, // name terminator
        0x00, 0x21, // qtype = NBSTAT
        0x00, 0x01, // qclass = IN
      ];
      final done = Completer<String?>();
      sock.listen((event) {
        if (event == RawSocketEvent.read && !done.isCompleted) {
          final dg = sock!.receive();
          if (dg != null) done.complete(_parseNbstat(dg.data));
        }
      });
      sock.send(req, InternetAddress(ip), 137);
      return await done.future.timeout(const Duration(milliseconds: 600), onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  /// Parses an NBSTAT reply for a usable machine name. Walks the DNS-style
  /// header/question/answer to reach RDATA, then reads the name table. Prefers
  /// the file-server name (suffix 0x20) over workstation (0x00); skips groups.
  static String? _parseNbstat(List<int> data) {
    try {
      if (data.length < 12) return null;
      final qd = (data[4] << 8) | data[5];
      var off = 12;
      for (var q = 0; q < qd; q++) {
        off = _skipNbName(data, off) + 4; // + qtype + qclass
      }
      off = _skipNbName(data, off); // answer RR name
      off += 2 + 2 + 4 + 2; // type, class, ttl, rdlength
      if (data.length <= off) return null;
      final count = data[off++];
      String? workstation;
      for (var i = 0; i < count; i++) {
        if (off + 18 > data.length) break;
        final name = String.fromCharCodes(data.sublist(off, off + 15)).trim();
        final suffix = data[off + 15];
        final isGroup = (data[off + 16] & 0x80) != 0;
        off += 18;
        if (isGroup || name.isEmpty || name == '__MSBROWSE__') continue;
        if (suffix == 0x20) return name; // file server — the SMB name
        workstation ??= (suffix == 0x00) ? name : null;
      }
      return workstation;
    } catch (_) {
      return null;
    }
  }

  /// Skips a DNS-style name (compression pointer or length-prefixed labels).
  static int _skipNbName(List<int> data, int off) {
    if (off < data.length && (data[off] & 0xC0) == 0xC0) return off + 2;
    while (off < data.length && data[off] != 0) {
      off += data[off] + 1;
    }
    return off + 1;
  }

  /// Lists [path]. An empty path lists the server's shares; otherwise the
  /// folder's entries. Share entries returned here carry the IPC$ tree, so the
  /// caller navigates by rebuilding the path string and re-entering, never by
  /// passing a share entry back to a file op.
  Future<List<SmbFile>> list(String path) async {
    final c = _c!;
    if (path.isEmpty) return c.listShares();
    return c.listFiles(await c.file(path));
  }

  /// Deletes [file]. Recursive for directories (handled by smb_connect).
  Future<void> delete(SmbFile file) async => _c!.delete(file);

  Future<void> download(SmbFile remote, String localPath, SmbProgress onProgress) async {
    final c = _c!;
    final out = File(localPath).openWrite();
    var done = 0;
    var sinceFlush = 0;
    try {
      await for (final chunk in await c.openRead(remote)) {
        out.add(chunk);
        done += chunk.length;
        sinceFlush += chunk.length;
        // ponytail: bound buffered bytes on multi-GB ROMs; flush every ~8MB.
        if (sinceFlush >= 8 << 20) {
          await out.flush();
          sinceFlush = 0;
        }
        onProgress(done, remote.size);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  Future<void> upload(String localPath, String remotePath, SmbProgress onProgress) async {
    final c = _c!;
    final local = File(localPath);
    final total = await local.length();
    final sink = await c.openWrite(await c.createFile(remotePath));
    var done = 0;
    var sinceFlush = 0;
    try {
      await for (final chunk in local.openRead()) {
        sink.add(chunk);
        done += chunk.length;
        sinceFlush += chunk.length;
        if (sinceFlush >= 8 << 20) {
          await sink.flush();
          sinceFlush = 0;
        }
        onProgress(done, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}

/// A host found by [SmbService.scanHosts]. [name] is null when only the IP is
/// known.
class SmbHost {
  final String ip;
  final String? name;
  const SmbHost({required this.ip, this.name});

  String get label => name ?? ip;
}
