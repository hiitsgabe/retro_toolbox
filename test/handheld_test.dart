import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/handheld.dart';

void main() {
  test('handheld only on linux arm64 with the launcher flag', () {
    expect(Handheld.isLinuxHandheld(env: {'RETRO_TOOLBOX_HANDHELD': '1'}, os: 'linux', arch: 'arm64'), isTrue);
    expect(Handheld.isLinuxHandheld(env: {}, os: 'linux', arch: 'arm64'), isFalse);
    expect(Handheld.isLinuxHandheld(env: {'RETRO_TOOLBOX_HANDHELD': '1'}, os: 'linux', arch: 'x64'), isFalse);
    expect(Handheld.isLinuxHandheld(env: {'RETRO_TOOLBOX_HANDHELD': '1'}, os: 'android', arch: 'arm64'), isFalse);
  });

  test('framebuffer flag', () {
    expect(Handheld.isFramebuffer(env: {'RETRO_TOOLBOX_FBDEV': '1'}), isTrue);
    expect(Handheld.isFramebuffer(env: {}), isFalse);
  });
}
