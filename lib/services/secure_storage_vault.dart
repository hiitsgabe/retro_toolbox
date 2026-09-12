import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// O pedaço de `flutter_secure_storage` que este app usa.
///
/// Existe porque o plugin fala por canal de plataforma, que não existe dentro
/// de `flutter test`. Sem esta interface, o cofre de sistema seria a única
/// implementação de [SecretVault] sem teste nenhum, justo a que guarda os
/// segredos de verdade.
abstract class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// A implementação de verdade. Três linhas de delegação por método e nenhuma
/// decisão: tudo que é decisão mora no [SecureStorageVault], que é testado.
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

/// O cofre cifrado pelo sistema operacional: Keychain no Apple, Keystore no
/// Android, DPAPI no Windows, libsecret no Linux.
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
    final todas = await _backend.readAll();
    // `toList()` antes de apagar: `keys` é a visão viva do mapa devolvido, e
    // uma implementação que devolva o mapa interno em vez de cópia lançaria
    // `ConcurrentModificationError` no meio da remoção de um addon.
    for (final chave in todas.keys.where((chave) => chave.startsWith(prefix)).toList()) {
      await _backend.delete(chave);
    }
  }
}

/// Escreve, lê de volta e apaga uma chave-canário.
///
/// **Ler de volta é o ponto.** No Linux sem Secret Service o plugin levanta, e
/// isso o `try` pega; mas existe também backend que aceita a escrita e não
/// guarda nada, e esse só aparece na leitura. Um app que anuncia "cifrado em
/// repouso" por cima de um desses perde o token do usuário a cada reinício sem
/// emitir um erro sequer.
Future<bool> probeSecureStorage(SecureStorageBackend backend) async {
  const chave = 'probe/canary';
  const valor = 'ok';
  try {
    await backend.write(chave, valor);
    final volta = await backend.read(chave);
    await backend.delete(chave);
    return volta == valor;
  } catch (_) {
    // Engolir é o comportamento certo aqui, e só aqui: a sonda existe
    // justamente para transformar "levantou" em `false`. Quem chama decide o
    // que fazer, e o que ele faz é cair para a reserva.
    return false;
  }
}
