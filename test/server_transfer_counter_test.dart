import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/fpkgi_server_service.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';

const _switch = Console(id: 'switch', name: 'Nintendo Switch', urls: [], originalFormat: ['.nsp']);
const _half = 256 * 1024;
const _ps4 = Console(id: 'ps4', name: 'PlayStation 4', urls: [], platform: 'ps4', originalFormat: ['.pkg']);

void main() {
  // FPKGi reads its boxart asset through the binding, but the binding also
  // stubs HttpClient; both servers proxy over real loopback here.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late HttpServer upstream;
  late Completer<void> release;
  late TinfoilServerService tinfoil;
  late FpkgiServerService fpkgi;

  setUp(() async {
    release = Completer<void>();
    // Sends a first half, then holds the rest until the test has looked. The
    // half is big enough to get past the proxy's output buffer.
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.contentLength = 2 * _half;
      req.response.add(List.filled(_half, 1));
      await req.response.flush();
      await release.future;
      req.response.add(List.filled(_half, 2));
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${upstream.port}/file';
    tinfoil = TinfoilServerService();
    await tinfoil.start(
      port: 0,
      loadGames: () async => {_switch: [Game(title: 'Game.nsp', url: url, size: 2 * _half, consoleId: 'switch')]},
      authHeaders: (_) => const {},
    );
    fpkgi = FpkgiServerService();
    await fpkgi.start(
      port: 0,
      loadGames: () async => {_ps4: [Game(title: 'Game - [US] [EN] [1.00].pkg', url: url, size: 2 * _half, consoleId: 'ps4')]},
      authHeaders: (_) => const {},
    );
  });

  tearDown(() async {
    if (!release.isCompleted) release.complete();
    await tinfoil.stop();
    await fpkgi.stop();
    await upstream.close(force: true);
  });

  /// Downloads [url] and runs [check] once the first bytes are in, while the
  /// transfer is still open.
  Future<void> midTransfer(String url, void Function() check) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      final first = Completer<void>();
      final done = res.listen((_) {
        if (!first.isCompleted) first.complete();
      }).asFuture<void>();
      await first.future;
      check();
      release.complete();
      await done;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> settled(TinfoilServerService t, FpkgiServerService f) async {
    for (var i = 0; i < 100 && (t.activeTransfers.value > 0 || f.activeTransfers.value > 0); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a Tinfoil download counts on Tinfoil only', () async {
    await midTransfer('http://127.0.0.1:${tinfoil.port}/dl/switch/0/Game.nsp', () {
      expect(tinfoil.activeTransfers.value, 1);
      expect(fpkgi.activeTransfers.value, 0);
    });
    await settled(tinfoil, fpkgi);
    expect(tinfoil.activeTransfers.value, 0);
  });

  test('an FPKGi download counts on FPKGi only', () async {
    await midTransfer('http://127.0.0.1:${fpkgi.port}/fpkg/ps4/0', () {
      expect(fpkgi.activeTransfers.value, 1);
      expect(tinfoil.activeTransfers.value, 0);
    });
    await settled(tinfoil, fpkgi);
    expect(fpkgi.activeTransfers.value, 0);
  });
}
