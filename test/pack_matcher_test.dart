import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// Pacote de teste com um caso real para cada tier:
/// - Chrono Trigger tem duas regiões, então exercita tier 1 contra tier 2.
/// - Blue Crystalrod tem o artigo no fim, que é o caso que o `canon` conserta.
/// - HammerLock Wrestling é o par fuzzy que a PoC resolveu certo.
/// - Pro Action Replay MK3 é o par fuzzy que a PoC resolveu **errado**.
/// - Zero 4 Champ RR e RR-Z são dois candidatos fuzzy do mesmo bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/chrono-trigger',
          'title': 'Chrono Trigger',
          'dumps': [
            {'name': 'Chrono Trigger (USA)', 'crc': '2D206BF7'},
            {'name': 'Chrono Trigger (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-blue-crystalrod',
          'title': 'The Blue Crystalrod',
          'dumps': [
            {'name': 'Blue Crystalrod, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/hammerlock-wrestling',
          'title': 'HammerLock Wrestling',
          'dumps': [
            {'name': 'HammerLock Wrestling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/pro-action-replay-mk3',
          'title': 'Pro Action Replay MK3',
          'dumps': [
            {'name': 'Pro Action Replay MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-mario-world',
          'title': 'Super Mario World',
          'dumps': [
            {'name': 'Super Mario World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Mario World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr',
          'title': 'Zero 4 Champ RR',
          'dumps': [
            {'name': 'Zero 4 Champ RR (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr-z',
          'title': 'Zero 4 Champ RR-Z',
          'dumps': [
            {'name': 'Zero 4 Champ RR-Z (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));

void main() {
  late PackMatcher matcher;

  setUp(() => matcher = PackMatcher(buildPack()));

  group('tier 1, nome exato', () {
    test('casa o nome do dump letra por letra', () {
      final m = matcher.match('Chrono Trigger (USA)');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.exactName);
      expect(m.game.id, 'snes/chrono-trigger');
      expect(m.sourceName, 'Chrono Trigger (USA)');
    });

    test('casa ignorando a extensão do arquivo', () {
      expect(matcher.match('Chrono Trigger (USA).zip')?.tier, MatchTier.exactName);
      expect(matcher.match('Chrono Trigger (USA).sfc')?.tier, MatchTier.exactName);
    });

    test('casa ignorando caixa, underscore e pontuação', () {
      final m = matcher.match('chrono_trigger_(usa).ZIP');
      expect(m?.tier, MatchTier.exactName);
      expect(m?.game.id, 'snes/chrono-trigger');
    });

    test('o tier exato devolve o dump concreto, com o CRC daquela região', () {
      expect(matcher.match('Chrono Trigger (USA)')?.dump?.crc, '2D206BF7');
      expect(matcher.match('Chrono Trigger (Japan)')?.dump?.crc, 'ABCD1234');
    });

    test('devolve null quando não casa em tier nenhum', () {
      expect(matcher.match('Alguma Coisa Que Nao Existe (USA).zip'), isNull);
    });
  });

  group('tier 2, título canônico', () {
    test('casa quando só a região e a revisão diferem', () {
      final m = matcher.match('Chrono Trigger (Europe) (Rev 1).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/chrono-trigger');
    });

    test('casa quando o artigo está invertido dos dois lados', () {
      // No pacote o dump é "Blue Crystalrod, The (Japan)". A fonte escreve o
      // artigo na frente. `canon` põe os dois na mesma forma.
      final m = matcher.match('The Blue Crystalrod (Japan).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/the-blue-crystalrod');
    });

    test('o tier canônico resolve o jogo e não a versão, então não traz dump', () {
      expect(matcher.match('Chrono Trigger (Europe) (Rev 1).zip')?.dump, isNull);
    });

    test('o tier exato ganha do canônico quando os dois casariam', () {
      // "Super Mario World (Europe)" casa exato no segundo dump e casaria
      // canônico no jogo inteiro. O exato tem que vencer, porque só ele sabe
      // qual das duas regiões é.
      final m = matcher.match('Super Mario World (Europe).sfc');
      expect(m!.tier, MatchTier.exactName);
      expect(m.dump?.crc, 'A31BEAD4');
    });
  });
}
