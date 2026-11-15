import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';

void main() {
  tearDown(() => ServerMode.current = false);

  test('serverRoots: folders under /storage, sorted by label', () {
    expect(serverRoots(list: () => ['/storage/roms', '/storage/hd']), {'/storage/hd': 'hd', '/storage/roms': 'roms'});
  });

  test('serverRoots: empty or failing listing gives nothing', () {
    expect(serverRoots(list: () => []), isEmpty);
    expect(serverRoots(list: () => throw Exception('no /storage')), isEmpty);
  });

  test('storageVolumes in server mode returns the server roots', () async {
    ServerMode.current = true;
    expect(await storageVolumes(serverList: () => ['/storage/roms']), {'/storage/roms': 'roms'});
  });
}
