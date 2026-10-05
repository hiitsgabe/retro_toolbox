import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/directory_service.dart';

void main() {
  test('free space of an existing folder comes from df on desktop hosts', () async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    final free = await DirectoryService.getFreeSpace(Directory.systemTemp.path);
    expect(free, greaterThan(0));
  });
}
