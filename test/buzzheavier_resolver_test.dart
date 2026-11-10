import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/network.dart';

/// Replays the verified buzzheavier flow over a local HttpServer so the
/// resolver logic is tested without touching the real (Cloudflare-guarded)
/// site.
Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.headers.value('Cookie') == 'cf-mitigated-test=challenge') {
      request.response.statusCode = 403;
      request.response.headers.set('cf-mitigated', 'challenge');
      await request.response.close();
    } else if (path == '/i10ganqzgbce') {
      final html = '<a class="download-btn gay-button" hx-get="/i10ganqzgbce/download?t=TOKEN123">Download</a>';
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.html;
      request.response.write(html);
      await request.response.close();
    } else if (path == '/i10ganqzgbce/download') {
      if (request.uri.queryParameters['t'] != 'TOKEN123') {
        request.response.statusCode = 400;
        request.response.write('bad token');
        await request.response.close();
        return;
      }
      // Browsers see htmx's 204 + Hx-Redirect; the value is the direct link.
      request.response.statusCode = 204;
      request.response.headers.set('hx-redirect', 'http://localhost:${server.port}/d/i10ganqzgbce?v=SIGNED');
      await request.response.close();
    } else if (path == '/d/i10ganqzgbce') {
      request.response.statusCode = 200;
      request.response.headers.set('content-disposition', 'attachment; filename="https.pdf"');
      request.response.write('bytes');
      await request.response.close();
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  });
  return server;
}

void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await _startServer();
    base = 'http://localhost:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('resolves page -> hx-get token -> Hx-Redirect direct link', () async {
    final direct = await resolveBuzzheavierDirectUrl('$base/i10ganqzgbce');
    expect(direct, 'http://localhost:${server.port}/d/i10ganqzgbce?v=SIGNED');

    // The direct link must serve the actual file to plain clients.
    final probe = await HttpClient().openUrl('GET', Uri.parse(direct));
    final response = await probe.close();
    expect(response.statusCode, 200);
    expect(response.headers.value('content-disposition'), contains('attachment'));
  });

  test('surfaces a Cloudflare challenge as a descriptive error', () async {
    await expectLater(
      () => resolveBuzzheavierDirectUrl('$base/i10ganqzgbce', cookieHeader: 'cf-mitigated-test=challenge'),
      throwsA(predicate((e) => e.toString().contains('Cloudflare challenge'))),
    );
  });
}
