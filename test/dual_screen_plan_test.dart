import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';

DisplayInfo d(int id, {bool isDefault = false, bool on = true}) => DisplayInfo(id: id, isDefault: isDefault, on: on);

void main() {
  // The AYN Thor: the top panel is the default display 0, the bottom is 4.
  final thor = [d(0, isDefault: true), d(4)];

  test('main on top keeps the app on the default display', () {
    final plan = planDisplays(DualScreenMode.mainOnTop, thor)!;
    expect((plan.mainDisplay, plan.companionDisplay), (0, 4));
  });

  test('main on bottom swaps the roles', () {
    final plan = planDisplays(DualScreenMode.mainOnBottom, thor)!;
    expect((plan.mainDisplay, plan.companionDisplay), (4, 0));
  });

  test('off plans nothing', () {
    expect(planDisplays(DualScreenMode.off, thor), isNull);
  });

  test('a second display that is off plans nothing', () {
    expect(planDisplays(DualScreenMode.mainOnTop, [d(0, isDefault: true), d(4, on: false)]), isNull);
    expect(planDisplays(DualScreenMode.mainOnBottom, [d(0, isDefault: true)]), isNull);
  });

  test('with three displays the companion takes the lowest other id', () {
    final plan = planDisplays(DualScreenMode.mainOnTop, [d(7), d(0, isDefault: true), d(3, on: false), d(5)])!;
    expect((plan.mainDisplay, plan.companionDisplay), (0, 5));
  });

  test('without a default display on, the lowest id is the top', () {
    final displays = [d(0, isDefault: true, on: false), d(9), d(2)];
    final top = planDisplays(DualScreenMode.mainOnTop, displays)!;
    expect((top.mainDisplay, top.companionDisplay), (2, 9));
    final bottom = planDisplays(DualScreenMode.mainOnBottom, displays)!;
    expect((bottom.mainDisplay, bottom.companionDisplay), (9, 2));
  });

  test('a display reads from the channel map', () {
    final info = DisplayInfo.fromJson(<Object?, Object?>{'id': 4, 'isDefault': false, 'on': true});
    expect((info.id, info.isDefault, info.on), (4, false, true));
  });
}
