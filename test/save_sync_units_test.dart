import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

Recipe bundled(String id) => parseRecipeFiles({'$id.json': File('save_recipes/$id.json').readAsStringSync()}).recipes.single;

void main() {
  final stardew = bundled('stardew-valley');
  const files = [
    'Farm_1/Farm_1',
    'Farm_1/SaveGameInfo',
    'Farm_1/Farm_1_old',
    'Farm_1/SaveGameInfo_old',
    'Farm_1/Farm_1_SVBAK',
    'Farm_1/BACKUP_SAVE',
    'Farm_2/Farm_2',
    'Farm_2/SaveGameInfo',
    'Farm_3/Farm_3',
    'Farm_3/Farm_3_STARDEWVALLEYSAVETMP',
    'EMERGENCY_SAVE',
    'stray.txt',
  ];

  test('Stardew: one unit per farm, only the farm file and SaveGameInfo travel', () {
    final units = groupUnits(stardew, files);
    expect(units.keys, unorderedEquals(['Farm_1', 'Farm_2', 'Farm_3']));
    expect(units['Farm_1'], ['Farm_1/Farm_1', 'Farm_1/SaveGameInfo']);
    expect(units['Farm_3'], ['Farm_3/Farm_3']);
  });

  test('Stardew: a farm with a temp file is busy, the others are not', () {
    expect(busyUnits(stardew, files), {'Farm_3'});
  });

  test('file units and the all unit', () {
    final sos = bundled('sea-of-stars');
    expect(groupUnits(sos, ['SOS_SaveSlot0.sos', 'Saves/SOS_SaveSlot1.sos', 'Player.log']), {
      'all': ['SOS_SaveSlot0.sos', 'Saves/SOS_SaveSlot1.sos'],
    });
    final perFile = Recipe.parse({
      'schema': 1,
      'id': 'slots',
      'name': 'Slots',
      'status': 'draft',
      'packages': ['com.example.game'],
      'locations': [
        {'area': 'androidData', 'root': 'files/default'},
      ],
      'unit': 'file',
      'include': ['user[1-4].dat', 'shared.dat'],
      'deviceLocal': ['user*.dat.bak*'],
      'inProgress': ['{file}.new'],
    });
    const slotFiles = ['user1.dat', 'user1.dat.bak1', 'user2.dat', 'user2.dat.new', 'shared.dat'];
    expect(groupUnits(perFile, slotFiles).keys, unorderedEquals(['user1.dat', 'user2.dat', 'shared.dat']));
    expect(busyUnits(perFile, slotFiles), {'user2.dat'});
  });

  test('UnitScanner hashes unit files and marks busy units', () async {
    final tmp = Directory.systemTemp.createTempSync('units');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = p.join(tmp.path, 'Android/data/com.chucklefish.stardewvalley/files/Saves');
    for (final f in files) {
      File(p.join(root, f))
        ..createSync(recursive: true)
        ..writeAsStringSync(f);
    }
    final fs = ShellGameFs(ProcessShell(), PathGuard([p.join(tmp.path, 'Android/data/com.chucklefish.stardewvalley')]));
    final units = await UnitScanner(fs).scan(stardew, root);
    expect(units.keys, unorderedEquals(['Farm_1', 'Farm_2', 'Farm_3']));
    expect(units['Farm_1']!.busy, isFalse);
    expect(units['Farm_3']!.busy, isTrue);
    expect(units['Farm_1']!.hashes.keys, ['Farm_1/Farm_1', 'Farm_1/SaveGameInfo']);
    expect(units['Farm_1']!.files['Farm_1/Farm_1']!.size, 'Farm_1/Farm_1'.length);
  });
}
