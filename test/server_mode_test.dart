import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => ServerMode.current = ServerMode.isServer());

  test('isServer only on linux with RETRO_TOOLBOX_SERVER=1', () {
    expect(ServerMode.isServer(env: {'RETRO_TOOLBOX_SERVER': '1'}, os: 'linux'), isTrue);
    expect(ServerMode.isServer(env: {'RETRO_TOOLBOX_SERVER': '1'}, os: 'macos'), isFalse);
    expect(ServerMode.isServer(env: {}, os: 'linux'), isFalse);
  });

  test('remember is a no-op outside server mode', () async {
    SharedPreferences.setMockInitialValues({});
    ServerMode.current = false;
    await ServerMode.remember('fbi', true);
    expect((await SharedPreferences.getInstance()).getBool(ServerMode.onKey('fbi')), isNull);
  });

  test('remember + shouldRestore round-trip in server mode', () async {
    SharedPreferences.setMockInitialValues({});
    ServerMode.current = true;
    await ServerMode.remember('rts', true);
    final prefs = await SharedPreferences.getInstance();
    expect(ServerMode.shouldRestore(prefs, 'rts'), isTrue);
    await ServerMode.remember('rts', false);
    expect(ServerMode.shouldRestore(prefs, 'rts'), isFalse);
    ServerMode.current = false;
    await ServerMode.remember('rts', true);
    expect(ServerMode.shouldRestore(prefs, 'rts'), isFalse); // never restores outside server mode
  });
}
