import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'vault_contract.dart';

void main() {
  runVaultContract('MemoryVault', () async => MemoryVault());

  test('dois cofres em memória não dividem estado', () {
    // Este é o motivo de o `MemoryVault` existir: cada teste que usa cofre
    // precisa do seu. Um `static` compartilhado aqui faria um teste enxergar
    // o segredo escrito por outro, e a suíte passaria a depender de ordem.
    final a = MemoryVault();
    final b = MemoryVault();

    return expectLater(
      a.write('ia/accessKey', 'ABCDEF').then((_) => b.read('ia/accessKey')),
      completion(isNull),
    );
  });
}
