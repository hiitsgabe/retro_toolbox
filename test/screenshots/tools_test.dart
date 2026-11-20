import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/add_catalog_source_screen.dart';
import 'package:retro_toolbox/screens/chd_convert_screen.dart';
import 'package:retro_toolbox/screens/cia_convert_screen.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/screens/console_info_screen.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
import 'package:retro_toolbox/screens/link_download_screen.dart';
import 'package:retro_toolbox/screens/m3u_screen.dart';
import 'package:retro_toolbox/screens/nsz_decompress_screen.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/screens/sports_grid_screen.dart';
import 'package:retro_toolbox/screens/steam_shortcut_screen.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';
import 'package:retro_toolbox/services/process_list.dart';
import 'package:retro_toolbox/services/system_info.dart';

import 'support.dart';
import 'fake_picker.dart';
import 'fakes.dart';

class _FakeServer implements LinkInboxServer {
  final ctrl = StreamController<String>.broadcast();
  int? _port;
  @override
  Stream<String> get links => ctrl.stream;
  @override
  bool get running => _port != null;
  @override
  int? get port => _port;
  @override
  Future<void> start(int port) async => _port = port;
  @override
  Future<void> stop() async => _port = null;
}

class _Reader extends SystemInfoReader {
  @override
  Future<SystemSnapshot> read() async => const SystemSnapshot(
        deviceName: 'Anbernic RG35XX H',
        firmware: 'Knulli',
        osName: 'Knulli',
        osVersion: '2025.02',
        kernel: '4.9.170',
        cpuModel: 'Cortex-A53',
        cores: 4,
        hostname: 'knulli',
        mem: MemInfo(totalBytes: 1 << 30, availableBytes: 600 << 20),
        battery: BatteryInfo(percent: 87, charging: true),
        cpuTempC: 48.5,
      );
}

class _Procs extends ProcessList {
  @override
  Future<List<ProcessEntry>> list() async => const [];
}

const patcher = PatcherInfo(
  gameId: 'we2002',
  platform: 'psx',
  sport: 'soccer',
  requiresSlotMapping: true,
  providers: ['espn'],
  languages: ['en', 'es', 'fr', 'pt'],
  supportsLogos: true,
  supportsBlankUnused: true,
  imageSlots: ['title', 'menu', 'boot'],
  supportsKits: true,
  kitTemplates: true,
);

void main() {
  screenshotSetUp();
  setUp(() => PackageInfo.setMockInitialValues(appName: 'Retro Toolbox', packageName: 'name.rafaismy.retrotoolbox', version: '0.7.7', buildNumber: '77', buildSignature: ''));

  final screens = <String, Widget Function()>{
    'chd_convert': () => const ChdConvertScreen(),
    'cia_convert': () => const CiaConvertScreen(),
    'nsz_decompress': () => const NszDecompressScreen(),
    'rar_decompress': () => const RarDecompressScreen(),
    'm3u': () => const M3uScreen(),
    'collection_clean': () => const CollectionCleanScreen(),
    'steam_shortcut': () => SteamShortcutScreen(),
    'link_download': () => LinkDownloadScreen(server: _FakeServer(), addresses: () async => ['192.168.1.42']),
    'file_explorer': () => FileExplorerScreen(initialPath: supportDir.path),
    'add_catalog_source': () => const AddCatalogSourceScreen(),
    'console_info': () => ConsoleInfoScreen(
          reader: _Reader(),
          processes: _Procs(),
          mounts: () async => [(label: 'Internal', mount: '/', total: 8 << 30, free: 2 << 30), (label: 'SD card', mount: '/userdata', total: 128 << 30, free: 40 << 30)],
          addresses: () async => ['192.168.1.20'],
          ssid: () async => 'HomeWiFi',
        ),
    'sports_grid': () => const SportsGridScreen(),
    'sport_patcher_wizard': () => SportPatcherWizardScreen(
          info: patcher,
          initialLeagues: const [League(id: 1, name: 'Brasileirao Serie A', country: 'Brazil'), League(id: 2, name: 'Premier League', country: 'England')],
        ),
  };
  final only = const String.fromEnvironment('ONLY');

  for (final MapEntry(key: name, value: build) in screens.entries) {
    if (only.isNotEmpty && !only.split(',').contains(name)) continue;
    testWidgets('tool $name', (t) async {
      await launch(t, build(), overrides: [
        patchersProvider.overrideWith((ref) async => [patcher]),
        ...consolesOverrides(),
      ]);
      if (name == 'chd_convert') await realWait(t, 4000);
      await realWait(t, 600);
      await snap(t, 'tool_$name');
    }, skip: !screenshotsEnabled);
  }

  // Filled states: a fake native picker hands back fixture paths.
  late FakePicker picker;
  setUp(() => FilePicker.platform = picker = FakePicker());

  Future<void> tapAll(WidgetTester t, String label) async {
    for (var i = find.text(label).evaluate().length - 1; i >= 0; i--) {
      await t.tap(find.text(label).at(i), warnIfMissed: false);
      await realWait(t, 400);
    }
  }

  Future<void> filled(WidgetTester t, String name, Widget screen, Future<void> Function(String root) act) async {
    final root = romFixtures();
    await launch(t, screen, overrides: consolesOverrides());
    await realWait(t, name == 'chd_convert' ? 4000 : 600);
    await withNativePicker(() => act(root));
    await realWait(t, 800);
    await snap(t, 'tool_${name}_filled');
  }

  bool want(String name) => only.isEmpty || only.split(',').contains(name);

  if (want('chd_convert')) {
    testWidgets('tool chd filled', (t) => filled(t, 'chd_convert', const ChdConvertScreen(), (root) async {
          picker.file = '$root/psx/Crash Bandicoot (USA).cue';
          picker.dir = '$root/psx';
          await tapAll(t, 'Disc image');
        }), skip: !screenshotsEnabled);
  }
  if (want('cia_convert')) {
    testWidgets('tool cia filled', (t) => filled(t, 'cia_convert', const CiaConvertScreen(), (root) async {
          picker.file = '$root/3ds/Pokemon X (USA).3ds';
          picker.dir = '$root/3ds';
          await tapAll(t, '3DS image');
        }), skip: !screenshotsEnabled);
  }
  if (want('nsz_decompress')) {
    testWidgets('tool nsz filled', (t) => filled(t, 'nsz_decompress', const NszDecompressScreen(), (root) async {
          picker.file = '$root/switch/Celeste [0100A410000E0000][v0].nsz';
          picker.dir = '$root/switch';
          await tapAll(t, 'NSZ file');
        }), skip: !screenshotsEnabled);
  }
  if (want('rar_decompress')) {
    testWidgets('tool rar filled', (t) => filled(t, 'rar_decompress', const RarDecompressScreen(), (root) async {
          picker.file = '${Directory.current.path}/test/fixtures/sample.rar';
          picker.dir = '$root/snes';
          await tapAll(t, 'Archive');
        }), skip: !screenshotsEnabled);
  }
  if (want('m3u')) {
    testWidgets('tool m3u filled', (t) => filled(t, 'm3u', const M3uScreen(), (root) async {
          picker.dir = '$root/psx';
          await tapAll(t, 'Choose folder');
          await tapAll(t, 'Scan');
        }), skip: !screenshotsEnabled);
  }
  if (want('collection_clean')) {
    testWidgets('tool collection_clean filled', (t) => filled(t, 'collection_clean', const CollectionCleanScreen(), (root) async {
          picker.dir = '$root/snes';
          await tapAll(t, 'Choose folder');
          await tapAll(t, 'Scan');
        }), skip: !screenshotsEnabled);
  }
  if (want('file_explorer')) {
    testWidgets('tool file_explorer filled', (t) => filled(t, 'file_explorer', FileExplorerScreen(initialPath: '${romFixtures()}/snes'), (root) async {}),
        skip: !screenshotsEnabled);
  }
  if (want('link_download')) {
    testWidgets('tool link_download filled', (t) async {
      final server = _FakeServer();
      await filled(t, 'link_download', LinkDownloadScreen(server: server, addresses: () async => ['192.168.1.42']), (root) async {
        server.ctrl.add('https://example.invalid/files/Chrono%20Trigger%20(USA).zip');
      });
    }, skip: !screenshotsEnabled);
  }
}
