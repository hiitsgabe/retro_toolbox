import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

Map<String, String> _bundle() {
  final files = Directory('save_recipes').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
  return {for (final f in files) f.uri.pathSegments.last: f.readAsStringSync()};
}

void main() {
  final load = parseRecipeFiles(_bundle());
  final byId = {for (final r in load.recipes) r.id: r};

  test('every bundled recipe parses', () {
    expect(load.rejected, isEmpty, reason: load.rejected.toString());
    expect(load.tooNew, isEmpty);
  });

  // Each case lists what a real device has under the recipe's root, and the
  // units that must travel. Anything left out is the game's own backup, a
  // setting, or engine data that stays on the device.
  final cases = <String, (String, List<String>, Map<String, List<String>>)>{
    'silksong': (
      'silksong',
      ['Restore_Points1/NODELrestoreData1.dat', 'shared.dat', 'user1.dat', 'user1_1.0.28714.dat'],
      {
        'all': ['shared.dat', 'user1.dat'],
      },
    ),
    // The same game on a handheld whose screen mod lives in files/BepInEx:
    // the root is files/default, so nothing the mod wrote is even scanned,
    // and the game's own .bak stays put.
    'silksong on a modded handheld': (
      'silksong',
      ['Restore_Points1/NODELrestoreData1.dat', 'Restore_Points1/NODELrestoreData2.dat', 'shared.dat', 'shared.dat.bak'],
      {
        'all': ['shared.dat'],
      },
    ),
    'hollow-knight': (
      'hollow-knight',
      ['GraphicsSettings.txt', 'il2cpp/Metadata/global-metadata.dat', 'user1.dat', 'user1.dat.bak676', 'user1_1.5.78.11833.dat'],
      {
        'all': ['user1.dat'],
      },
    ),
    'cuphead': (
      'cuphead',
      ['cuphead_player_data_v1_slot_0.sav', 'cuphead_player_data_v1_slot_1.sav', 'cuphead_player_data_v1_slot_2.sav'],
      {
        'cuphead_player_data_v1_slot_0.sav': ['cuphead_player_data_v1_slot_0.sav'],
        'cuphead_player_data_v1_slot_1.sav': ['cuphead_player_data_v1_slot_1.sav'],
        'cuphead_player_data_v1_slot_2.sav': ['cuphead_player_data_v1_slot_2.sav'],
      },
    ),
    'papers-please': (
      'papers-please',
      ['headers.sav', 'names.sav', 'platover.sav', 'save_O2RA1H6VDLO5ECYNY3MO6WQJHU5ETIAY.sav', 'settings.sav', 'stash.sav', 'stats.sav'],
      {
        'all': ['headers.sav', 'names.sav', 'save_O2RA1H6VDLO5ECYNY3MO6WQJHU5ETIAY.sav', 'stash.sav', 'stats.sav'],
      },
    ),
    'toem': (
      'toem',
      ['Album Photos/1.png', 'Compendium/c.json', 'Gamesave.json', 'Settings.json', 'World_Photo/w.png'],
      {
        'all': ['Album Photos/1.png', 'Compendium/c.json', 'Gamesave.json', 'World_Photo/w.png'],
      },
    ),
    'dredge': (
      'dredge',
      ['backup-saves/slot0.json', 'dredge-settings.bin', 'dredge-settings.bin.bak', 'saves/slot0.json'],
      {
        'all': ['saves/slot0.json'],
      },
    ),
    // The only verified recipe, so the only one that binds without ever asking
    // the owner to confirm the place. It is also the only one with
    // beforeRestore, checks and inProgress, so it is the one that most needs a
    // case here.
    'stardew-valley': (
      'stardew-valley',
      [
        'EMERGENCY_SAVE',
        'Slot_1/Slot_1',
        'Slot_1/Slot_1_SVBAK',
        'Slot_1/Slot_1_old',
        'Slot_1/SaveGameInfo',
        'Slot_2/Slot_2',
        'Slot_2/Slot_2_STARDEWVALLEYSAVETMP',
        'Slot_2/SaveGameInfo',
        'stray.txt',
      ],
      {
        'Slot_1': ['Slot_1/SaveGameInfo', 'Slot_1/Slot_1'],
        'Slot_2': ['Slot_2/SaveGameInfo', 'Slot_2/Slot_2'],
      },
    ),
    'sea-of-stars': (
      'sea-of-stars',
      ['DecodedBanks/x.bank', 'SOS_SaveDataIndex.sos', 'SOS_SaveSlot99.sos', 'Unity/y.dat'],
      {
        'all': ['SOS_SaveDataIndex.sos', 'SOS_SaveSlot99.sos'],
      },
    ),
    'minecraft-bedrock': (
      'minecraft-bedrock',
      ['AbCdEf==/db/000003.log', 'AbCdEf==/level.dat', 'GhIjKl==/level.dat'],
      {
        'AbCdEf==': ['AbCdEf==/db/000003.log', 'AbCdEf==/level.dat'],
        'GhIjKl==': ['GhIjKl==/level.dat'],
      },
    ),
  };

  cases.forEach((label, c) {
    test('$label groups the files a device really has', () {
      final r = byId[c.$1];
      expect(r, isNotNull, reason: 'no recipe ${c.$1}');
      expect(groupUnits(r!, c.$2), c.$3);
    });
  });
}
