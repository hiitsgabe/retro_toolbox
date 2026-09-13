import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

import 'vault_contract.dart';

/// The real plugin talks over a platform channel, absent in `flutter test`.
/// This fake makes the system vault testable.
class _FakeBackend implements SecureStorageBackend {
  _FakeBackend({this.throwsOnWrite = false, this.swallowsWrite = false});

  /// A Linux without Secret Service: the write throws `PlatformException`.
  final bool throwsOnWrite;

  /// Worse than throwing: accepts the write and stores nothing, which is why
  /// the probe reads back instead of only checking that the write threw.
  final bool swallowsWrite;

  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (throwsOnWrite) throw PlatformException(code: 'Libsecret error');
    if (swallowsWrite) return;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

void main() {
  runVaultContract('SecureStorageVault', () async => SecureStorageVault(_FakeBackend()));

  group('availability probe', () {
    test('passes a keyring that reads back what it wrote', () async {
      expect(await probeSecureStorage(_FakeBackend()), isTrue);
    });

    test('fails a keyring that throws', () async {
      expect(await probeSecureStorage(_FakeBackend(throwsOnWrite: true)), isFalse);
    });

    test('fails a keyring that silently swallows the write', () async {
      expect(await probeSecureStorage(_FakeBackend(swallowsWrite: true)), isFalse);
    });

    test('leaves no canary behind', () async {
      final backend = _FakeBackend();

      await probeSecureStorage(backend);

      expect(backend.values, isEmpty);
    });
  });
}
