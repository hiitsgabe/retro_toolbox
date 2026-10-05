import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/directory_service.dart';

void main() {
  test('free space of an existing folder comes from df on desktop hosts', () async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    final free = await DirectoryService.getFreeSpace(Directory.systemTemp.path);
    expect(free, greaterThan(0));
  });

  test('df output that cannot be read is unknown (null), not 0', () {
    expect(DirectoryService.parseDfAvailable(''), isNull);
    expect(DirectoryService.parseDfAvailable('Filesystem 1024-blocks Used Available Capacity Mounted on\n'), isNull);
    expect(DirectoryService.parseDfAvailable('hdr\nfake 10 5\n'), isNull);
    expect(DirectoryService.parseDfAvailable('hdr\nfake 10 5 n/a 50% /\n'), isNull);
    expect(DirectoryService.parseDfAvailable('hdr\nfake 10 10 0 100% /\n'), 0);
    expect(DirectoryService.parseDfAvailable('hdr\nfake 10 5 5 50% /\n'), 5 * 1024);
  });

  test('a failing df is null from the nullable API and 0 from the int API', () async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    const missing = '/definitely/not/a/folder';
    expect(await DirectoryService.getFreeSpaceOrNull(missing), isNull);
    expect(await DirectoryService.getFreeSpace(missing), 0);
  });
}
