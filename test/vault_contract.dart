import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The contract every [SecretVault] implementation must satisfy.
///
/// [build] returns an empty vault on each call; a `Future` because the
/// `shared_preferences` implementation needs `await` to be born.
void runVaultContract(String name, Future<SecretVault> Function() build) {
  group('vault contract: $name', () {
    test('reads back what it wrote', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');

      expect(await vault.read('ia/accessKey'), 'ABCDEF');
    });

    test('a never-written key reads null', () async {
      final vault = await build();

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('writing over replaces', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'old');
      await vault.write('ia/accessKey', 'new');

      expect(await vault.read('ia/accessKey'), 'new');
    });

    test('delete deletes', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.delete('ia/accessKey');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('writing empty deletes rather than storing empty', () async {
      // Absence has one representation, `null`, so callers do not have to
      // handle both `''` and `null`.
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.write('ia/accessKey', '');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('deleteWithPrefix takes only matching keys', () async {
      final vault = await build();
      await vault.write('addon:ultranx/snes', 'a');
      await vault.write('addon:ultranx/n64', 'b');
      await vault.write('addon:ultranx_2/snes', 'c');
      await vault.write('ia/accessKey', 'd');

      await vault.deleteWithPrefix('addon:ultranx/');

      expect(await vault.read('addon:ultranx/snes'), isNull);
      expect(await vault.read('addon:ultranx/n64'), isNull);
      expect(await vault.read('addon:ultranx_2/snes'), 'c');
      expect(await vault.read('ia/accessKey'), 'd');
    });

    test('deleting a missing key does not throw', () async {
      final vault = await build();

      await vault.delete('addon:never/existed');
      await vault.deleteWithPrefix('addon:never/');

      expect(await vault.read('addon:never/existed'), isNull);
    });
  });
}
