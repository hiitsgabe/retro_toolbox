import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';

void main() {
  test('teams take the slots in the order the patcher asks, then their own index', () {
    final info = PatcherInfo.fromJson({'game_id': 'iss-deluxe-snes', 'slot_order': [19, 20, 21]});
    expect([for (var i = 0; i < 5; i++) info.slotFor(i)], [19, 20, 21, 3, 4]);
    expect(PatcherInfo.fromJson({'game_id': 'x'}).slotFor(2), 2);
  });

  test('formation capabilities: read when sent, false and empty from an older library', () {
    final i = PatcherInfo.fromJson({
      'game_id': 'g',
      'writes_formation': true,
      'formations': ['4-4-2', '4-3-3']
    });
    expect(i.writesFormation, isTrue);
    expect(i.formations, ['4-4-2', '4-3-3']);
    final old = PatcherInfo.fromJson({'game_id': 'g'});
    expect(old.writesFormation, isFalse);
    expect(old.formations, isEmpty);
  });
}
