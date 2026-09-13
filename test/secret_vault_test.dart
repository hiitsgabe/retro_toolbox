import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'vault_contract.dart';

void main() {
  runVaultContract('MemoryVault', () async => MemoryVault());

  test('two memory vaults do not share state', () {
    final a = MemoryVault();
    final b = MemoryVault();

    return expectLater(
      a.write('ia/accessKey', 'ABCDEF').then((_) => b.read('ia/accessKey')),
      completion(isNull),
    );
  });
}
