import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

class _BackendBom implements SecureStorageBackend {
  final Map<String, String> valores = {};

  @override
  Future<String?> read(String key) async => valores[key];

  @override
  Future<void> write(String key, String value) async {
    valores[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    valores.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(valores);
}

class _BackendMorto implements SecureStorageBackend {
  @override
  Future<String?> read(String key) async => throw StateError('sem chaveiro');

  @override
  Future<void> write(String key, String value) async => throw StateError('sem chaveiro');

  @override
  Future<void> delete(String key) async => throw StateError('sem chaveiro');

  @override
  Future<Map<String, String>> readAll() async => throw StateError('sem chaveiro');
}

void main() {
  test('com chaveiro vivo, usa o de sistema e diz que está cifrado', () async {
    final escolha = await chooseVault(backend: _BackendBom(), buildFallback: () async => MemoryVault());

    expect(escolha.vault, isA<SecureStorageVault>());
    expect(escolha.encryptedAtRest, isTrue);
  });

  test('sem chaveiro, cai para a reserva e diz que NÃO está cifrado', () async {
    // As duas afirmações são a decisão travada inteira. Cair para a reserva
    // sem carregar o `false` junto é o que transforma a fatia em maquiagem: a
    // tela anunciaria "guardado com segurança" sobre texto puro.
    final escolha = await chooseVault(backend: _BackendMorto(), buildFallback: () async => MemoryVault());

    expect(escolha.vault, isA<MemoryVault>());
    expect(escolha.encryptedAtRest, isFalse);
  });

  test('com chaveiro vivo, a reserva nem chega a ser construída', () async {
    // `PrefsVault.open()` abre o `shared_preferences`. Construir a reserva
    // sempre, para descartá-la em seguida, é trabalho de boot desperdiçado em
    // todo aparelho que tem chaveiro, que é a maioria.
    var construcoes = 0;

    await chooseVault(
      backend: _BackendBom(),
      buildFallback: () async {
        construcoes++;
        return MemoryVault();
      },
    );

    expect(construcoes, 0);
  });
}
