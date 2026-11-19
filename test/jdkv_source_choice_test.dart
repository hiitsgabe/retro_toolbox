import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:retro_toolbox/services/jksv_meta.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _id = '0100000000ABC000';

/// testWidgets mocks every HttpClient in the file; the round trip needs a real one.
class _RealHttp extends HttpOverrides {}

/// Recipes without any disk, so the screen test needs no runAsync.
class _RecipesOnlyHub extends Hub {
  _RecipesOnlyHub() : super(FolderBackend(Directory('/nonexistent')));

  @override
  Future<Map<String, HubRecipe>> recipes() async => {
        for (final r in _recipes) r['id'] as String: HubRecipe(source: 'repo', device: 'odin-02c4', publishedAt: DateTime.utc(2026, 11, 1), recipe: r),
      };
}

final _recipes = [
  {'id': 'eden', 'name': 'Eden', 'unit': 'folder'},
  {'id': 'stardew-valley', 'name': 'Stardew Valley', 'unit': 'file'},
  {'id': 'yuzu', 'name': 'yuzu', 'unit': 'folder'},
];

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  group('choice', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('encodes as folder or hub:<recipe>, and anything else reads as the folder', () {
      expect(const JdkvSourceChoice.folder().encode(), 'folder');
      expect(const JdkvSourceChoice.hub('eden').encode(), 'hub:eden');
      expect(JdkvSourceChoice.decode('hub:eden'), const JdkvSourceChoice.hub('eden'));
      expect(JdkvSourceChoice.decode(null), const JdkvSourceChoice.folder());
      expect(JdkvSourceChoice.decode('folder'), const JdkvSourceChoice.folder());
      expect(JdkvSourceChoice.decode('hub:'), const JdkvSourceChoice.folder());
    });

    test('defaults to the folder, then persists and restores a hub recipe', () async {
      final first = JdkvServerNotifier();
      addTearDown(first.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(first.state.source, const JdkvSourceChoice.folder());
      await first.setSource(const JdkvSourceChoice.hub('eden'));
      expect((await SharedPreferences.getInstance()).getString('jdkv_source'), 'hub:eden');

      final second = JdkvServerNotifier();
      addTearDown(second.dispose);
      await _until(() => second.state.source == const JdkvSourceChoice.hub('eden'));
    });

    test('hub recipes are the folder-unit ones, by name', () async {
      final n = JdkvServerNotifier(openHub: () async => (hub: _RecipesOnlyHub(), deviceId: 'thor-7f3a'));
      addTearDown(n.dispose);
      await n.loadHubRecipes();
      expect(n.state.hubConfigured, isTrue);
      expect(n.state.hubRecipes, {'eden': 'Eden', 'yuzu': 'yuzu'});
    });

    test('no hub leaves the hub unconfigured', () async {
      final n = JdkvServerNotifier(openHub: () async => null);
      addTearDown(n.dispose);
      await n.loadHubRecipes();
      expect(n.state.hubConfigured, isFalse);
      expect(n.state.hubRecipes, isEmpty);
    });

    test('starting on a hub recipe without a hub says to set up Save Sync', () async {
      SharedPreferences.setMockInitialValues({'jdkv_source': 'hub:eden'});
      final n = JdkvServerNotifier(openHub: () async => null);
      addTearDown(n.dispose);
      await _until(() => n.state.source == const JdkvSourceChoice.hub('eden'));
      await n.enable();
      expect(n.state.running, isFalse);
      expect(n.state.error, 'Set up Save Sync first.');
    });

    test('a hub error at start goes to the error line', () async {
      SharedPreferences.setMockInitialValues({'jdkv_source': 'hub:eden'});
      final n = JdkvServerNotifier(openHub: () async => throw const HubMissing('folder:/sdcard/Saves'));
      addTearDown(n.dispose);
      await _until(() => n.state.source == const JdkvSourceChoice.hub('eden'));
      await n.enable();
      expect(n.state.running, isFalse);
      expect(n.state.error, contains('No hub at folder:/sdcard/Saves'));
    });
  });

  test('a hub source serves its titles and pulls an upload into a new gen', () async {
    SharedPreferences.setMockInitialValues({'jdkv_server_port_v2': 0, 'jdkv_source': 'hub:eden'});
    final tmp = Directory.systemTemp.createTempSync('jdkv_hub');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'thor-7f3a', create: true);
    final payload = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('$_id/slot', 'emu'.codeUnits)));
    final sha = sha256.convert(payload).toString();
    final first = GenMeta(
      gen: makeGenId(DateTime.utc(2026, 11, 18), 'odin-02c4', sha),
      parents: const [],
      recipe: 'eden',
      unit: _id,
      device: 'odin-02c4',
      deviceName: 'Odin',
      createdAt: DateTime.utc(2026, 11, 18),
      package: 'dev.eden.eden_emulator',
      files: {'$_id/slot': GenFile(sha256.convert('emu'.codeUnits).toString(), 3)},
      payloadSha256: sha,
    );
    await hub.put(first, payload);

    final n = JdkvServerNotifier(openHub: () async => (hub: hub, deviceId: 'thor-7f3a'));
    addTearDown(n.dispose);
    await _until(() => n.state.source == const JdkvSourceChoice.hub('eden') && n.state.port == 0);
    await n.enable();
    expect(n.state.error, isNull);
    expect(n.state.running, isTrue);

    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      addTearDown(client.close);
      final list = await (await client.openUrl('PROPFIND', Uri.parse('http://127.0.0.1:${n.state.port}/'))).close();
      expect(await list.transform(utf8.decoder).join(), contains('<d:href>/$_id</d:href>'));

      final upload = Archive()
        ..addFile(ArchiveFile.bytes('slot', 'switch'.codeUnits))
        ..addFile(ArchiveFile.bytes(JksvMeta.fileName, JksvMeta.encode(applicationId: int.parse(_id, radix: 16))));
      final put = await client.openUrl('PUT', Uri.parse('http://127.0.0.1:${n.state.port}/$_id/backup.zip'));
      put.add(ZipEncoder().encodeBytes(upload));
      expect((await put.close()).statusCode, 201);
    }, _RealHttp());

    await _until(() => n.state.incoming.isNotEmpty);
    await n.pull(_id, timestamp: '20261119-120000');
    expect(n.state.error, isNull);
    final gens = await Hub(hub.backend).gens('eden', _id);
    final mine = gens.singleWhere((g) => g.gen != first.gen);
    expect(mine.parents, [first.gen]);
    expect(mine.device, 'thor-7f3a');
    expect(mine.deviceName, 'Switch (JKSV)');
    expect(mine.package, 'jksv');
    expect(ZipDecoder().decodeBytes(await hub.payload(mine)).findFile('$_id/slot')!.content, 'switch'.codeUnits);
    await n.disable();
  });

  group('screen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    });

    Future<void> show(WidgetTester t, JdkvHubOpener openHub) async {
      await t.pumpWidget(ProviderScope(
        overrides: [jdkvServerProvider.overrideWith((ref) => JdkvServerNotifier(openHub: openHub))],
        child: const MaterialApp(home: JdkvServerScreen()),
      ));
      await t.pump();
      await t.pump();
    }

    ListTile tile(WidgetTester t, String title) => t.widget<ListTile>(find.widgetWithText(ListTile, title));

    testWidgets('without a hub the Save Sync option is disabled with a hint', (t) async {
      await show(t, () async => null);
      expect(tile(t, 'Exported saves folder').enabled, isTrue);
      expect(tile(t, 'Save Sync').enabled, isFalse);
      expect(find.text('Set up Save Sync first'), findsOneWidget);
    });

    testWidgets('a saved hub recipe without a hub stays listed, disabled', (t) async {
      SharedPreferences.setMockInitialValues({'jdkv_source': 'hub:eden'});
      await show(t, () async => null);
      expect(tile(t, 'Save Sync: eden').enabled, isFalse);
      expect(find.text('Set up Save Sync first'), findsOneWidget);
    });

    testWidgets('with a hub each folder recipe is an enabled option that becomes the source', (t) async {
      await show(t, () async => (hub: _RecipesOnlyHub(), deviceId: 'thor-7f3a'));
      expect(tile(t, 'Save Sync: Eden').enabled, isTrue);
      expect(tile(t, 'Save Sync: yuzu').enabled, isTrue);
      expect(find.text('Save Sync: Stardew Valley'), findsNothing);
      expect(find.text('Set up Save Sync first'), findsNothing);
      expect(find.text('Save exports folder'), findsOneWidget);

      await t.tap(find.text('Save Sync: Eden'));
      await t.pump();
      final container = ProviderScope.containerOf(t.element(find.byType(JdkvServerScreen)));
      expect(container.read(jdkvServerProvider).source, const JdkvSourceChoice.hub('eden'));
      // The export folder only matters for the folder source.
      expect(find.text('Save exports folder'), findsNothing);
    });
  });
}
