import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/rts_server_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _folders = [
  RtsFolder(path: '/home/u/psp', name: 'PSP', formats: ['.iso'], romsSubfolder: 'psp'),
  RtsFolder(path: '/home/u/snes', name: 'SNES', formats: ['.zip'], romsSubfolder: 'snes'),
];

String _emitted() => RtsServerService.buildConsolesJson(_folders, '192.168.0.10:8080');

void main() {
  test('what the RTS emits is a catalog the consumer parses', () {
    final consoles = CatalogService.parseConsoles(_emitted());

    expect(consoles.keys, containsAll(<String>['psp', 'snes']));
    expect(consoles['psp']!.urls.single, 'http://192.168.0.10:8080/f/0/');
  });

  test('the id the RTS generates equals the id the consumer computes', () {
    // Both sides are spelled out literally on purpose: asserting one derivation
    // against the same derivation passes for any implementation, even a broken one.
    final emitted = (jsonDecode(_emitted()) as List).cast<Map<String, dynamic>>();

    expect(emitted.map((c) => c['name']).toList(), <String>['PSP', 'SNES']);
    expect(CatalogService.parseConsoles(_emitted()).keys.toList(), <String>['psp', 'snes']);
  });

  test('the RTS emits no token, so harvesting leaves its output unchanged', () async {
    final vault = MemoryVault();
    final clean = await CatalogService.harvestAuthTokens(_emitted(), vault: vault, addonId: 'rts');

    expect(CatalogService.parseConsoles(clean).keys, CatalogService.parseConsoles(_emitted()).keys);
    for (final folder in _folders) {
      expect(await vault.read(SecretRef.addonToken('rts', CatalogService.consoleId(folder.name))), isNull);
    }
  });

  test('no RTS console asks for an account', () {
    for (final console in CatalogService.parseConsoles(_emitted()).values) {
      expect(authNeedsToken(console.auth), isFalse);
    }
  });

  test('the RTS catalog merges under the installer addon id', () {
    final merged = mergeCatalogs([
      (addonId: Addon.idFromUrl('http://192.168.0.10:8080/consoles.json'), consoles: CatalogService.parseConsoles(_emitted())),
    ]);

    expect(merged.sources['psp']!.single.addonId, '192_168_0_10_8080_consoles_json');
    expect(merged.sources['psp']!.single.auth, isNull);
  });
}
