/// Where the app's secrets live: addon tokens, Internet Archive credentials.
///
/// An interface because the implementation is platform-dependent, and on one
/// platform it fails: Linux without a live Secret Service on D-Bus. So the app
/// must be able to swap vaults at runtime.
///
/// A missing secret has one representation, `null`. Writing an empty string
/// deletes the key.
abstract class SecretVault {
  /// The secret, or `null` if never written or already deleted.
  Future<String?> read(String key);

  /// Writes. An empty value deletes, and does not write empty.
  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Deletes everything starting with [prefix]. Used when the user removes an
  /// addon, whose credentials go with it.
  Future<void> deleteWithPrefix(String prefix);
}

/// A fake vault, for tests. Persists nothing.
class MemoryVault implements SecretVault {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    _values.removeWhere((key, value) => key.startsWith(prefix));
  }
}
