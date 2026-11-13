import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/local_history.dart';
import 'package:retro_toolbox/services/save_sync/puller.dart';
import 'package:retro_toolbox/services/save_sync/pusher.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

import 'save_sync_support.dart';

void main() {
  late Directory tmp;
  late TestDevice thor, odin;
  late Hub hub;
  final stardew = bundledRecipe('stardew-valley');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('puller');
    thor = TestDevice(p.join(tmp.path, 'thor'), 'AYN Thor');
    odin = TestDevice(p.join(tmp.path, 'odin'), 'AYN Odin 2 Mini');
    hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'thor-7f3a', create: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, LocalUnit>> scan(TestDevice d) => UnitScanner(d.fsFor(stardew)).scan(stardew, d.saves);

  Future<GenMeta> pushFromThor(String farm, String body) async {
    thor.writeFarm(farm, body);
    final unit = (await scan(thor))[farm]!;
    return Pusher(fs: thor.fsFor(stardew), hub: hub, stagingRoot: p.join(thor.paths.saveSync, '.staging'), deviceId: 'thor-7f3a', deviceName: 'AYN Thor')
        .push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);
  }

  LocalHistory history(TestDevice d, {int keep = 20}) => LocalHistory(p.join(d.paths.saveSync, 'history'), d.fsFor(stardew), keep: keep);

  Puller puller(TestDevice d, {int keep = 20}) =>
      Puller(fs: d.fsFor(stardew), hub: hub, history: history(d, keep: keep), stagingRoot: p.join(d.paths.saveSync, '.staging'));

  Future<void> pullInto(TestDevice d, String farm, GenMeta gen) async {
    final expected = (await scan(d))[farm]?.hashes ?? const <String, String>{};
    await puller(d).pull(recipe: stardew, binding: binding, locationDir: d.saves, unitKey: farm, gen: gen, expectedLocal: expected);
  }

  void stardewBackups(TestDevice d, String farm, {String emergencyFor = 'Farm_1'}) {
    File(p.join(d.saves, farm, 'BACKUP_SAVE')).writeAsStringSync('idx');
    File(p.join(d.saves, farm, '${farm}_SVBAK')).writeAsStringSync('old backup');
    File(p.join(d.saves, farm, '${farm}_SVEMERG')).writeAsStringSync('old emergency');
    File(p.join(d.saves, farm, '${farm}_old')).writeAsStringSync('yesterday');
    File(p.join(d.saves, 'EMERGENCY_SAVE')).writeAsBytesSync([emergencyFor.length, ...utf8.encode(emergencyFor), 1, 2, 3]);
  }

  test('replaces an older farm and moves the stale backups aside into history', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    await pullInto(odin, 'Farm_1', gen);

    expect(odin.farm('Farm_1'), contains('day 5'));
    for (final gone in ['Farm_1/BACKUP_SAVE', 'Farm_1/Farm_1_SVBAK', 'Farm_1/Farm_1_SVEMERG', 'EMERGENCY_SAVE']) {
      expect(odin.has(gone), isFalse, reason: gone);
    }
    expect(odin.has('Farm_1/Farm_1_old'), isTrue);
    final entries = await history(odin).entries('stardew-valley', 'Farm_1');
    final entry = p.join(odin.paths.saveSync, 'history', 'stardew-valley', 'Farm_1', entries.single);
    expect(File(p.join(entry, 'Farm_1/Farm_1')).readAsStringSync(), contains('day 3'));
    expect(File(p.join(entry, 'Farm_1/Farm_1_SVBAK')).readAsStringSync(), 'old backup');
    expect(File(p.join(entry, 'EMERGENCY_SAVE')).existsSync(), isTrue);
    expect(Directory(p.join(odin.paths.saveSync, '.staging')).listSync(), isEmpty);
  });

  test('an EMERGENCY_SAVE that names another farm stays', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1', emergencyFor: 'Farm_2');
    await pullInto(odin, 'Farm_1', gen);
    expect(odin.has('EMERGENCY_SAVE'), isTrue);
  });

  test('a farm new to this device gets a folder the game can write in', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.makeSavesFolder();
    await pullInto(odin, 'Farm_1', gen);
    expect(odin.farm('Farm_1'), contains('day 5'));
    expect(Directory(p.join(odin.saves, 'Farm_1')).statSync().mode & 0x1FF, 0x1FF);
  });

  test('refusals change nothing: older game, running game, missing save folder, local edited since the check', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');

    odin.shell.version = '1.6.14.7';
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRefused>()));
    odin.shell.version = '1.6.15.2';

    odin.shell.gameRunning = true;
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<SyncBlocked>()));
    odin.shell.gameRunning = false;

    final stale = (await scan(odin))['Farm_1']!.hashes;
    odin.writeFarm('Farm_1', 'day 4');
    await expectLater(
      puller(odin).pull(recipe: stardew, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: stale),
      throwsA(isA<SyncBlocked>()),
    );
    expect(odin.farm('Farm_1'), contains('day 4'));
    expect(await history(odin).entries('stardew-valley', 'Farm_1'), isEmpty);

    final fresh = TestDevice(p.join(tmp.path, 'fresh'), 'Fresh');
    await expectLater(pullInto(fresh, 'Farm_1', gen), throwsA(isA<PullRefused>()));
  });

  test('a failure while writing puts the old files back', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    odin.shell.failReplaceAt = 1; // Farm_1/Farm_1 is replaced, SaveGameInfo fails
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRolledBack>()));
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(odin.has('Farm_1/BACKUP_SAVE'), isTrue);
    expect(odin.has('EMERGENCY_SAVE'), isTrue);
  });

  test('a replace whose reply is lost after it landed is still rolled back', () async {
    final gen = await pushFromThor('Farm_1', 'day 5'); // SaveGameInfo says 1.6.15
    odin.writeFarm('Farm_1', 'day 3', version: '1.6.14');
    final info = File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync();
    odin.shell.loseReplyOnMvTo = 'Farm_1/SaveGameInfo';
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNull)));
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync(), info);
  });

  String? journalOf(TestDevice d) {
    final root = Directory(p.join(d.paths.saveSync, 'history'));
    if (!root.existsSync()) return null;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (p.basename(f.path) == '.pull.json') return f.path;
    }
    return null;
  }

  test('a rollback that fails keeps its journal, and recover puts the old unit back', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    final info = File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync();
    odin.shell.failReplaceFrom = 1; // Farm_1/Farm_1 is replaced, SaveGameInfo fails, and so does putting Farm_1/Farm_1 back
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNotNull)));
    expect(odin.farm('Farm_1'), contains('day 5'));
    final journal = journalOf(odin);
    expect(journal, isNotNull);
    expect((jsonDecode(File(journal!).readAsStringSync()) as Map)['gen'], gen.gen);

    odin.shell.failReplaceFrom = -1;
    final r = await puller(odin).recover(stardew);
    expect(r.recovered, ['Farm_1']);
    expect(r.stuck, isEmpty);
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync(), info);
    for (final back in ['Farm_1/BACKUP_SAVE', 'Farm_1/Farm_1_SVBAK', 'Farm_1/Farm_1_SVEMERG', 'EMERGENCY_SAVE']) {
      expect(odin.has(back), isTrue, reason: back);
    }
    expect(journalOf(odin), isNull);
    final again = await puller(odin).recover(stardew);
    expect(again.recovered, isEmpty);
    expect(again.stuck, isEmpty);
  });

  test('a game started during the pull rolls it back', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    odin.shell.startGameAfterReplaces = 2;
    await expectLater(
      pullInto(odin, 'Farm_1', gen),
      throwsA(isA<PullRolledBack>().having((e) => e.cause, 'cause', isA<SyncBlocked>()).having((e) => e.rollbackError, 'rollbackError', isNull)),
    );
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(odin.has('Farm_1/BACKUP_SAVE'), isTrue);
    expect(odin.has('EMERGENCY_SAVE'), isTrue);
    expect(journalOf(odin), isNull);
  });

  test('a unit file the gen lacks moves into the history entry', () async {
    final noVersion = Recipe.parse({...stardew.raw, 'version': null});
    thor.writeFarm('Farm_1', 'day 5');
    File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).deleteSync();
    final unit = (await UnitScanner(thor.fsFor(noVersion)).scan(noVersion, thor.saves))['Farm_1']!;
    final pusher = Pusher(
      fs: thor.fsFor(noVersion),
      hub: hub,
      stagingRoot: p.join(thor.paths.saveSync, '.staging'),
      deviceId: 'thor-7f3a',
      deviceName: 'AYN Thor',
    );
    final gen = await pusher.push(recipe: noVersion, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);
    expect(gen.files.keys, ['Farm_1/Farm_1']);

    odin.writeFarm('Farm_1', 'day 3');
    final info = File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync();
    File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).setLastModifiedSync(DateTime.utc(2020)); // a copy would get the current time
    final expected = (await UnitScanner(odin.fsFor(noVersion)).scan(noVersion, odin.saves))['Farm_1']!.hashes;
    await puller(odin).pull(recipe: noVersion, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected);
    expect(odin.farm('Farm_1'), contains('day 5'));
    expect(odin.has('Farm_1/SaveGameInfo'), isFalse);
    final entry = p.join(odin.paths.saveSync, 'history', 'stardew-valley', 'Farm_1', (await history(odin).entries('stardew-valley', 'Farm_1')).single);
    expect(File(p.join(entry, 'Farm_1/SaveGameInfo')).readAsStringSync(), info);
    expect(File(p.join(entry, 'Farm_1/SaveGameInfo')).lastModifiedSync().toUtc(), DateTime.utc(2020), reason: 'moved, not copied');
  });

  test('a move aside that died after writing part of its destination leaves the original alone', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    File(p.join(odin.saves, 'Farm_1', 'BACKUP_SAVE')).writeAsStringSync('the real backup index');
    odin.shell.partialMvFrom = 'Farm_1/BACKUP_SAVE';
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNull)));
    expect(File(p.join(odin.saves, 'Farm_1', 'BACKUP_SAVE')).readAsStringSync(), 'the real backup index');
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  test('a move of a unit file the gen lacks that died half way leaves the original alone', () async {
    final noVersion = Recipe.parse({...stardew.raw, 'version': null});
    thor.writeFarm('Farm_1', 'day 5');
    File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).deleteSync();
    final unit = (await UnitScanner(thor.fsFor(noVersion)).scan(noVersion, thor.saves))['Farm_1']!;
    final gen = await Pusher(
      fs: thor.fsFor(noVersion),
      hub: hub,
      stagingRoot: p.join(thor.paths.saveSync, '.staging'),
      deviceId: 'thor-7f3a',
      deviceName: 'AYN Thor',
    ).push(recipe: noVersion, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);

    odin.writeFarm('Farm_1', 'day 3');
    final info = File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync();
    final expected = (await UnitScanner(odin.fsFor(noVersion)).scan(noVersion, odin.saves))['Farm_1']!.hashes;
    odin.shell.partialMvFrom = 'Farm_1/SaveGameInfo';
    await expectLater(
      puller(odin).pull(recipe: noVersion, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNull)),
    );
    expect(File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync(), info);
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  test('a move aside whose reply is lost after it landed is still rolled back', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    odin.shell.loseReplyOnMvTo = 'Farm_1/BACKUP_SAVE';
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNull)));
    expect(odin.has('Farm_1/BACKUP_SAVE'), isTrue, reason: 'the journal is gone, so only the rollback can put it back');
    expect(File(p.join(odin.saves, 'Farm_1', 'BACKUP_SAVE')).readAsStringSync(), 'idx');
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  test('a move of a unit file the gen lacks whose reply is lost after it landed is still rolled back', () async {
    final noVersion = Recipe.parse({...stardew.raw, 'version': null});
    thor.writeFarm('Farm_1', 'day 5');
    File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).deleteSync();
    final unit = (await UnitScanner(thor.fsFor(noVersion)).scan(noVersion, thor.saves))['Farm_1']!;
    final gen = await Pusher(
      fs: thor.fsFor(noVersion),
      hub: hub,
      stagingRoot: p.join(thor.paths.saveSync, '.staging'),
      deviceId: 'thor-7f3a',
      deviceName: 'AYN Thor',
    ).push(recipe: noVersion, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);

    odin.writeFarm('Farm_1', 'day 3');
    final info = File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync();
    final expected = (await UnitScanner(odin.fsFor(noVersion)).scan(noVersion, odin.saves))['Farm_1']!.hashes;
    odin.shell.loseReplyOnMvTo = 'Farm_1/SaveGameInfo';
    await expectLater(
      puller(odin).pull(recipe: noVersion, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRolledBack>().having((e) => e.rollbackError, 'rollbackError', isNull)),
    );
    expect(odin.has('Farm_1/SaveGameInfo'), isTrue, reason: 'the journal is gone, so only the rollback can put it back');
    expect(File(p.join(odin.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync(), info);
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  test('a damaged hub copy and a gen with files outside the unit are refused', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    File(p.join(tmp.path, 'hub', 'units', 'stardew-valley', 'Farm_1', '${gen.gen}.zip')).writeAsBytesSync([0, 1, 2]);
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<PayloadCorrupt>()));

    final planted = Archive()
      ..addFile(ArchiveFile.bytes('Farm_1/Farm_1', utf8.encode('<SaveGame>x</SaveGame>')))
      ..addFile(ArchiveFile.bytes('EMERGENCY_SAVE', [1, 2]));
    final zip = ZipEncoder().encodeBytes(planted);
    final sha = sha256.convert(zip).toString();
    final evil = GenMeta(
      gen: makeGenId(DateTime.utc(2026, 11, 11), 'evil-0000', sha),
      parents: const [],
      recipe: 'stardew-valley',
      unit: 'Farm_1',
      device: 'evil-0000',
      deviceName: 'Evil',
      createdAt: DateTime.utc(2026, 11, 11),
      package: stardewPkg,
      files: {
        for (final f in planted) f.name: GenFile(sha256.convert(f.content).toString(), f.content.length),
      },
      gameVersion: '1.6.15',
      payloadSha256: sha,
    );
    await hub.put(evil, zip);
    await expectLater(
        pullInto(odin, 'Farm_1', evil), throwsA(isA<PullRefused>().having((e) => e.reason, 'reason', contains('not part of Farm_1'))));
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  /// What a pull of [gen] into [d] leaves when the app dies mid-way: the
  /// entry with copies of the unit, [aside] moved into it, [written] already
  /// in the saves folder, and the journal.
  Future<String> interrupt(TestDevice d, GenMeta gen, String unitKey, {List<String> aside = const [], Map<String, String> written = const {}}) async {
    final before = (await scan(d))[unitKey]?.hashes ?? const <String, String>{};
    final entry = await history(d).newEntry('stardew-valley', unitKey, 'before-${gen.gen}');
    await history(d).snapshot(entry, d.saves, before.keys);
    for (final rel in aside) {
      File(p.join(entry, rel)).parent.createSync(recursive: true);
      File(p.join(d.saves, rel)).renameSync(p.join(entry, rel));
    }
    for (final e in written.entries) {
      File(p.join(d.saves, e.key))
        ..createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
    File(p.join(entry, '.pull.json')).writeAsStringSync(jsonEncode({
      'gen': gen.gen,
      'unit': unitKey,
      'locationDir': d.saves,
      'before': before,
      'genFiles': gen.hashes,
      'aside': aside,
    }));
    return entry;
  }

  const aside = ['EMERGENCY_SAVE', 'Farm_1/BACKUP_SAVE', 'Farm_1/Farm_1_SVBAK', 'Farm_1/Farm_1_SVEMERG'];

  List<String> recoverEntries(TestDevice d, String unitKey) => [
        for (final e in Directory(p.join(d.paths.saveSync, 'history', 'stardew-valley', unitKey)).listSync())
          if (e.path.endsWith('-before-recover')) e.path,
      ];

  test('recover moves the backups a pull put aside back, with the old farm', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    expect(odin.has('Farm_1/BACKUP_SAVE'), isFalse);
    expect(odin.farm('Farm_1'), contains('day 5'));

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, ['Farm_1']);
    expect(r.stuck, isEmpty);
    expect(odin.farm('Farm_1'), contains('day 3'));
    for (final rel in aside) {
      expect(odin.has(rel), isTrue, reason: rel);
    }
    expect(File(p.join(odin.saves, 'Farm_1', 'Farm_1_SVBAK')).readAsStringSync(), 'old backup');
    expect(journalOf(odin), isNull);
  });

  test('recover removes the files of a farm new to this device', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.makeSavesFolder();
    await interrupt(odin, gen, 'Farm_1', written: {'Farm_1/Farm_1': thor.farm('Farm_1')});

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, ['Farm_1']);
    expect(odin.has('Farm_1/Farm_1'), isFalse);
    expect(odin.has('Farm_1/SaveGameInfo'), isFalse);
    expect(journalOf(odin), isNull);
  });

  test('recover after the game saved again restores nothing and keeps both versions', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    final entry = await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    odin.writeFarm('Farm_1', 'day 9');

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, isEmpty);
    final kept = recoverEntries(odin, 'Farm_1').single;
    expect(r.stuck.single.unit, 'Farm_1');
    expect(r.stuck.single.message, 'an interrupted pull could not be undone because the files changed since; both versions are kept in $kept');
    expect(File(p.join(kept, 'Farm_1/Farm_1')).readAsStringSync(), contains('day 9'));
    expect(File(p.join(entry, 'Farm_1/Farm_1')).readAsStringSync(), contains('day 3'));
    expect(odin.farm('Farm_1'), contains('day 9'));
    for (final rel in aside) {
      expect(odin.has(rel), isFalse, reason: rel);
    }
    expect(journalOf(odin), p.join(entry, '.pull.json'));

    final again = await puller(odin).recover(stardew);
    expect(again.stuck.single.message, r.stuck.single.message);
    expect(recoverEntries(odin, 'Farm_1'), [kept], reason: 'an unchanged unit is not copied again');
  });

  test('recover restores nothing when its copy of the unit does not verify', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    odin.shell.afterRun = (argv) {
      if (argv.first == 'cp' && argv.last.contains('-before-recover/')) File(argv.last).writeAsBytesSync([0], mode: FileMode.append);
    };

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.unit, 'Farm_1');
    expect(r.stuck.single.message, contains('does not match'));
    expect(odin.farm('Farm_1'), contains('day 5'));
    expect(odin.has('Farm_1/BACKUP_SAVE'), isFalse);
    expect(journalOf(odin), isNotNull);
  });

  test('a journal recover cannot finish is reported stuck and the other units still recover', () async {
    final gen1 = await pushFromThor('Farm_1', 'day 5');
    final gen2 = await pushFromThor('Farm_2', 'two day 5');
    odin.writeFarm('Farm_1', 'day 3');
    odin.writeFarm('Farm_2', 'two day 3');
    await interrupt(odin, gen1, 'Farm_1', written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    final entry2 = await interrupt(odin, gen2, 'Farm_2', written: {'Farm_2/Farm_2': thor.farm('Farm_2')});
    File(p.join(entry2, 'Farm_2/Farm_2')).deleteSync();

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, ['Farm_1']);
    expect(odin.farm('Farm_1'), contains('day 3'));
    final kept = recoverEntries(odin, 'Farm_2').single;
    expect(r.stuck.single.unit, 'Farm_2');
    expect(r.stuck.single.message, allOf(contains('Farm_2/Farm_2 is missing'), contains(kept)));
    expect(odin.farm('Farm_2'), contains('two day 5'));
    expect(File(p.join(entry2, '.pull.json')).existsSync(), isTrue);
  });

  test('a history copy that does not match its source stops the pull before the game folder changes', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    final was = await scan(odin);
    odin.shell.afterRun = (argv) {
      if (argv.first == 'cp' && argv.last.contains('/history/')) File(argv.last).writeAsBytesSync([0], mode: FileMode.append);
    };
    await expectLater(pullInto(odin, 'Farm_1', gen), throwsA(isA<SyncBlocked>()));
    odin.shell.afterRun = null;
    expect((await scan(odin))['Farm_1']!.hashes, was['Farm_1']!.hashes);
    for (final rel in aside) {
      expect(odin.has(rel), isTrue, reason: rel);
    }
    expect(journalOf(odin), isNull);
  });

  test('trimming history keeps the entry the pull just made even when another sorts after it', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    final future = Directory(p.join(odin.paths.saveSync, 'history', 'stardew-valley', 'Farm_1', '20990101T000000Z-before-x'))..createSync(recursive: true);
    final expected = (await scan(odin))['Farm_1']!.hashes;
    await puller(odin, keep: 1).pull(recipe: stardew, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected);
    final names = await history(odin).entries('stardew-valley', 'Farm_1');
    expect(names.first, p.basename(future.path));
    expect(names, hasLength(2));
    expect(File(p.join(future.parent.path, names.last, 'Farm_1/Farm_1')).readAsStringSync(), contains('day 3'));
  });

  test('a beforeRestore path inside another unit refuses the pull and moves nothing', () async {
    final reaching = Recipe.parse({
      ...stardew.raw,
      'beforeRestore': [
        {
          'moveAside': ['Other/Other'],
        },
      ],
    });
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    odin.writeFarm('Other', 'other farm');
    final expected = (await scan(odin))['Farm_1']!.hashes;
    await expectLater(
      puller(odin).pull(recipe: reaching, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRefused>()),
    );
    expect(odin.farm('Other'), contains('other farm'));
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(journalOf(odin), isNull);
  });

  test('a unit stuck by an error keeps one copy of itself across recovers', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    final entry = await interrupt(odin, gen, 'Farm_1', written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    File(p.join(entry, 'Farm_1/Farm_1')).deleteSync();

    final r = await puller(odin).recover(stardew);
    final kept = recoverEntries(odin, 'Farm_1').single;
    expect(r.stuck.single.entry, kept);
    final again = await puller(odin).recover(stardew);
    expect(recoverEntries(odin, 'Farm_1'), [kept], reason: 'an unchanged unit is not copied again');
    expect(again.stuck.single.message, r.stuck.single.message);
  });

  test('recover restores nothing when a copy of a changed file is missing from the entry', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3', version: '1.6.14');
    stardewBackups(odin, 'Farm_1');
    final entry = await interrupt(
      odin,
      gen,
      'Farm_1',
      aside: aside,
      written: {'Farm_1/Farm_1': thor.farm('Farm_1'), 'Farm_1/SaveGameInfo': File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync()},
    );
    File(p.join(entry, 'Farm_1/SaveGameInfo')).deleteSync();

    final r = await puller(odin).recover(stardew);
    expect(odin.farm('Farm_1'), contains('day 5'), reason: 'Farm_1/Farm_1 sorts first and still has its copy');
    for (final rel in aside) {
      expect(odin.has(rel), isFalse, reason: rel);
    }
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.message, contains('Farm_1/SaveGameInfo is missing'));
    expect(journalOf(odin), p.join(entry, '.pull.json'));
  });

  test('a backup whose copy is gone from the entry leaves the unit stuck, not recovered', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    final entry = await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    File(p.join(entry, 'Farm_1/Farm_1_SVBAK')).deleteSync();

    final r = await puller(odin).recover(stardew);
    expect(odin.farm('Farm_1'), contains('day 5'));
    for (final rel in aside) {
      expect(odin.has(rel), isFalse, reason: rel);
    }
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.message, contains('Farm_1/Farm_1_SVBAK is missing'));
    expect(File(p.join(entry, 'Farm_1/BACKUP_SAVE')).existsSync(), isTrue);
    expect(journalOf(odin), p.join(entry, '.pull.json'));
  });

  test('recover removes nothing from a new farm the game saved over after the interruption', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.makeSavesFolder();
    final entry = await interrupt(odin, gen, 'Farm_1', written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    File(p.join(odin.saves, 'Farm_1', 'Farm_1')).writeAsStringSync('<?xml version="1.0"?><SaveGame>day 6</SaveGame>');

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.unit, 'Farm_1');
    expect(odin.farm('Farm_1'), contains('day 6'));
    expect(journalOf(odin), p.join(entry, '.pull.json'));
  });

  test('a backup the game made again while its copy is still in the entry leaves the unit stuck', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    final entry = await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    File(p.join(odin.saves, 'Farm_1', 'BACKUP_SAVE')).writeAsStringSync('new idx');

    final r = await puller(odin).recover(stardew);
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.unit, 'Farm_1');
    expect(odin.farm('Farm_1'), contains('day 5'));
    expect(File(p.join(odin.saves, 'Farm_1', 'BACKUP_SAVE')).readAsStringSync(), 'new idx');
    expect(File(p.join(entry, 'Farm_1/BACKUP_SAVE')).readAsStringSync(), 'idx');
    for (final rel in aside.where((r) => r != 'Farm_1/BACKUP_SAVE')) {
      expect(odin.has(rel), isFalse, reason: rel);
      expect(File(p.join(entry, rel)).existsSync(), isTrue, reason: rel);
    }
    expect(journalOf(odin), p.join(entry, '.pull.json'));
  });

  test("a beforeRestore path in another farm's folder is refused even when no unit owns it", () async {
    final reaching = Recipe.parse({
      ...stardew.raw,
      'beforeRestore': [
        {
          'moveAside': ['Other/BACKUP_SAVE'],
        },
      ],
    });
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    odin.writeFarm('Other', 'other farm');
    File(p.join(odin.saves, 'Other', 'BACKUP_SAVE')).writeAsStringSync('other idx');
    final expected = (await scan(odin))['Farm_1']!.hashes;
    await expectLater(
      puller(odin).pull(recipe: reaching, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRefused>()),
    );
    expect(File(p.join(odin.saves, 'Other', 'BACKUP_SAVE')).readAsStringSync(), 'other idx');
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(journalOf(odin), isNull);
  });

  test("a beforeRestore path that another file unit's deviceLocal pattern claims is refused", () async {
    final slots = Recipe.parse({
      ...stardew.raw,
      'unit': 'file',
      'include': ['*.sav'],
      'deviceLocal': ['{file}.bak'],
      'inProgress': <String>[],
      'beforeRestore': [
        {
          'moveAside': ['{file}.bak', 'slot2.sav.bak'],
        },
      ],
      'checks': <Object>[],
      'version': null,
    });
    Directory(thor.saves).createSync(recursive: true);
    File(p.join(thor.saves, 'slot1.sav')).writeAsStringSync('slot one day 5');
    final unit = (await UnitScanner(thor.fsFor(slots)).scan(slots, thor.saves))['slot1.sav']!;
    final pusher = Pusher(fs: thor.fsFor(slots), hub: hub, stagingRoot: p.join(thor.paths.saveSync, '.staging'), deviceId: 'thor-7f3a', deviceName: 'AYN Thor');
    final gen = await pusher.push(recipe: slots, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);

    odin.makeSavesFolder();
    File(p.join(odin.saves, 'slot1.sav')).writeAsStringSync('slot one day 3');
    File(p.join(odin.saves, 'slot2.sav')).writeAsStringSync('slot two');
    File(p.join(odin.saves, 'slot2.sav.bak')).writeAsStringSync('slot two backup');
    final expected = (await UnitScanner(odin.fsFor(slots)).scan(slots, odin.saves))['slot1.sav']!.hashes;
    await expectLater(
      puller(odin).pull(recipe: slots, binding: binding, locationDir: odin.saves, unitKey: 'slot1.sav', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRefused>().having((e) => e.reason, 'reason', contains('slot2.sav'))),
    );
    expect(File(p.join(odin.saves, 'slot2.sav.bak')).readAsStringSync(), 'slot two backup');
    expect(File(p.join(odin.saves, 'slot1.sav')).readAsStringSync(), 'slot one day 3');
    expect(journalOf(odin), isNull);
  });

  test("a beforeRestore name that is another farm's folder is refused, and the farm stays", () async {
    final reaching = Recipe.parse({
      ...stardew.raw,
      'beforeRestore': [
        {
          'moveAside': ['Other'],
        },
      ],
    });
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    odin.writeFarm('Other', 'other farm');
    final expected = (await scan(odin))['Farm_1']!.hashes;
    await expectLater(
      puller(odin).pull(recipe: reaching, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRefused>()),
    );
    expect(odin.farm('Other'), contains('other farm'));
    expect(odin.farm('Farm_1'), contains('day 3'));
    expect(journalOf(odin), isNull);
  });

  test('a beforeRestore path that names any folder is refused and rolled back', () async {
    final reaching = Recipe.parse({
      ...stardew.raw,
      'beforeRestore': [
        {
          'moveAside': ['Farm_1/Nested'],
        },
      ],
    });
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    File(p.join(odin.saves, 'Farm_1', 'Nested', 'keep.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('keep');
    final expected = (await scan(odin))['Farm_1']!.hashes;
    await expectLater(
      puller(odin).pull(recipe: reaching, binding: binding, locationDir: odin.saves, unitKey: 'Farm_1', gen: gen, expectedLocal: expected),
      throwsA(isA<PullRolledBack>()),
    );
    expect(File(p.join(odin.saves, 'Farm_1', 'Nested', 'keep.txt')).readAsStringSync(), 'keep');
    expect(odin.farm('Farm_1'), contains('day 3'));
  });

  test('recover restores nothing when a copy of a changed file is there but damaged', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3', version: '1.6.14');
    stardewBackups(odin, 'Farm_1');
    final entry = await interrupt(
      odin,
      gen,
      'Farm_1',
      aside: aside,
      written: {'Farm_1/Farm_1': thor.farm('Farm_1'), 'Farm_1/SaveGameInfo': File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).readAsStringSync()},
    );
    File(p.join(entry, 'Farm_1/SaveGameInfo')).writeAsStringSync('garbage');

    final r = await puller(odin).recover(stardew);
    expect(odin.farm('Farm_1'), contains('day 5'), reason: 'nothing is restored when one copy does not match its old hash');
    expect(r.recovered, isEmpty);
    expect(r.stuck.single.message, contains('Farm_1/SaveGameInfo'));
    expect(journalOf(odin), p.join(entry, '.pull.json'));
  });

  test('a before-recover copy that does not verify is removed, so history does not grow per recover', () async {
    final gen = await pushFromThor('Farm_1', 'day 5');
    odin.writeFarm('Farm_1', 'day 3');
    stardewBackups(odin, 'Farm_1');
    await interrupt(odin, gen, 'Farm_1', aside: aside, written: {'Farm_1/Farm_1': thor.farm('Farm_1')});
    odin.shell.afterRun = (argv) {
      if (argv.first == 'cp' && argv.last.contains('-before-recover')) File(argv.last).writeAsBytesSync([0], mode: FileMode.append);
    };
    for (var i = 0; i < 3; i++) {
      final r = await puller(odin).recover(stardew);
      expect(r.stuck.single.unit, 'Farm_1');
    }
    final left = Directory(p.join(odin.paths.saveSync, 'history', 'stardew-valley', 'Farm_1'))
        .listSync()
        .where((e) => p.basename(e.path).contains('-before-recover'))
        .toList();
    expect(left, isEmpty);
  });
}
