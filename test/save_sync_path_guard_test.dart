import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';

void main() {
  final guard = PathGuard(['/storage/emulated/0/Android/data/com.chucklefish.stardewvalley', '/storage/emulated/0/RetroToolbox/SaveSync']);

  test('accepts a root and anything inside it', () {
    expect(guard.check('/storage/emulated/0/Android/data/com.chucklefish.stardewvalley'), '/storage/emulated/0/Android/data/com.chucklefish.stardewvalley');
    expect(guard.check('/storage/emulated/0/RetroToolbox/SaveSync/history/a/b.txt'), '/storage/emulated/0/RetroToolbox/SaveSync/history/a/b.txt');
  });

  test('normalises duplicate slashes and dots', () {
    expect(guard.check('/storage/emulated/0/RetroToolbox//SaveSync/./x'), '/storage/emulated/0/RetroToolbox/SaveSync/x');
  });

  test('refuses traversal, relative paths, siblings that share a prefix, newlines and backslashes', () {
    for (final bad in [
      '/storage/emulated/0/RetroToolbox/SaveSync/../../Android/data/other',
      'RetroToolbox/SaveSync/x',
      '/storage/emulated/0/Android/data/com.chucklefish.stardewvalley2/files',
      '/storage/emulated/0/RetroToolbox/SaveSync/a\nb',
      r'/storage/emulated/0/RetroToolbox/SaveSync/a\b',
      '/data/data/com.chucklefish.stardewvalley',
    ]) {
      expect(() => guard.check(bad), throwsA(isA<PathRefused>()), reason: bad);
    }
  });

  test('isSafeRelative', () {
    expect(PathGuard.isSafeRelative('Farm_1/SaveGameInfo'), isTrue);
    expect(PathGuard.isSafeRelative('Restore_Points*/**'), isTrue);
    for (final bad in ['', '/abs', 'a/../b', '..', 'a//b', './a', 'a/', r'a\b', 'a\nb']) {
      expect(PathGuard.isSafeRelative(bad), isFalse, reason: bad);
    }
  });
}
