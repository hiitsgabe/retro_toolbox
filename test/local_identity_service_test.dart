import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';

void main() {
  late Directory tmp;
  late PackMatcher matcher;
  late List<String> lidos;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_identity_test');
    matcher = PackMatcher(buildPack());
    lidos = [];
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File write(String name) =>
      File('${tmp.path}/$name')..writeAsStringSync('conteudo');

  /// Serviço com um CRC falso, para o teste controlar o que o disco "tem" e
  /// contar quantas vezes o arquivo foi lido.
  LocalIdentityService serviceReturning(String crc) => LocalIdentityService(
        matcher: matcher,
        crcOfFile: (file) async {
          lidos.add(file.path);
          return crc;
        },
      );

  test('aceita o nome exato e nem toca no arquivo', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('Chrono Trigger (USA).sfc'));
    expect(m!.tier, MatchTier.exactName);
    expect(m.game.id, 'snes/chrono-trigger');
    expect(lidos, isEmpty);
  });

  test('aceita o nome canônico e nem toca no arquivo', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('The Blue Crystalrod.sfc'));
    expect(m!.tier, MatchTier.canonicalName);
    expect(m.game.id, 'snes/the-blue-crystalrod');
    expect(lidos, isEmpty);
  });

  test('no palpite fuzzy calcula o CRC e corrige o jogo', () async {
    // O nome parece HammerLock Wrestling, mas os bytes são do Pro Action
    // Replay MK3. O CRC ganha.
    final service = serviceReturning('11112222');
    final file = write('Hammer Lock Wrestling (USA).sfc');
    expect(matcher.match('Hammer Lock Wrestling (USA).sfc')!.tier,
        MatchTier.fuzzyName);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/pro-action-replay-mk3');
    expect(lidos, [file.path]);
  });

  test('sem palpite de nome nenhum, o CRC resolve sozinho', () async {
    final service = serviceReturning('A31BEAD4');
    final file = write('rom desconhecida 0042.sfc');
    expect(matcher.match('rom desconhecida 0042.sfc'), isNull);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/super-mario-world');
  });

  test('CRC que não está no pacote devolve o palpite de nome intocado',
      () async {
    final service = serviceReturning('DEADBEEF');
    final m = await service.identify(write('Hammer Lock Wrestling (USA).sfc'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/hammerlock-wrestling');
  });

  test('não calcula CRC de contêiner, porque não seria comparável', () async {
    final service = serviceReturning('11112222');
    final m = await service.identify(write('Hammer Lock Wrestling (USA).zip'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/hammerlock-wrestling');
    expect(lidos, isEmpty);
  });

  test('o cache evita a segunda leitura do mesmo arquivo', () async {
    final service = serviceReturning('11112222');
    final file = write('Hammer Lock Wrestling (USA).sfc');
    await service.identify(file);
    await service.identify(file);
    expect(lidos, hasLength(1));
    expect(service.cache.values, ['11112222']);
  });
}
