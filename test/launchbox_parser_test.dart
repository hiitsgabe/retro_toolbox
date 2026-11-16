import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_parser.dart';

const snes = 'Super Nintendo Entertainment System';
const genesis = 'Sega Genesis';
const lynx = 'Atari Lynx';
const kept = {snes, genesis, lynx};

// Game 2's alternate names and images come before the game itself, as the
// real file does not promise any order.
const fixture = '''<?xml version="1.0" standalone="yes"?>
<LaunchBox>
  <GameAlternateName>
    <AlternateName>Sonic 1</AlternateName>
    <DatabaseID>2</DatabaseID>
  </GameAlternateName>
  <GameAlternateName>
    <AlternateName>Sonic the Hedgehog</AlternateName>
    <DatabaseID>2</DatabaseID>
  </GameAlternateName>
  <GameImage>
    <DatabaseID>2</DatabaseID>
    <FileName>sonic-shot.png</FileName>
    <Type>Screenshot - Gameplay</Type>
    <CRC32>1</CRC32>
  </GameImage>
  <GameImage>
    <DatabaseID>2</DatabaseID>
    <FileName>sonic-box.jpg</FileName>
    <Type>Box - Front</Type>
    <Region>North America</Region>
    <CRC32>2</CRC32>
  </GameImage>
  <Game>
    <Name>Super Metroid</Name>
    <ReleaseDate>1994-03-19T00:00:00-08:00</ReleaseDate>
    <Overview>Samus returns.
She explores Zebes &amp; fights Ridley.</Overview>
    <MaxPlayers>1</MaxPlayers>
    <Cooperative>false</Cooperative>
    <DatabaseID>1</DatabaseID>
    <CommunityRating>4.5</CommunityRating>
    <Platform>Super Nintendo Entertainment System</Platform>
    <CommunityRatingCount>80</CommunityRatingCount>
    <Genres>Action; Platform</Genres>
    <Developer>Nintendo R&amp;D1</Developer>
    <Publisher>Nintendo</Publisher>
  </Game>
  <Game>
    <Name>Sonic the Hedgehog</Name>
    <ReleaseYear>1991</ReleaseYear>
    <DatabaseID>2</DatabaseID>
    <Platform>Sega Genesis</Platform>
    <Genres />
  </Game>
  <Game>
    <Name>Crash Bandicoot</Name>
    <DatabaseID>3</DatabaseID>
    <Platform>Sony Playstation</Platform>
  </Game>
  <GameAlternateName>
    <AlternateName>Metroid 3</AlternateName>
    <DatabaseID>1</DatabaseID>
  </GameAlternateName>
  <GameAlternateName>
    <AlternateName>Crash</AlternateName>
    <DatabaseID>3</DatabaseID>
  </GameAlternateName>
  <GameImage>
    <DatabaseID>1</DatabaseID>
    <FileName>metroid-logo.png</FileName>
    <Type>Clear Logo</Type>
  </GameImage>
  <GameImage>
    <DatabaseID>1</DatabaseID>
    <FileName>metroid-banner.png</FileName>
    <Type>Banner</Type>
  </GameImage>
  <GameImage>
    <DatabaseID>1</DatabaseID>
    <FileName>metroid-b.jpg</FileName>
    <Type>Box - Front</Type>
  </GameImage>
  <GameImage>
    <DatabaseID>1</DatabaseID>
    <FileName>metroid-a.jpg</FileName>
    <Type>Box - Front</Type>
  </GameImage>
  <Platform>
    <Name>Super Nintendo Entertainment System</Name>
    <Developer>Nintendo</Developer>
  </Platform>
</LaunchBox>
''';

Stream<List<int>> bytesOf(String s) => Stream.value(utf8.encode(s));

/// One line per game, so two parses compare as plain strings.
Map<String, List<String>> summary(Map<String, List<LaunchboxGame>> r) => {
  for (final e in r.entries) e.key: [for (final g in e.value) jsonEncode(g.toJson())],
};

void main() {
  test('only kept platforms appear, each requested one as a key', () async {
    final r = await parseLaunchboxXml(bytesOf(fixture), kept);
    expect(r.keys.toSet(), kept);
    expect(r[snes]!.map((g) => g.name), ['Super Metroid']);
    expect(r[genesis]!.map((g) => g.name), ['Sonic the Hedgehog']);
    expect(r[lynx], isEmpty);
  });

  test('alternate names and images attach to the right game, even when they come first', () async {
    final r = await parseLaunchboxXml(bytesOf(fixture), kept);
    final metroid = r[snes]!.single;
    final sonic = r[genesis]!.single;
    expect(metroid.alternateNames, ['Metroid 3']);
    expect(metroid.images.map((i) => i.file), ['metroid-a.jpg', 'metroid-b.jpg', 'metroid-logo.png']);
    // The alternate name equal to the game's own name is dropped.
    expect(sonic.alternateNames, ['Sonic 1']);
    expect(sonic.images.map((i) => [i.type, i.file, i.region]), [
      [LaunchboxImageType.boxFront, 'sonic-box.jpg', 'North America'],
      [LaunchboxImageType.screenshot, 'sonic-shot.png', null],
    ]);
  });

  test('fields read through, a self-closing Genres is empty', () async {
    final r = await parseLaunchboxXml(bytesOf(fixture), kept);
    final metroid = r[snes]!.single;
    final sonic = r[genesis]!.single;
    expect(metroid.id, 1);
    expect(metroid.releaseDate, 19940319);
    expect(metroid.genres, ['Action', 'Platform']);
    expect(metroid.developer, 'Nintendo R&D1');
    expect(metroid.rating, 4.5);
    expect(sonic.releaseDate, 19910000);
    expect(sonic.genres, isEmpty);
  });

  test('overview keeps its newlines and decodes &amp;', () async {
    final r = await parseLaunchboxXml(bytesOf(fixture), kept);
    expect(r[snes]!.single.overview, 'Samus returns.\nShe explores Zebes & fights Ridley.');
  });

  test('reads a Stream<Uint8List>, as File.openRead gives', () async {
    final r = await parseLaunchboxXml(Stream<Uint8List>.value(utf8.encode(fixture)), kept);
    expect(r[snes]!.single.name, 'Super Metroid');
  });

  group('input that is not a whole LaunchBox file throws FormatException', () {
    Future<void> rejects(String xml) => expectLater(parseLaunchboxXml(bytesOf(xml), kept), throwsFormatException);

    test('cut after the first game', () => rejects(fixture.substring(0, fixture.indexOf('</Game>') + '</Game>'.length)));
    test('cut inside a field', () => rejects(fixture.substring(0, fixture.indexOf('Zebes'))));
    test('not XML', () => rejects('Not a LaunchBox file, just some words.'));
    test('empty', () => rejects(''));
    test('another root element', () => rejects(fixture.replaceAll('LaunchBox>', 'Catalog>')));
  });

  group('zip', () {
    late Directory dir;
    late String zip;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('lb_parse_');
      final data = utf8.encode(fixture);
      zip = '${dir.path}/Metadata.zip';
      File(zip).writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile('Metadata.xml', data.length, data))));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('parseLaunchboxZip gives the same result and onProgress ends at 1.0', () async {
      final progress = <double>[];
      final fromZip = await parseLaunchboxZip(zip, kept, onProgress: progress.add);
      final fromXml = await parseLaunchboxXml(bytesOf(fixture), kept);
      expect(summary(fromZip), summary(fromXml));
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test('an onProgress that throws stops the parse with that exception', () async {
      await expectLater(
        parseLaunchboxZip(zip, kept, onProgress: (_) => throw const FileSystemException('cancelled')),
        throwsA(isA<FileSystemException>().having((e) => e.message, 'message', 'cancelled')),
      );
    });
  });
}
