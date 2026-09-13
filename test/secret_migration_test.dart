import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Counts writes, to prove a secret-free map never touches the vault.
class _VaultSpy extends MemoryVault {
  int writes = 0;

  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}

Map<String, dynamic> _settings({
  String? iaAccessKey,
  String? iaSecretKey,
  String? iaCookies,
  Map<String, dynamic>? consoleSettings,
}) {
  return {
    'consoleSettings': consoleSettings ?? <String, dynamic>{},
    'generalSettings': {'downloadDir': '/home/user/roms', 'autoExtract': true},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
    if (iaCookies != null) 'iaCookies': iaCookies,
    'nszDecompressEnabled': true,
  };
}

void main() {
  test('all three Internet Archive credentials go to the vault', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz'));

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(SecretRef.iaSecretKey), 'SK');
    expect(await vault.read(SecretRef.iaCookies), 'logged-in-sig=xyz');
  });

  test('each console token is keyed by addon, not just by console', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(consoleSettings: {
      'nintendo_64': {'downloadDir': '/roms/n64', 'authToken': 'tok-n64'},
      'snes': {'authToken': 'tok-snes'},
    }));

    expect(await vault.read(SecretRef.addonToken('builtin', 'nintendo_64')), 'tok-n64');
    expect(await vault.read(SecretRef.addonToken('builtin', 'snes')), 'tok-snes');
  });

  test('the returned map keeps none of the four secrets', () async {
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(
      iaAccessKey: 'AK',
      iaSecretKey: 'SK',
      iaCookies: 'logged-in-sig=xyz',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    ));

    expect(cleaned.containsKey('iaAccessKey'), isFalse);
    expect(cleaned.containsKey('iaSecretKey'), isFalse);
    expect(cleaned.containsKey('iaCookies'), isFalse);
    expect((cleaned['consoleSettings'] as Map)['snes'], isNot(contains('authToken')));
  });

  test('non-secret values stay where they were', () async {
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'downloadDir': '/roms/snes', 'authToken': 'tok-snes'},
      },
    ));

    expect(cleaned['nszDecompressEnabled'], isTrue);
    expect((cleaned['generalSettings'] as Map)['downloadDir'], '/home/user/roms');
    expect((cleaned['consoleSettings'] as Map)['snes'], containsPair('downloadDir', '/roms/snes'));
  });

  test('an already-populated vault wins over the file, but plaintext still leaves', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'new');
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(iaAccessKey: 'old'));

    expect(await vault.read(SecretRef.iaAccessKey), 'new');
    expect(cleaned.containsKey('iaAccessKey'), isFalse);
  });

  test('an empty value does not become a vault key', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(iaAccessKey: ''));

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
  });

  test('a malformed consoleSettings does not break the migration', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final cleaned = await migration.drain({
      'consoleSettings': {
        'snes': 'this should be a map',
        'n64': {'authToken': 'tok-n64'},
      },
      'nszDecompressEnabled': true,
    });

    expect(await vault.read(SecretRef.addonToken('builtin', 'n64')), 'tok-n64');
    expect((cleaned['consoleSettings'] as Map)['snes'], 'this should be a map');
  });

  test('does not mutate the map it received', () async {
    // A shallow `Map.from` is not enough: the nested `consoleSettings` is the
    // same object, so the token would vanish from the caller's map.
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');
    final original = _settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    );

    await migration.drain(original);

    expect(original['iaAccessKey'], 'AK');
    expect((original['consoleSettings'] as Map)['snes'], containsPair('authToken', 'tok-snes'));
  });

  test('a secret-free map writes nothing to the vault', () async {
    // Each write is a D-Bus round trip on Linux with a keyring; for a user who
    // never signed in, the right number is zero.
    final vault = _VaultSpy();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(consoleSettings: {
      'snes': {'downloadDir': '/roms/snes'},
    }));

    expect(vault.writes, 0);
  });
}
