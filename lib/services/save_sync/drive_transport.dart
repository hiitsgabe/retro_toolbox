import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One HTTP request to Google Drive.
class DriveRequest {
  DriveRequest(this.method, this.url, {this.headers = const {}, this.body = const []});

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;
}

class DriveResponse {
  DriveResponse(this.status, this.body, {this.headers = const {}});

  DriveResponse.json(this.status, Object? json, {this.headers = const {}}) : body = utf8.encode(jsonEncode(json));

  final int status;
  final List<int> body;

  /// Names in lower case.
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 300;

  /// The body as JSON; null when it is empty or not JSON (a gateway's error page).
  Object? get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(body, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }
}

/// Every Drive request goes through one of these, so tests answer with an
/// in-memory Drive instead of the network.
abstract class DriveTransport {
  /// Throws [DriveNetworkError] when the connection fails, stalls or breaks.
  Future<DriveResponse> send(DriveRequest request);
}

/// The connection failed, stalled or broke before the whole response arrived. Drive may or may
/// not have acted on the request.
class DriveNetworkError implements Exception {
  DriveNetworkError(this.cause);

  /// The SocketException, HttpException or TimeoutException underneath, for logs.
  final Object cause;

  @override
  String toString() => 'Lost the connection to Google Drive. Check the connection and try again.';
}

/// The real transport, over dart:io.
class HttpDriveTransport implements DriveTransport {
  HttpDriveTransport({HttpClient? client, this.idle = const Duration(seconds: 60)}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = idle;
  }

  final HttpClient _client;

  /// How long a request may make no progress: connecting, the socket taking the next piece of the
  /// body, the response starting, the next piece of the response. A slow transfer that keeps moving
  /// has no deadline, so a big save goes up and down on a slow link too.
  final Duration idle;

  static const _piece = 64 * 1024;

  /// Bytes per second. The last pieces of a body can still sit in the OS's send buffer (a few MB)
  /// when the socket has taken them all, so the response gets [idle] plus the time the whole body
  /// takes at this rate (128 kbps) to start.
  static const _slowestLink = 16 * 1024;

  @override
  Future<DriveResponse> send(DriveRequest r) async {
    HttpClientRequest? req;
    try {
      req = await _client.openUrl(r.method, r.url).timeout(idle);
      r.headers.forEach(req.headers.set);
      req.contentLength = r.body.length;
      // Piece by piece, each one waiting for the socket to take it, so a stalled upload shows.
      for (var i = 0; i < r.body.length; i += _piece) {
        req.add(r.body.sublist(i, min(i + _piece, r.body.length)));
        await req.flush().timeout(idle);
      }
      final res = await req.close().timeout(idle + Duration(milliseconds: r.body.length * 1000 ~/ _slowestLink));
      final body = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(idle)) {
        body.add(chunk);
      }
      final headers = <String, String>{};
      res.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(', '));
      return DriveResponse(res.statusCode, body.takeBytes(), headers: headers);
    } on TimeoutException catch (e) {
      // Future.timeout only stops waiting: abort, or the upload goes on and Drive may still make the file.
      req?.abort(e);
      throw DriveNetworkError(e);
    } on IOException catch (e) {
      req?.abort(e);
      throw DriveNetworkError(e);
    }
  }
}
