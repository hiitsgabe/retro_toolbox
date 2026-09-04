import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/collection_clean_service.dart';

void main() {
  test('normalizeName strips tags, case, and punctuation', () {
    expect(CollectionCleanService.normalizeName('Super Mario (USA) [!].nes'), 'super mario');
    expect(CollectionCleanService.normalizeName('Sonic 2 (Europe).md'), 'sonic 2');
    expect(CollectionCleanService.normalizeName('The Legend of Zelda (U) [rev A].sfc'), 'the legend of zelda');
  });

  test('cleanFileName removes bracket/paren tags, keeps case and extension', () {
    expect(CollectionCleanService.cleanFileName('Zelda (USA) [rev A].sfc'), 'Zelda.sfc');
    expect(CollectionCleanService.cleanFileName('Final Fantasy VI (J).sfc'), 'Final Fantasy VI.sfc');
  });

  test('cleanFileName returns null when nothing changes or name would empty', () {
    expect(CollectionCleanService.cleanFileName('Clean Game.zip'), isNull);
    expect(CollectionCleanService.cleanFileName('(USA).zip'), isNull);
  });

  test('isGhostFile matches junk names and resource-fork prefix', () {
    expect(CollectionCleanService.isGhostFile('.DS_Store'), true);
    expect(CollectionCleanService.isGhostFile('Thumbs.db'), true);
    expect(CollectionCleanService.isGhostFile('._SomeRom.nes'), true);
    expect(CollectionCleanService.isGhostFile('Mario.nes'), false);
  });

  test('isGhostDir matches only junk folder names', () {
    expect(CollectionCleanService.isGhostDir('__MACOSX'), true);
    expect(CollectionCleanService.isGhostDir('.AppleDouble'), true);
    expect(CollectionCleanService.isGhostDir('snes'), false);
  });

  test('pickDuplicateRemovals keeps the largest of each normalized group', () {
    final files = [
      (path: '/r/Mario (USA).nes', size: 100),
      (path: '/r/Mario (Europe).nes', size: 250),
      (path: '/r/Sonic.md', size: 50),
    ];
    final removals = CollectionCleanService.pickDuplicateRemovals(files);
    expect(removals.map((f) => f.path), ['/r/Mario (USA).nes']);
  });

  test('pickDuplicateRemovals ignores singletons', () {
    final files = [
      (path: '/r/Mario.nes', size: 100),
      (path: '/r/Sonic.md', size: 50),
    ];
    expect(CollectionCleanService.pickDuplicateRemovals(files), isEmpty);
  });

  group('disk operations on a temp folder', () {
    late Directory dir;
    final service = CollectionCleanService();

    setUp(() => dir = Directory.systemTemp.createTempSync('cc_test'));
    tearDown(() => dir.existsSync() ? dir.deleteSync(recursive: true) : null);

    File write(String name, int bytes) {
      final f = File(p.join(dir.path, name))..writeAsBytesSync(List.filled(bytes, 0));
      return f;
    }

    test('scan+applyDelete removes the smaller duplicate, keeps the largest', () {
      write('Mario (USA).nes', 10);
      final keep = write('Mario (Europe).nes', 20);
      final removals = service.scanDuplicates(dir);
      expect(service.applyDelete(dir, removals.map((r) => r.path)), 1);
      expect(File(p.join(dir.path, 'Mario (USA).nes')).existsSync(), false);
      expect(keep.existsSync(), true);
    });

    test('scan+applyRenames strips tags on disk', () {
      write('Zelda (USA) [!].sfc', 5);
      final renames = service.scanRenames(dir);
      expect(service.applyRenames(dir, renames), 1);
      expect(File(p.join(dir.path, 'Zelda.sfc')).existsSync(), true);
    });

    test('scan+applyDelete removes ghosts recursively, spares real files', () {
      write('game.nes', 5);
      File(p.join(dir.path, '.DS_Store')).writeAsStringSync('x');
      Directory(p.join(dir.path, '__MACOSX')).createSync();
      File(p.join(dir.path, '__MACOSX', 'junk')).writeAsStringSync('x');
      final ghosts = service.scanGhosts(dir);
      service.applyDelete(dir, ghosts.map((g) => g.path));
      expect(File(p.join(dir.path, '.DS_Store')).existsSync(), false);
      expect(Directory(p.join(dir.path, '__MACOSX')).existsSync(), false);
      expect(File(p.join(dir.path, 'game.nes')).existsSync(), true);
    });

    test('applyDelete refuses paths outside the base folder', () {
      final outside = write('keep.nes', 5); // in base, but we lie about base
      final otherBase = Directory.systemTemp.createTempSync('cc_other');
      expect(service.applyDelete(otherBase, [outside.path]), 0);
      expect(outside.existsSync(), true);
      otherBase.deleteSync(recursive: true);
    });
  });
}
