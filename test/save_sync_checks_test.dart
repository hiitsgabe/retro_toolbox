import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/save_checks.dart';

void main() {
  final farm = utf8.encode('<?xml version="1.0"?><SaveGame><player/></SaveGame>\r\n');

  test('xmlEndsWith reads plain, gzip and zlib files', () {
    expect(xmlEndsWith(farm, '</SaveGame>'), isTrue);
    expect(xmlEndsWith(GZipEncoder().encodeBytes(farm), '</SaveGame>'), isTrue);
    expect(xmlEndsWith(ZLibEncoder().encodeBytes(farm), '</SaveGame>'), isTrue);
    expect(xmlEndsWith(farm.sublist(0, farm.length - 6), '</SaveGame>'), isFalse);
  });

  test('binaryFormatterEnvelope wants the header record and the end byte', () {
    final ok = [0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0x01, 0x0B];
    expect(binaryFormatterEnvelope(ok), isTrue);
    expect(binaryFormatterEnvelope(ok.sublist(0, ok.length - 1)), isFalse);
    expect(binaryFormatterEnvelope([0x01, ...ok.sublist(1)]), isFalse);
  });

  test('failedCheck names the problem', () {
    expect(failedCheck(const SaveCheck(file: 'x', xmlEndsWith: '</SaveGame>'), farm), isNull);
    expect(failedCheck(const SaveCheck(file: 'x', xmlEndsWith: '</SaveGame>'), utf8.encode('<SaveGame>')), contains('</SaveGame>'));
  });

  test('readDotnetString reads a 7-bit length prefix', () {
    expect(readDotnetString([5, ...utf8.encode('Farm1'), 9, 9]), 'Farm1');
    final long = 'x' * 200;
    expect(readDotnetString([0xC8, 0x01, ...utf8.encode(long)]), long);
    expect(readDotnetString([9, 1, 2]), isNull);
    expect(readDotnetString([]), isNull);
  });

  test('xmlTagText finds the first tag', () {
    expect(xmlTagText(utf8.encode('<Farmer><gameVersion>1.6.15</gameVersion></Farmer>'), 'gameVersion'), '1.6.15');
    expect(xmlTagText(utf8.encode('<Farmer/>'), 'gameVersion'), isNull);
  });

  test('compareVersions and versionAllows', () {
    expect(compareVersions('1.6.15', '1.6.9'), greaterThan(0));
    expect(compareVersions('1.6.15.2', '1.6.15', parts: 3), 0);
    expect(compareVersions('1.6', '1.6.0'), 0);
    expect(versionAllows(VersionRule.receiverAtLeastSave, saveVersion: '1.6.15', installed: '1.6.15.2', parts: 3), isTrue);
    expect(versionAllows(VersionRule.receiverAtLeastSave, saveVersion: '1.6.15', installed: '1.6.14.7', parts: 3), isFalse);
    expect(versionAllows(VersionRule.sameBuild, saveVersion: '3.0.60146', installed: '3.0.60146'), isTrue);
    expect(versionAllows(VersionRule.sameBuild, saveVersion: '3.0.60146', installed: '3.0.60147'), isFalse);
  });

  group('versionRefusal', () {
    Recipe recipe(Map<String, dynamic>? version) => Recipe.parse({
          'schema': 1,
          'id': 'game',
          'name': 'Game',
          'status': 'draft',
          'packages': ['com.example.game'],
          'locations': [
            {'area': 'androidData', 'root': 'files'},
          ],
          'unit': 'folder',
          'include': ['*/{folder}', '*/info'],
          'version': version,
        });
    GenMeta gen({String? packageVersion, String? gameVersion}) => GenMeta(
          gen: 'g1',
          parents: const [],
          recipe: 'game',
          unit: 'A',
          device: 'd-0000',
          deviceName: 'D',
          createdAt: DateTime.utc(2026),
          package: 'com.example.game',
          packageVersion: packageVersion,
          gameVersion: gameVersion,
          files: const {},
          payloadSha256: 'f' * 64,
        );
    final fromFile = recipe({'file': '*/info', 'xmlTag': 'v', 'parts': 3, 'rule': 'receiverAtLeastSave'});
    final fromPackage = recipe({'from': 'package', 'rule': 'sameBuild'});

    test('allows when the recipe has no version rule, or the rule passes', () {
      expect(versionRefusal(recipe(null), gen(), null), isNull);
      expect(versionRefusal(fromFile, gen(gameVersion: '1.6.15'), '1.6.15.2'), isNull);
      expect(versionRefusal(fromPackage, gen(packageVersion: '3.0.1'), '3.0.1'), isNull);
    });

    test('refuses a save from a newer game, and another build', () {
      expect(versionRefusal(fromFile, gen(gameVersion: '1.6.15'), '1.6.14.7'), contains('1.6.15'));
      expect(versionRefusal(fromPackage, gen(packageVersion: '3.0.1'), '3.0.2'), contains('3.0.1'));
    });

    test('fails closed: a gen without the version it needs, or an unreadable installed version', () {
      expect(versionRefusal(fromFile, gen(packageVersion: '1.6.15.2'), '1.6.15.2'), contains('g1 does not record its version'));
      expect(versionRefusal(fromPackage, gen(gameVersion: '1.6.15'), '1.6.15'), contains('g1 does not record its version'));
      expect(versionRefusal(fromFile, gen(gameVersion: '1.6.15'), null), contains('installed version'));
    });
  });
}
