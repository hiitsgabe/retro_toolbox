import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

/// A 3DS title from the catalog, shown in the FBI list.
typedef FbiGame = ({Game game, Console console});

/// Serves prepared/picked .cia files from a local cache over HTTP (with Range)
/// and installs them on a 3DS running FBI — pushed to "Receive URLs over the
/// network" (TCP 5000) or shown as a QR for "Scan QR Code". Anything that isn't
/// already a .cia (a .3ds/.cci, or a .zip of one) is converted before serving.
class FbiServerService {
  static const _formats = {'.cia', '.3ds', '.cci'};
  static const fbiPort = 5000; // the port FBI listens on, on the 3DS

  static bool is3dsConsole(Console c) => c.fileFormat?.any((f) => _formats.contains(f.toLowerCase())) ?? false;

  /// FBI's URL-receive wire format: a 4-byte big-endian length, then the
  /// newline-separated URL payload. (FBI replies with one ack byte on close.)
  static Uint8List buildPushPayload(List<String> urls) {
    final body = utf8.encode(urls.join('\n'));
    final header = ByteData(4)..setUint32(0, body.length, Endian.big);
    return (BytesBuilder()
          ..add(header.buffer.asUint8List())
          ..add(body))
        .toBytes();
  }

  /// Sends [urls] to FBI at [ip]:5000. Returns once the payload is delivered;
  /// the 3DS then downloads+installs on its own.
  static Future<void> sendUrlsToFbi(String ip, List<String> urls) async {
    final socket = await Socket.connect(ip, fbiPort, timeout: const Duration(seconds: 10));
    try {
      socket.add(buildPushPayload(urls));
      await socket.flush();
      await socket.first.timeout(const Duration(seconds: 3), onTimeout: () => Uint8List(0));
    } catch (_) {
      // Ack is optional; the payload was already flushed.
    } finally {
      socket.destroy();
    }
  }

  static Future<List<String>> localAddresses() => TinfoilServerService.localAddresses();

  /// The catalog's 3DS titles (for the list); their URLs are produced only after
  /// preparing (converting/copying) into the served cache.
  static List<FbiGame> games(Map<Console, List<Game>> gamesByConsole) {
    final out = <FbiGame>[];
    gamesByConsole.forEach((console, list) {
      for (final g in list) {
        out.add((game: g, console: console));
      }
    });
    return out;
  }

  HttpServer? _server;
  Directory? _cacheDir;
  final activeTransfers = ValueNotifier<int>(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;
  Directory? get cacheDir => _cacheDir;

  Future<void> start({required int port, required Directory cacheDir}) async {
    await stop();
    _cacheDir = cacheDir;
    await cacheDir.create(recursive: true);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (e) => debugPrint('fbi server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// URL FBI downloads a cached .cia from. [fileName] is the file in the cache.
  String ciaUrl(String hostPort, String fileName) => 'http://$hostPort/cia/${Uri.encodeComponent(fileName)}';

  Future<void> _handle(HttpRequest req) async {
    try {
      final segs = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length == 2 && segs[0] == 'cia' && _cacheDir != null) {
        await _serveCia(req, Uri.decodeComponent(segs[1]));
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      debugPrint('fbi handle error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveCia(HttpRequest req, String name) async {
    final base = _cacheDir!.absolute.path;
    final file = File(p.normalize(p.join(base, name)));
    if (!p.isWithin(base, file.path) || !file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final total = file.lengthSync();
    final range = req.headers.value(HttpHeaders.rangeHeader);
    int start = 0, end = total - 1;
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? end;
      if (start > end || start >= total) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    req.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    activeTransfers.value++;
    try {
      await req.response.addStream(file.openRead(start, end + 1));
    } finally {
      activeTransfers.value--;
      await req.response.close();
    }
  }
}
