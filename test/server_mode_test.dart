import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
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

  group('rts restore', () {
    const portKey = 'rts_server_port_v2';

    Future<ProviderContainer> load(Map<String, Object> prefs) async {
      ServerMode.current = true;
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(rtsServerProvider);
      await pumpEventQueue();
      return c;
    }

    test('restarts on load in server mode', () async {
      final c = await load({ServerMode.onKey('rts'): true, portKey: 0});
      expect(c.read(rtsServerProvider).running, isTrue);
    });

    test('stays off without the flag', () async {
      final c = await load({portKey: 0});
      expect(c.read(rtsServerProvider).running, isFalse);
    });

    test('failed enable keeps the on flag', () async {
      final busy = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(busy.close);
      final c = await load({ServerMode.onKey('rts'): true, portKey: busy.port});
      expect(c.read(rtsServerProvider).running, isFalse);
      expect(c.read(rtsServerProvider).error, isNotNull);
      expect((await SharedPreferences.getInstance()).getBool(ServerMode.onKey('rts')), isTrue);
    });

    test('enable and disable remember the state', () async {
      final c = await load({portKey: 0});
      final n = c.read(rtsServerProvider.notifier);
      final prefs = await SharedPreferences.getInstance();
      await n.enable();
      expect(prefs.getBool(ServerMode.onKey('rts')), isTrue);
      await n.disable();
      expect(prefs.getBool(ServerMode.onKey('rts')), isFalse);
    });
  });
}
