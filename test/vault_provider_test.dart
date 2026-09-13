import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

class _GoodBackend implements SecureStorageBackend {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

class _DeadBackend implements SecureStorageBackend {
  @override
  Future<String?> read(String key) async => throw StateError('no keyring');

  @override
  Future<void> write(String key, String value) async => throw StateError('no keyring');

  @override
  Future<void> delete(String key) async => throw StateError('no keyring');

  @override
  Future<Map<String, String>> readAll() async => throw StateError('no keyring');
}

void main() {
  test('live keyring: uses system vault and reports encrypted', () async {
    final choice = await chooseVault(backend: _GoodBackend(), buildFallback: () async => MemoryVault());

    expect(choice.vault, isA<SecureStorageVault>());
    expect(choice.encryptedAtRest, isTrue);
  });

  test('no keyring: falls back and reports NOT encrypted', () async {
    // Falling back without carrying `false` would let the screen announce
    // "stored securely" over plain text.
    final choice = await chooseVault(backend: _DeadBackend(), buildFallback: () async => MemoryVault());

    expect(choice.vault, isA<MemoryVault>());
    expect(choice.encryptedAtRest, isFalse);
  });

  test('live keyring: the fallback is never built', () async {
    var builds = 0;

    await chooseVault(
      backend: _GoodBackend(),
      buildFallback: () async {
        builds++;
        return MemoryVault();
      },
    );

    expect(builds, 0);
  });
}
