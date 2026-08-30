import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';

void main() {
  test('sanitizeForFat strips exFAT-illegal chars so SD writes succeed', () {
    // The colon that broke the on-device download to the exFAT SD.
    expect(Game.sanitizeForFat('Metroid Prime™ 4: Beyond.nsz'), 'Metroid Prime™ 4 Beyond.nsz');
    // All illegal chars collapse to single spaces; legal ones (™, brackets) stay.
    expect(Game.sanitizeForFat('a<>:"/\\|?*b [x].zip'), 'a b [x].zip');
    // Trailing dot/space is also FAT-illegal.
    expect(Game.sanitizeForFat('name. '), 'name');
    // Never returns empty.
    expect(Game.sanitizeForFat('???'), 'output');
  });
}
