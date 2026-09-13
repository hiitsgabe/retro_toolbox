import 'dart:convert';

import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Test pack with one real case per tier:
/// - Crystal Vanguard has two regions, exercising tier 1 against tier 2.
/// - Zxia Gztqfevzem has the trailing article, the case `canon` fixes.
/// - CopperBolt Grappling is the fuzzy pair the PoC resolved right.
/// - Duo Vector Recoil MK3 is the fuzzy pair the PoC resolved wrong.
/// - Reso 4 Kkesv HQ and HQ-H are two fuzzy candidates in the same bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/crystal-vanguard',
          'title': 'Crystal Vanguard',
          'dumps': [
            {'name': 'Crystal Vanguard (USA)', 'crc': '2D206BF7'},
            {'name': 'Crystal Vanguard (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-zxia-gztqfevzem',
          'title': 'The Zxia Gztqfevzem',
          'dumps': [
            {'name': 'Zxia Gztqfevzem, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/copperbolt-grappling',
          'title': 'CopperBolt Grappling',
          'dumps': [
            {'name': 'CopperBolt Grappling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/duo-vector-recoil-mk3',
          'title': 'Duo Vector Recoil MK3',
          'dumps': [
            {'name': 'Duo Vector Recoil MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-pixel-world',
          'title': 'Super Pixel World',
          'dumps': [
            {'name': 'Super Pixel World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Pixel World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq',
          'title': 'Reso 4 Kkesv HQ',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq-h',
          'title': 'Reso 4 Kkesv HQ-H',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ-H (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));
