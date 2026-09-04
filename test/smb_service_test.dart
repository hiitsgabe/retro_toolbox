import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/smb_service.dart';

void main() {
  test('smbParent walks up the /share/dir/file model', () {
    expect(smbParent('/Games/switch/rom.nsp'), '/Games/switch');
    expect(smbParent('/Games/switch'), '/Games');
    expect(smbParent('/Games'), ''); // share root → shares list
    expect(smbParent(''), ''); // already at root
  });
}
