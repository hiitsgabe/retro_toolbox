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

  test('nation fill: read when sent, false from an older library', () {
    expect(PatcherInfo.fromJson({'game_id': 'g', 'supports_nation_fill': true}).supportsNationFill, isTrue);
    expect(PatcherInfo.fromJson({'game_id': 'g', 'supports_nation_fill': false}).supportsNationFill, isFalse);
    expect(PatcherInfo.fromJson({'game_id': 'g'}).supportsNationFill, isFalse);
  });

  test('the job carries fill_nations or blank_unused per choice, never with nationals', () {
    final fill = PatcherInfo.fromJson(
        {'game_id': 'iss-snes', 'supports_nation_fill': true, 'supports_blank_unused': true, 'supports_nationals': true});
    expect(fill.leftSlotsJob(LeftSlots.fill, blankUnused: true, nationals: true), {'fill_nations': true});
    expect(fill.leftSlotsJob(LeftSlots.clear, nationals: true), {'blank_unused': true});
    expect(fill.leftSlotsJob(LeftSlots.keep, blankUnused: true, nationals: true), isEmpty);
    // Clear is no choice where the game cannot blank a slot.
    expect(PatcherInfo.fromJson({'game_id': 'g', 'supports_nation_fill': true}).leftSlotsJob(LeftSlots.clear), isEmpty);
    // Without the fill, the Look step's switch and the nationals switch as before.
    final old = PatcherInfo.fromJson({'game_id': 'g', 'supports_blank_unused': true, 'supports_nationals': true});
    expect(old.leftSlotsJob(LeftSlots.fill), isEmpty);
    expect(old.leftSlotsJob(LeftSlots.fill, blankUnused: true, nationals: true), {'blank_unused': true, 'nationals': true});
  });

  test('club fill: read when sent, false from an older library', () {
    expect(PatcherInfo.fromJson({'game_id': 'g', 'supports_club_fill': true}).supportsClubFill, isTrue);
    expect(PatcherInfo.fromJson({'game_id': 'g'}).supportsClubFill, isFalse);
  });

  test('with the club fill, the choice is the club slots and the nations box travels on its own', () {
    final pes = PatcherInfo.fromJson({
      'game_id': 'pes2013-ps2',
      'supports_club_fill': true,
      'supports_nation_fill': true,
      'supports_blank_unused': true,
      'supports_nationals': true
    });
    expect(pes.leftSlotsJob(LeftSlots.fill, fillNations: true), {'fill_clubs': true, 'fill_nations': true});
    expect(pes.leftSlotsJob(LeftSlots.fill), {'fill_clubs': true});
    // Clearing beside the nation fill empties the club slots only.
    expect(pes.leftSlotsJob(LeftSlots.clear, fillNations: true), {'blank_unused': 'clubs', 'fill_nations': true});
    expect(pes.leftSlotsJob(LeftSlots.clear), {'blank_unused': true});
    expect(pes.leftSlotsJob(LeftSlots.keep, fillNations: true, blankUnused: true, nationals: true), {'fill_nations': true});
    expect(pes.leftSlotsJob(LeftSlots.keep), isEmpty);
    // An older library (no club fill): fill means nations, as before; the box is ignored.
    final old = PatcherInfo.fromJson({'game_id': 'pes2013-ps2', 'supports_nation_fill': true, 'supports_blank_unused': true});
    expect(old.leftSlotsJob(LeftSlots.fill, fillNations: false), {'fill_nations': true});
    expect(old.leftSlotsJob(LeftSlots.clear, fillNations: true), {'blank_unused': true});
  });
}
