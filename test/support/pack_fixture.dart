import 'dart:convert';

import 'package:roms_downloader/models/metadata_pack_model.dart';

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
