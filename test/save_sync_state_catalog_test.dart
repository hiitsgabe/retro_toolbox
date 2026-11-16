import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

void main() {
  test('no URL stored reads as null, and clearing goes back to null', () async {
    final s = SyncState(MemoryStore());
    expect(s.catalogUrl, isNull);
    await s.setCatalogUrl('https://example.com/r/');
    expect(s.catalogUrl, 'https://example.com/r/');
    await s.setCatalogUrl(null);
    expect(s.catalogUrl, isNull);
  });
}
