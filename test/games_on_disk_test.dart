import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/launcher/games_on_disk.dart';

class FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Each console's library dir, by id.
class DirSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  DirSettings(this.dirs) : super(const AppSettings());

  final Map<String, String> dirs;

  @override
  String getDownloadDir(String? consoleId) => dirs[consoleId] ?? '';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// A cue/bin console whose handler writes .chd, a zip console that unpacks to
// .sfc, and a console sharing the PlayStation's .chd.
const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], gameFilesFormat: ['.CUE', '.bin'], additionalHandler: GameHandler.chdCompress);
const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], originalFormat: ['.zip'], gameFilesFormat: ['.sfc', '.smc']);
const _ps2 = Console(id: 'ps2', name: 'PlayStation 2', urls: [], gameFilesFormat: ['.iso', '.chd']);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-on-disk-'));
  tearDown(() => tmp.delete(recursive: true));

  void touch(String rel) => File(p.join(tmp.path, rel)).createSync(recursive: true);

  test('onDiskFormats is what is sent, what unpacking keeps and what a handler writes, lowercased', () {
    expect(_psx.onDiskFormats, {'.cue', '.bin', '.chd'});
    expect(_snes.onDiskFormats, {'.zip', '.sfc', '.smc'});
    expect(const Console(id: 'x', name: 'X', urls: []).onDiskFormats, isEmpty);
  });

  test('a root file in a known format counts', () async {
    touch('Crash.cue');
    expect(await hasGamesOnDisk(tmp.path, _psx.onDiskFormats), isTrue);
  });

  test('a .chd-only folder counts for a cue/bin console that converts to CHD', () async {
    touch('Crash.chd');
    expect(await hasGamesOnDisk(tmp.path, _psx.onDiskFormats), isTrue);
  });

  test('a loose .zip counts for a zip console', () async {
    touch('Mario World.zip');
    expect(await hasGamesOnDisk(tmp.path, _snes.onDiskFormats), isTrue);
  });

  test('a folder with a game directly inside counts, one nested deeper does not', () async {
    touch('Spyro/Spyro.cue');
    expect(await hasGamesOnDisk(tmp.path, _psx.onDiskFormats), isTrue);
    File(p.join(tmp.path, 'Spyro', 'Spyro.cue')).deleteSync();
    touch('Spyro/Disc 1/Spyro.cue');
    expect(await hasGamesOnDisk(tmp.path, _psx.onDiskFormats), isFalse);
  });

  test('other files, an empty folder and a missing one hold no games', () async {
    touch('notes.txt');
    touch('saves/Crash.srm');
    expect(await hasGamesOnDisk(tmp.path, _psx.onDiskFormats), isFalse);
    expect(await hasGamesOnDisk(p.join(tmp.path, 'missing'), _psx.onDiskFormats), isFalse);
    expect(await hasGamesOnDisk('', _psx.onDiskFormats), isFalse);
  });

  test('in a shared dir an extension two consoles claim is no one\'s', () {
    expect(ownFormats(_psx, [_psx, _ps2]), {'.cue', '.bin'});
    expect(ownFormats(_ps2, [_psx, _ps2]), {'.iso'});
    expect(ownFormats(_psx, [_psx]), _psx.onDiskFormats);
  });

  group('gamesOnDiskProvider', () {
    Future<bool> onDisk(String consoleId, Map<String, String> dirs) {
      final c = ProviderContainer(overrides: [
        appStateProvider.overrideWith((ref) => FakeApp(const AppState(consoles: {'psx': _psx, 'snes': _snes, 'ps2': _ps2}))),
        settingsProvider.overrideWith((ref) => DirSettings(dirs)),
      ]);
      addTearDown(c.dispose);
      return c.read(gamesOnDiskProvider(consoleId).future);
    }

    test('reads the console\'s own dir', () async {
      touch('psx/Crash.chd');
      expect(await onDisk('psx', {'psx': p.join(tmp.path, 'psx'), 'snes': p.join(tmp.path, 'snes')}), isTrue);
      expect(await onDisk('snes', {'psx': p.join(tmp.path, 'psx'), 'snes': p.join(tmp.path, 'snes')}), isFalse);
    });

    test('a dir two consoles share is split by their own formats', () async {
      touch('Crash.chd');
      final shared = {'psx': tmp.path, 'ps2': tmp.path};
      expect(await onDisk('psx', shared), isFalse, reason: 'the PlayStation 2 claims .chd too');
      expect(await onDisk('ps2', shared), isFalse);
      touch('Spyro.cue');
      expect(await onDisk('psx', shared), isTrue);
      expect(await onDisk('ps2', shared), isFalse);
    });

    test('a console with no dir, or unknown, has none', () async {
      touch('Crash.chd');
      expect(await onDisk('psx', const {}), isFalse);
      expect(await onDisk('gone', {'gone': tmp.path}), isFalse);
    });
  });
}
