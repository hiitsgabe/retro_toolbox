import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';

PatcherInfo _p(String id, String platform) =>
    PatcherInfo(gameId: id, platform: platform, sport: 'hockey', requiresSlotMapping: false, providers: const []);

void main() {
  final all = [_p('a', 'snes'), _p('b', 'psx'), _p('c', 'psp'), _p('d', 'ps2'), _p('e', 'genesis')];

  test('handheld hides the heavy disc-image patches', () {
    expect(visiblePatchers(all, handheld: true).map((p) => p.gameId), ['a', 'c', 'e']);
  });

  test('other platforms keep every patch', () {
    expect(visiblePatchers(all, handheld: false), all);
  });
}
