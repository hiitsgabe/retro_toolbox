import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/download_staging.dart';

void main() {
  group('sweepDownloaderTemps', () {
    late Directory dir;
    final now = DateTime(2026, 11, 16, 12);

    setUp(() => dir = Directory.systemTemp.createTempSync('staging_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    File make(String name, {required DateTime modified, int bytes = 10}) {
      final f = File(p.join(dir.path, name))..writeAsBytesSync(List.filled(bytes, 0));
      f.setLastModifiedSync(modified);
      return f;
    }

    test('deletes old staging files and reports the bytes freed', () async {
      final a = make('com.bbflight.background_downloader123', modified: now.subtract(const Duration(hours: 1)), bytes: 7);
      final b = make('com.bbflight.background_downloader-42', modified: now.subtract(const Duration(days: 3)), bytes: 5);

      final freed = await sweepDownloaderTemps([dir.path], now: now);

      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
      expect(freed, 12);
    });

    test('keeps a staging file touched within minAge', () async {
      final fresh = make('com.bbflight.background_downloader9', modified: now.subtract(const Duration(seconds: 30)));

      final freed = await sweepDownloaderTemps([dir.path], now: now);

      expect(fresh.existsSync(), isTrue);
      expect(freed, 0);
    });

    test('never touches files without the downloader prefix', () async {
      final other = make('favorites.json', modified: now.subtract(const Duration(days: 30)));
      final near = make('bbflight.background_downloader1', modified: now.subtract(const Duration(days: 30)));

      await sweepDownloaderTemps([dir.path], now: now);

      expect(other.existsSync(), isTrue);
      expect(near.existsSync(), isTrue);
    });

    test('a missing directory is skipped', () async {
      expect(await sweepDownloaderTemps([p.join(dir.path, 'nope')], now: now), 0);
    });
  });

  group('movingFraction', () {
    test('destination smaller than expected while running is the copy progress', () {
      expect(movingFraction(expectedSize: 200, destLength: 50), 0.25);
      expect(movingFraction(expectedSize: 200, destLength: 0), 0.0);
    });

    test('no destination file means still downloading', () {
      expect(movingFraction(expectedSize: 200, destLength: null), isNull);
    });

    test('a destination already at full size is not a copy in progress', () {
      expect(movingFraction(expectedSize: 200, destLength: 200), isNull);
      expect(movingFraction(expectedSize: 200, destLength: 300), isNull);
    });

    test('unknown expected size gives no fraction', () {
      expect(movingFraction(expectedSize: -1, destLength: 10), isNull);
      expect(movingFraction(expectedSize: 0, destLength: 0), isNull);
    });
  });

  test('a moving download reads as moving, not as a speed line', () {
    const game = Game(title: 't', url: 'https://x/t.zip', size: 0, consoleId: 'c');
    const state = GameState(game: game, status: GameStatus.downloading);
    expect(state.copyWith(movingToDestination: true).movingToDestination, isTrue);
    expect(state.copyWith(movingToDestination: true).copyWith(currentProgress: 0.5).movingToDestination, isTrue);
    expect(state.copyWith(movingToDestination: true).copyWith(movingToDestination: false).movingToDestination, isFalse);
  });
}
