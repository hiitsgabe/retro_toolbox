import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'link_download.dart';

/// Retro Tools Server uses 9093.
const linkInboxDefaultPort = 9094;

const _maxBody = 8192;

const _page = '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Retro Toolbox</title>
<style>
body{margin:0;padding:24px 16px;background:#17102B;color:#fff;font-family:system-ui,sans-serif}
h1{font-size:22px;margin:0 0 16px}
input,button{box-sizing:border-box;width:100%;padding:14px;font-size:16px;border-radius:8px;border:0;margin-bottom:12px}
button{background:#7C4DFF;color:#fff;font-weight:600}
#s{min-height:1.4em;color:#cbb8ff}
</style></head><body>
<h1>Retro Toolbox</h1>
<input id="u" type="url" placeholder="https://..." autocomplete="off" autocapitalize="off">
<button id="b">Send to handheld</button>
<div id="s"></div>
<script>
var s=document.getElementById('s');
document.getElementById('b').onclick=function(){
fetch('/link',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
body:'url='+encodeURIComponent(document.getElementById('u').value.trim())})
.then(function(r){s.textContent=r.ok?'Sent, confirm on the handheld':'Not a valid link'})
.catch(function(){s.textContent='Could not reach the handheld'})};
</script></body></html>''';

/// A tiny LAN web page where a phone can send a download link to the handheld.
/// Links only go onto [links]; the app decides what to do with them.
class LinkInboxServer {
  final _links = StreamController<String>.broadcast();
  HttpServer? _server;

  Stream<String> get links => _links.stream;
  bool get running => _server != null;
  int? get port => _server?.port;

  Future<void> start(int port) async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (e) => debugPrint('link inbox error: $e'));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_page);
        await req.response.close();
      } else if (req.method == 'POST' && path == '/link') {
        await (_fromOwnPage(req) ? _receive(req) : _reply(req, HttpStatus.forbidden));
      } else {
        await _reply(req, HttpStatus.notFound);
      }
    } catch (e) {
      debugPrint('link inbox handle error: $e');
      try {
        await _reply(req, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  /// Browsers send Origin on every POST, so another site's page can't push a
  /// link; an IP-only Host shuts out DNS rebinding (a name pointing here).
  static bool _fromOwnPage(HttpRequest req) {
    final host = req.headers.value(HttpHeaders.hostHeader), origin = req.headers.value('origin');
    if (host == null || InternetAddress.tryParse(Uri.tryParse('http://$host')?.host ?? '') == null) return false;
    return origin == null || origin == 'http://$host';
  }

  Future<void> _receive(HttpRequest req) async {
    if (req.contentLength > _maxBody) return _reply(req, HttpStatus.requestEntityTooLarge);
    // Count while reading so a chunked or lying client can't make us buffer more than the limit.
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) return _reply(req, HttpStatus.requestEntityTooLarge);
    }
    String? url;
    try {
      final body = utf8.decode(bytes).trim();
      url = body.startsWith('url=') ? Uri.splitQueryString(body)['url'] : body;
    } on FormatException {
      url = null;
    } on ArgumentError {
      url = null; // bad percent-encoding
    }
    if (url == null || !isValidDownloadUrl(url)) return _reply(req, HttpStatus.badRequest);
    _links.add(url.trim());
    await _reply(req, HttpStatus.ok);
  }

  Future<void> _reply(HttpRequest req, int status) async {
    req.response
      ..statusCode = status
      ..headers.set(HttpHeaders.connectionHeader, 'close');
    await req.response.close();
  }
}
