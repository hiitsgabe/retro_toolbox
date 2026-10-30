import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';

Console parse(Map<String, dynamic> extra) => Console.fromJson({'id': 'x', 'name': 'X', ...extra});

void main() {
  group('legacy keys', () {
    test('should_unzip maps to the zip pipeline', () {
      final c = parse({'file_format': ['.bin', '.cue'], 'should_unzip': true});
      expect(c.originalFormat, ['.zip']);
      expect(c.decompress, Decompress.unzip);
      expect(c.gameFilesFormat, ['.bin', '.cue']);
    });

    test('without unzip the formats are the original format', () {
      final c = parse({'file_format': ['.iso'], 'should_unzip': false});
      expect(c.originalFormat, ['.iso']);
      expect(c.decompress, Decompress.none);
      expect(c.gameFilesFormat, isNull);
    });

    test('unzip with download_url keeps the real extension', () {
      final c = parse({
        'file_format': ['.nsz'],
        'should_unzip': true,
        'download_url': 'https://h/<id>',
        'should_decompress_nsz': true,
      });
      expect(c.originalFormat, ['.nsz']);
      expect(c.decompress, Decompress.none);
      expect(c.additionalHandler, GameHandler.nszDecompress);
    });

    test('legacy .nsz formats keep NSZ on without the flag', () {
      // Before, every .nsz download was decompressed (global switch, default on).
      expect(parse({'file_format': ['.nsz']}).additionalHandler, GameHandler.nszDecompress);
      expect(parse({'original_format': ['.nsz']}).additionalHandler, isNull);
    });

    test('3ds flag maps to the handler', () {
      expect(parse({'convert_3ds_to_cia': true}).additionalHandler, GameHandler.cia3ds);
    });
  });

  test('new keys win over legacy', () {
    final c = parse({
      'file_format': ['.bin'],
      'should_unzip': true,
      'original_format': ['.rar'],
      'decompress': 'unrar',
      'additional_handler': 'chd_compress',
    });
    expect(c.originalFormat, ['.rar']);
    expect(c.decompress, Decompress.unrar);
    expect(c.additionalHandler, GameHandler.chdCompress);
  });

  test('missing decompress is none', () {
    expect(parse({'original_format': ['.zip']}).decompress, Decompress.none);
  });

  test('unknown ids are ignored', () {
    final c = parse({'decompress': '7z', 'additional_handler': 'foo'});
    expect(c.decompress, Decompress.none);
    expect(c.additionalHandler, isNull);
  });

  test('toJson round-trips the new keys only', () {
    final c = parse({
      'platform': 'psx',
      'original_format': ['.zip'],
      'decompress': 'unzip',
      'game_files_format': ['.bin', '.cue'],
      'additional_handler': 'chd_compress',
    });
    final json = c.toJson();
    for (final k in ['file_format', 'should_unzip', 'should_decompress_nsz', 'convert_3ds_to_cia']) {
      expect(json.containsKey(k), false, reason: k);
    }
    final back = Console.fromJson(json);
    expect(back.platform, 'psx');
    expect(back.originalFormat, ['.zip']);
    expect(back.decompress, Decompress.unzip);
    expect(back.gameFilesFormat, ['.bin', '.cue']);
    expect(back.additionalHandler, GameHandler.chdCompress);
  });

  test('applicable handlers follow the game files', () {
    expect(parse({'game_files_format': ['.bin', '.cue', '.iso']}).applicableHandlers, [GameHandler.chdCompress]);
    expect(parse({'original_format': ['.cia', '.3ds']}).applicableHandlers, [GameHandler.cia3ds]);
    expect(parse({'original_format': ['.gba']}).applicableHandlers, isEmpty);
    expect(parse({'original_format': ['.nsz'], 'additional_handler': 'nsz_decompress'}).applicableHandlers, [GameHandler.nszDecompress]);
  });

  test('Decompress.matches checks the file extension', () {
    expect(Decompress.unzip.matches('A.ZIP'), true);
    expect(Decompress.unzip.matches('a.rar'), false);
    expect(Decompress.unrar.matches('a.rar'), true);
    expect(Decompress.none.matches('a.zip'), false);
  });

  test('multi-disc inputs are each cue', () {
    final files = ['d1.cue', 'd1.bin', 'd2.cue', 'd2.bin'];
    expect(files.where(GameHandler.chdCompress.accepts), ['d1.cue', 'd2.cue']);
  });
}
