import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _game = Game(
  title: "Castlevania: Belmont's Curse.nsz",
  url: 'https://api.example.com/games/download/0100BA4026E94000/base',
  size: 560321310,
  consoleId: 'switch',
);
const _update = GameAddon(
  label: 'v65536',
  size: 2722082635,
  url: 'https://api.example.com/games/download/0100BA4026E94000/update',
  fileName: "Castlevania: Belmont's Curse [v65536].nsz",
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('update_downloads');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<SettingsNotifier> settings(Map<String, dynamic> consoles) async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': '/roms'},
        'consoleSettings': consoles,
      }),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(settingsProvider.notifier);
    await n.loaded;
    return n;
  }

  test('an update is a game of its console flagged as an update, through JSON too', () {
    final g = _update.toGame(_game);
    expect((g.title, g.url, g.size, g.consoleId, g.isUpdate), (_update.fileName, _update.url, _update.size, 'switch', true));
    expect(Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>).isUpdate, isTrue);
    expect(_game.isUpdate, isFalse);
    expect(_game.toJson().containsKey('isUpdate'), isFalse);
  });

  test('updates go to a folder named updates in the download folder, or the one the console chose', () async {
    var n = await settings({});
    expect(n.downloadDirFor(_game), '/roms');
    expect(n.downloadDirFor(_update.toGame(_game)), p.join('/roms', 'updates'));
    n = await settings({
      'switch': {'updatesDir': '/sd/updates'},
    });
    expect(n.downloadDirFor(_update.toGame(_game)), '/sd/updates');
    expect(n.downloadDirFor(_game), '/roms');
  });

  test('unpacking and handler for updates: the game\'s unless the console chose', () {
    expect(SettingsNotifier.resolveUpdateDecompress(null, Decompress.unzip), Decompress.unzip);
    expect(SettingsNotifier.resolveUpdateDecompress('none', Decompress.unzip), Decompress.none);
    expect(SettingsNotifier.resolveUpdateDecompress('unrar', Decompress.none), Decompress.unrar);
    expect(SettingsNotifier.resolveUpdateHandler(null, GameHandler.nszDecompress), GameHandler.nszDecompress);
    expect(SettingsNotifier.resolveUpdateHandler('none', GameHandler.nszDecompress), isNull);
    expect(SettingsNotifier.resolveUpdateHandler('chd_compress', null), GameHandler.chdCompress);
  });

  test('activeHandlerFor: an update follows the game, or runs nothing when the console says so', () async {
    var n = await settings({
      'switch': {'additionalHandler': 'nsz_decompress'},
    });
    expect(n.activeHandlerFor(_game), GameHandler.nszDecompress);
    expect(n.activeHandlerFor(_update.toGame(_game)), GameHandler.nszDecompress);
    n = await settings({
      'switch': {'additionalHandler': 'nsz_decompress', 'updateHandler': 'none'},
    });
    expect(n.activeHandlerFor(_game), GameHandler.nszDecompress);
    expect(n.activeHandlerFor(_update.toGame(_game)), isNull);
  });

  test('the update settings are console changes, and Reset clears them', () async {
    final n = await settings({
      'switch': {'updatesDir': '/sd/u', 'updateDecompress': 'none', 'updateHandler': 'none'},
    });
    expect(n.changedKeys('switch'), [AppSettings.updatesDir, AppSettings.updateDecompress, AppSettings.updateHandler]);
    await n.resetConsoleSettings('switch', n.changedKeys('switch'));
    expect(n.changedKeys('switch'), isEmpty);
    expect(n.updatesDir('switch'), p.join('/roms', 'updates'));
  });

  test('shouldUnpack: an explicit update unpacking works with Extract archives off, nothing else does', () async {
    final base = {'autoExtract': false};
    var n = await settings({
      'switch': {...base, 'updateDecompress': 'unzip'},
    });
    final zip = _update.toGame(_game).copyWith(title: 'u.zip', url: 'https://api.example.com/u.zip');
    expect(n.shouldUnpack(zip), isTrue);
    expect(n.shouldUnpack(_game), isFalse);
    n = await settings({
      'switch': {...base},
    });
    expect(n.shouldUnpack(zip), isFalse);
    n = await settings({
      'switch': {...base, 'updateDecompress': 'none'},
    });
    expect(n.shouldUnpack(zip), isFalse);
  });
}
