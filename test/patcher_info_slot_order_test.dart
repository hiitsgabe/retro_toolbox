import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';

void main() {
  test('teams take the slots in the order the patcher asks, then their own index', () {
    final info = PatcherInfo.fromJson({'game_id': 'iss-deluxe-snes', 'slot_order': [19, 20, 21]});
    expect([for (var i = 0; i < 5; i++) info.slotFor(i)], [19, 20, 21, 3, 4]);
    expect(PatcherInfo.fromJson({'game_id': 'x'}).slotFor(2), 2);
  });

  test('a 48-team league on a 36-slot game keeps 36 teams, at slotFor(0..35)', () {
    final info = PatcherInfo.fromJson({'game_id': 'iss-deluxe-snes', 'team_slots': 36, 'slot_order': [19, 20, 21]});
    expect(info.teamSlots, 36);
    expect(info.keptTeams(48), 36);
    expect(info.keptTeams(20), 20);
    final slots = [for (var i = 0; i < info.keptTeams(48); i++) info.slotFor(i)];
    expect(slots.length, 36);
    expect(slots, [19, 20, 21, for (var i = 3; i < 36; i++) i]);
    expect(PatcherInfo.fromJson({'game_id': 'x'}).keptTeams(48), 48);
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
