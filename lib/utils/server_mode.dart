import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Headless Docker server mode. The container exports `RETRO_TOOLBOX_SERVER=1`.
/// Server names: fbi, tinfoil, fpkgi, rts, jdkv, ftp.
class ServerMode {
  static bool isServer({Map<String, String>? env, String? os}) {
    final e = env ?? Platform.environment;
    final o = os ?? Platform.operatingSystem;
    return o == 'linux' && e['RETRO_TOOLBOX_SERVER'] == '1';
  }

  /// Tests may override.
  static bool current = isServer();

  static String onKey(String server) => 'server_mode_${server}_on';

  /// Persists whether [server] should be running; no-op outside server mode.
  static Future<void> remember(String server, bool on) async {
    if (!current) return;
    await (await SharedPreferences.getInstance()).setBool(onKey(server), on);
  }

  static bool shouldRestore(SharedPreferences prefs, String server) => current && (prefs.getBool(onKey(server)) ?? false);
}
