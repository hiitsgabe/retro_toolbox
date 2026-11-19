import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  void set(CatalogState s) => state = s;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _update = GameAddon(label: 'v65536', size: 1, url: 'https://api.example.com/0100BA4026E94000/update', fileName: "Castlevania: Belmont's Curse [v65536].nsz");
const _dlc = GameAddon(kind: AddonKind.dlc, label: 'Boss Rush', size: 2, url: 'https://api.example.com/0100BA4026E94001/dlc', fileName: 'Boss Rush.zip');
const _mod = GameAddon(kind: AddonKind.mod, label: 'Hard Mode', size: 3, url: 'https://api.example.com/mods/hard', fileName: 'Hard Mode.zip');
const _game = Game(
  title: "Castlevania: Belmont's Curse.nsz",
  url: 'https://api.example.com/0100BA4026E94000/base',
  size: 4,
  consoleId: 'switch',
  updates: [_update],
  dlcs: [_dlc],
  mods: [_mod],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('addon_settings');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUpAll(() async {
    // The catalog unpacks Switch games, so a mod that followed the game would unzip.
    File(p.join(tmp.path, 'config', 'consoles.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'switch': {'name': 'Switch', 'decompress': 'unzip'},
      }));
    await CatalogService().getConsoles();
  });

  Future<SettingsNotifier> settings(Map<String, dynamic> consoles, {String downloadDir = '/d'}) async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': downloadDir},
        'consoleSettings': consoles,
      }),
    });
    final c = ProviderContainer(overrides: [catalogProvider.overrideWith((_) => _FakeCatalog())]);
    addTearDown(c.dispose);
    final n = c.read(settingsProvider.notifier);
    await n.loaded;
    return n;
  }

  final update = _update.toGame(_game);
  final dlc = _dlc.toGame(_game);
  final mod = _mod.toGame(_game);

  test('update and DLC go to the updates folder, a mod to mods/<game> in the download folder', () async {
    var n = await settings({});
    expect(n.downloadDirFor(_game), '/d');
    expect(n.downloadDirFor(update), p.join('/d', 'updates'));
    expect(n.downloadDirFor(dlc), p.join('/d', 'updates'));
    expect(n.modsDir('switch'), p.join('/d', 'mods'));
    // The game's name without its format, made safe for exFAT like every file name.
    expect(n.downloadDirFor(mod), p.join('/d', 'mods', "Castlevania Belmont's Curse"));
    n = await settings({
      'switch': {'updatesDir': '/sd/updates'},
    });
    expect(n.downloadDirFor(dlc), '/sd/updates');
    expect(n.downloadDirFor(mod), p.join('/d', 'mods', "Castlevania Belmont's Curse"));
    n = await settings({}, downloadDir: '');
    expect((n.modsDir('switch'), n.downloadDirFor(mod)), ('', ''));
  });

  test('DLC unpacks and converts like an update', () async {
    var n = await settings({
      'switch': {'autoExtract': false, 'updateDecompress': 'unzip'},
    });
    expect((n.decompressFor(dlc), n.shouldUnpack(dlc)), (Decompress.unzip, true));
    expect(n.shouldUnpack(_game), isFalse);
    n = await settings({
      'switch': {'updateDecompress': 'none', 'additionalHandler': 'nsz_decompress', 'updateHandler': 'none'},
    });
    expect(n.decompressFor(_game), Decompress.unzip);
    expect((n.decompressFor(dlc), n.shouldUnpack(dlc)), (Decompress.none, false));
    expect(n.activeHandlerFor(_game), GameHandler.nszDecompress);
    expect(n.activeHandlerFor(dlc), isNull);
    n = await settings({
      'switch': {'additionalHandler': 'nsz_decompress'},
    });
    expect(n.activeHandlerFor(dlc), GameHandler.nszDecompress);
  });

  test('a mod is never unpacked and runs no handler, whatever the game and the updates do', () async {
    var n = await settings({
      'switch': {'additionalHandler': 'nsz_decompress'},
    });
    expect((n.decompressFor(_game), n.shouldUnpack(_game), n.activeHandlerFor(_game)), (Decompress.unzip, true, GameHandler.nszDecompress));
    expect((n.decompressFor(mod), n.shouldUnpack(mod), n.activeHandlerFor(mod)), (Decompress.none, false, null));
    n = await settings({
      'switch': {'updateDecompress': 'unzip', 'additionalHandler': 'nsz_decompress', 'updateHandler': 'nsz_decompress'},
    });
    expect((n.decompressFor(mod), n.shouldUnpack(mod), n.activeHandlerFor(mod)), (Decompress.none, false, null));
  });

  test('the game state manager has an entry for every update, DLC and mod', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'generalSettings': {'downloadDir': p.join(tmp.path, 'roms')},
        'consoleSettings': {},
      }),
    });
    final catalog = _FakeCatalog();
    final c = ProviderContainer(overrides: [catalogProvider.overrideWith((_) => catalog)]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).loaded;
    c.read(gameStateManagerProvider);
    catalog.set(const CatalogState(games: [_game]));
    await Future<void>.delayed(Duration.zero);
    final ids = [_game.gameId, update.gameId, dlc.gameId, mod.gameId];
    expect(ids.toSet(), hasLength(4));
    final states = c.read(gameStateManagerProvider);
    expect(states.keys, containsAll(ids));
    expect([for (final id in ids.skip(1)) states[id]!.game.addonKind], [AddonKind.update, AddonKind.dlc, AddonKind.mod]);
  });

  test('an addon knows its game by name, through JSON and copyWith', () {
    for (final a in [update, dlc, mod]) {
      expect(a.addonOf, "Castlevania: Belmont's Curse");
      final back = Game.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect((back.addonOf, back.addonKind), (a.addonOf, a.addonKind));
      expect(a.copyWith(size: 9).addonOf, a.addonOf);
    }
    expect(_game.addonOf, isNull);
    expect(_game.toJson().containsKey('addonOf'), isFalse);
  });
}
