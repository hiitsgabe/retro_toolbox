import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/crc_confirm_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs do pacote de teste, na forma numérica que o diretório central grava.
const chronoUsa = 0x2D206BF7;
const smwEurope = 0xA31BEAD4;

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://exemplo/arquivo.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  CrcConfirmService serving(Uint8List zip) => CrcConfirmService(
        matcher: matcher,
        fetch: FakeRangeServer(zip).fetch,
      );

  test('não vai à rede quando o nome não termina em .zip', () async {
    var chamadas = 0;
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: (u, r) async {
        chamadas++;
        throw StateError('não deveria ter ido à rede');
      },
    );
    final byName = matcher.match('Chrono Trigger (USA).sfc');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).sfc', byName);
    expect(chamadas, 0);
    expect(out, same(byName));
  });

  test('confirma o palpite de nome quando o CRC aponta o mesmo jogo', () async {
    final service = serving(
        buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out!.game.id, 'snes/chrono-trigger');
    expect(out.tier, MatchTier.checksum);
    expect(out.confidence, MatchConfidence.confirmed);
    expect(out.dump?.name, 'Chrono Trigger (USA)');
  });

  test('corrige o palpite de nome quando o CRC aponta outro jogo', () async {
    // O arquivo se chama Chrono Trigger mas contém Super Mario World. O nome
    // mente, o CRC não.
    final service = serving(
        buildZip([cdEntry('rom.sfc', smwEurope)]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    expect(byName!.game.id, 'snes/chrono-trigger');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out!.game.id, 'snes/super-mario-world');
    expect(out.tier, MatchTier.checksum);
    expect(out.dump?.name, 'Super Mario World (Europe)');
  });

  test('fica com o nome quando o servidor não fala Range', () async {
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('rom.sfc', smwEurope)]),
        status: 200,
      ).fetch,
    );
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out, same(byName));
  });

  test('fica com o nome quando o zip tem dois jogos diferentes dentro',
      () async {
    final service = serving(buildZip([
      cdEntry('Chrono Trigger (USA).sfc', chronoUsa),
      cdEntry('Super Mario World (Europe).sfc', smwEurope),
    ]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out, same(byName));
  });

  test('ignora o que não é ROM e decide pela única que é', () async {
    // Se o filtro de extensão não existisse, o bonus.zip entraria com o CRC do
    // Super Mario World, viraria dois jogos, e o zip seria descartado como
    // inconclusivo. Ver 5.8, limite 1.
    final service = serving(buildZip([
      cdEntry('leiame.txt', 0x00000009),
      cdEntry('bonus.zip', smwEurope),
      cdEntry('Chrono Trigger (USA).sfc', chronoUsa),
    ]));
    final byName = matcher.match('qualquer coisa.zip');
    expect(byName, isNull);
    final out = await service.confirm(uri, 'qualquer coisa.zip', byName);
    expect(out!.game.id, 'snes/chrono-trigger');
    expect(out.tier, MatchTier.checksum);
    expect(out.sourceName, 'qualquer coisa.zip');
  });
}
