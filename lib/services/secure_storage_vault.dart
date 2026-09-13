import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The slice of `flutter_secure_storage` this app uses.
///
/// An interface because the plugin talks over a platform channel, which does
/// not exist inside `flutter test`.
abstract class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// The real implementation: pure delegation, no decisions. Every decision
/// lives in [SecureStorageVault], which is tested.
class PluginSecureStorage implements SecureStorageBackend {
  final FlutterSecureStorage _storage;

  const PluginSecureStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// The OS-encrypted vault: Keychain on Apple, Keystore on Android, DPAPI on
/// Windows, libsecret on Linux.
class SecureStorageVault implements SecretVault {
  final SecureStorageBackend _backend;

  const SecureStorageVault(this._backend);

  @override
  Future<String?> read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _backend.write(key, value);
  }

  @override
  Future<void> delete(String key) => _backend.delete(key);

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final all = await _backend.readAll();
    // `toList()` before deleting: a backend that returns its live map would
    // throw `ConcurrentModificationError` mid-removal.
    for (final key in all.keys.where((key) => key.startsWith(prefix)).toList()) {
      await _backend.delete(key);
    }
  }
}

/// Writes, reads back, and deletes a canary key.
///
/// Reading back is the point: a backend that accepts the write and stores
/// nothing only shows up on the read, and would silently lose the token every
/// restart.
Future<bool> probeSecureStorage(SecureStorageBackend backend) async {
  const key = 'probe/canary';
  const value = 'ok';
  try {
    await backend.write(key, value);
    final readBack = await backend.read(key);
    await backend.delete(key);
    return readBack == value;
  } catch (_) {
    return false;
  }
}
