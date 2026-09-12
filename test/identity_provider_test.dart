import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

const indexJson =
    '{"built":"2026-09-10","packs":[{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","games":1,"aliases":["super_nintendo"]}]}';
const packJson =
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/chrono-trigger","title":"Chrono Trigger","dumps":[{"name":"Chrono Trigger (USA)","crc":"2D206BF7"}]}]}';

const snes = PackTarget('super_nintendo', 'Super Nintendo');
const switchTarget = PackTarget('nintendo_switch', 'Nintendo Switch');

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_provider_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer container() {
    final service = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        if (uri.path.endsWith('index.json')) return utf8.encode(indexJson);
        return gzip.encode(utf8.encode(packJson));
      },
    );
    final c = ProviderContainer(overrides: [
      metadataPackServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('constrói o matcher a partir do pacote do console', () async {
    final matcher = await container().read(packMatcherProvider(snes).future);
    expect(matcher, isNotNull);
    expect(matcher!.match('Chrono Trigger (USA).zip')?.tier,
        MatchTier.exactName);
  });

  test('console sem pacote devolve null em vez de erro', () async {
    final c = container();
    expect(await c.read(packMatcherProvider(switchTarget).future), isNull);
    expect(
        await c.read(localIdentityServiceProvider(switchTarget).future), isNull);
  });

  test('o serviço local reusa o mesmo matcher memoizado', () async {
    final c = container();
    final matcher = await c.read(packMatcherProvider(snes).future);
    final service = await c.read(localIdentityServiceProvider(snes).future);
    expect(service!.matcher, same(matcher));
  });
}
