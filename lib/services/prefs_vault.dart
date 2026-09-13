import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The fallback vault, in `shared_preferences`, in plaintext.
///
/// Used when the system keyring is unavailable (in practice, Linux without
/// gnome-keyring or KWallet on D-Bus). It does not encrypt and does not
/// pretend to: what it buys is keeping the secret out of the `app_settings`
/// JSON, which is serialized whole and printed on the error path.
class PrefsVault implements SecretVault {
  /// Prefix of every key in this vault, so it never collides with
  /// `app_settings` and can be swept on its own.
  static const String keyPrefix = 'secret:';

  final SharedPreferences _prefs;

  PrefsVault(this._prefs);

  static Future<PrefsVault> open() async => PrefsVault(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString('$keyPrefix$key');

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _prefs.setString('$keyPrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove('$keyPrefix$key');
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final target = '$keyPrefix$prefix';
    // `toList()` before removing: `where` is lazy, so it would interleave.
    final keys = _prefs.getKeys().where((key) => key.startsWith(target)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
