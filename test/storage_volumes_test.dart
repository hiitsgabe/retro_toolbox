import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';

void main() {
  test('volumes come from app dirs and from /storage, internal first, deduplicated', () {
    final v = volumesFrom(
      appDirs: ['/storage/emulated/0/Android/data/pkg/files', '/storage/1234-ABCD/Android/data/pkg/files'],
      storageEntries: ['/storage/emulated', '/storage/self', '/storage/1234-ABCD', '/storage/5678-EF01'],
    );
    expect(v, {
      '/storage/emulated/0': 'Internal storage',
      '/storage/1234-ABCD': 'SD card (1234-ABCD)',
      '/storage/5678-EF01': 'SD card (5678-EF01)',
    });
  });

  test('a card the app dirs miss is still found in /storage, and internal is always offered', () {
    final v = volumesFrom(appDirs: const [], storageEntries: ['/storage/9999-0000']);
    expect(v.keys, ['/storage/emulated/0', '/storage/9999-0000']);
  });
}
