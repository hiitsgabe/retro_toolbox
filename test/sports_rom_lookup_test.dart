import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/sports_rom_lookup.dart';
import 'package:retro_toolbox/utils/rom_search.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('rom_lookup_'));
  tearDown(() => root.deleteSync(recursive: true));

  File touch(String relative) => File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  Future<String?> find(String gameId, [List<String>? dirs]) =>
      SportsRomLookup.findLocal(dirs: dirs ?? [root.path], gameId: gameId);

  group('findLocal', () {
    test('finds Winning Eleven as a loose .bin', () async {
      touch('Winning Eleven 2002 (Japan).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan).bin');
    });

    test('prefers the .cue over its .bin, and over the archive it came from', () async {
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).zip');
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).bin');
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).cue');
      expect(p.extension((await find('we2002'))!), '.cue');
    });

    test('finds a file inside a folder named after the game', () async {
      touch('World Soccer Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename((await find('we2002'))!), 'Track 01.bin');
    });

    test('skips extra tracks when the first one is there', () async {
      touch('Winning Eleven 2002 (Japan) (Track 2).bin');
      touch('Winning Eleven 2002 (Japan) (Track 1).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan) (Track 1).bin');
    });

    test('matches a name written without spaces', () async {
      touch('PES2013.iso');
      expect(p.basename((await find('pes2013-ps2'))!), 'PES2013.iso');
    });

    test('finds PES 2013 under its long title', () async {
      touch('PES 2013 - Pro Evolution Soccer (USA) (En,Fr,Es,Pt).iso');
      expect(await find('pes2013-ps2'), isNotNull);
    });

    test('ignores extensions the patcher cannot take', () async {
      touch('NHL 07 (USA).cso');
      touch('Winning Eleven 2002 (Japan).txt');
      expect(await find('nhl07-psp'), isNull);
      expect(await find('we2002'), isNull);
    });

    test('ignores other games and missing folders', () async {
      touch('Gran Turismo 3 (USA).iso');
      expect(await find('pes2013-ps2', [root.path, p.join(root.path, 'missing')]), isNull);
    });

    test('prefers the preferred region among equal matches', () async {
      touch('NHL 07 (Europe).iso');
      touch('NHL 07 (USA).iso');
      expect(p.basename((await find('nhl07-psp'))!), 'NHL 07 (USA).iso');
    });

    test('picks the data track when tracks are numbered with two digits', () async {
      touch('Winning Eleven 2002 (Japan) (Track 02).bin');
      touch('Winning Eleven 2002 (Japan) (Track 01).bin');
      touch('Winning Eleven 2002 (Japan) (Track 10).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan) (Track 01).bin');
    });

    test('picks the data track among bare track names in a game folder', () async {
      touch('Winning Eleven 2002 (Japan)/Track 03.bin');
      touch('Winning Eleven 2002 (Japan)/Track 02.bin');
      touch('Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename((await find('we2002'))!), 'Track 01.bin');
    });

    group('in the general download folder', () {
      // root is the general folder; each console keeps its own folder inside.
      String dir(String name) => p.join(root.path, name);
      Future<String?> findPsp() => SportsRomLookup.findLocal(
          dirs: [dir('psp')], looseDirs: [root.path], gameId: 'nhl07-psp', skip: [dir('psp'), dir('ps2')]);

      test("does not offer another console's copy of the game", () async {
        touch('ps2/NHL 07 (USA).iso');
        expect(await findPsp(), isNull);
        touch('psp/NHL 07 (Europe).iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL 07 (Europe).iso'));
      });

      test('still finds loose files and extracted game folders there', () async {
        touch('NHL 07 (USA)/NHL 07 (USA).iso');
        expect(p.basename((await findPsp())!), 'NHL 07 (USA).iso');
      });

      test("ranks the console's own folder ahead of it", () async {
        touch('NHL 07 (USA).iso');
        touch('psp/NHL 07 (Europe).iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL 07 (Europe).iso'));
      });

      test("ranks the console's own folder ahead even of a closer name there", () async {
        touch('NHL 07 (USA).iso'); // maybe the PS2 disc, dropped loose
        touch('psp/NHL07.iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL07.iso'));
      });

      test("does not go into another system's folder it does not know", () async {
        touch('ps2 (old)/NHL 07 (USA).iso');
        touch('megadrive/NHL 07.zip');
        expect(await findPsp(), isNull);
      });
    });
  });

  group('extractedFor', () {
    test('finds the image next to the downloaded archive', () {
      touch('Winning Eleven 2002 (Japan).zip');
      touch('Winning Eleven 2002 (Japan).cue');
      final found = SportsRomLookup.extractedFor(
          dir: root.path, archiveName: 'Winning Eleven 2002 (Japan).zip', gameId: 'we2002');
      expect(p.extension(found!), '.cue');
    });

    test('finds the image in the folder the archive was extracted to', () {
      touch('Pro Evolution Soccer 2013 (USA)/Pro Evolution Soccer 2013 (USA).iso');
      final found = SportsRomLookup.extractedFor(
          dir: root.path, archiveName: 'Pro Evolution Soccer 2013 (USA).zip', gameId: 'pes2013-ps2');
      expect(p.basename(found!), 'Pro Evolution Soccer 2013 (USA).iso');
    });

    test('picks the data track among bare track names', () {
      touch('Winning Eleven 2002 (Japan)/Track 02.bin');
      touch('Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename(SportsRomLookup.extractedFor(dir: root.path, archiveName: 'Winning Eleven 2002 (Japan).zip', gameId: 'we2002')!), 'Track 01.bin');
    });

    test('is null when nothing was extracted', () {
      touch('NHL 07 (USA).zip');
      expect(SportsRomLookup.extractedFor(dir: root.path, archiveName: 'NHL 07 (USA).zip', gameId: 'nhl07-psp'),
          isNull);
    });
  });

  test('a title without spaces still scores as a match', () {
    expect(romFuzzyScore('pes 2013', 'PES2013.iso'), greaterThanOrEqualTo(kRomMatchThreshold));
    expect(romFuzzyScore('Winning Eleven 2002', 'WinningEleven2002.bin'), greaterThanOrEqualTo(kRomMatchThreshold));
  });
}
