import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';

void main() {
  test('teams take the slots in the order the patcher asks, then their own index', () {
    final info = PatcherInfo.fromJson({'game_id': 'iss-deluxe-snes', 'slot_order': [19, 20, 21]});
    expect([for (var i = 0; i < 5; i++) info.slotFor(i)], [19, 20, 21, 3, 4]);
    expect(PatcherInfo.fromJson({'game_id': 'x'}).slotFor(2), 2);
  });
}
