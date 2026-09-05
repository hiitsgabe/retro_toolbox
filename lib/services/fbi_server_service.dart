import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

/// A 3DS game exposed over the FBI server, with the URL FBI downloads from.
typedef FbiGame = ({Game game, Console console, String url});

/// Serves 3DS .cia titles over HTTP (reusing the Tinfoil proxy) and pushes
/// their URLs to FBI on the 3DS ("Receive URLs over the network", TCP 5000),
/// or shows them as QR codes for FBI's "Scan QR Code" install.
class FbiServerService {
  static const _formats = {'.cia'};
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
      // Best-effort: FBI acks after installing, which can take a while. Don't
      // block the UI on it — delivery of the payload is what matters here.
      await socket.first.timeout(const Duration(seconds: 3), onTimeout: () => Uint8List(0));
    } catch (_) {
      // Ack read is optional; the payload was already flushed.
    } finally {
      socket.destroy();
    }
  }

  final _http = TinfoilServerService();

  bool get running => _http.running;
  int get port => _http.port;
  ValueListenable<int> get activeTransfers => _http.activeTransfers;

  Future<void> start({
    required int port,
    required Future<Map<Console, List<Game>>> Function() loadGames,
    required Map<String, String> Function(Console) authHeaders,
  }) =>
      _http.start(port: port, loadGames: loadGames, authHeaders: authHeaders);

  Future<void> stop() => _http.stop();

  static Future<List<String>> localAddresses() => TinfoilServerService.localAddresses();

  /// The list of 3DS games and their download URLs on this server.
  static List<FbiGame> games(Map<Console, List<Game>> gamesByConsole, String hostPort) {
    final (index, routes) = TinfoilServerService.buildIndex(gamesByConsole, hostPort);
    final files = index['files'] as List;
    final out = <FbiGame>[];
    var i = 0;
    routes.forEach((_, entry) {
      final url = (files[i] as Map)['url'] as String;
      out.add((game: entry.game, console: entry.console, url: url));
      i++;
    });
    return out;
  }
}
