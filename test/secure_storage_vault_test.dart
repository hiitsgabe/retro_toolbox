import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

import 'vault_contract.dart';

/// O plugin de verdade não existe dentro de `flutter test`: ele fala por canal
/// de plataforma. Este falso é o que torna o cofre de sistema testável.
class _BackendFalso implements SecureStorageBackend {
  _BackendFalso({this.lancaAoEscrever = false, this.engoleEscrita = false});

  /// Um Linux sem Secret Service: a escrita levanta `PlatformException`.
  final bool lancaAoEscrever;

  /// Pior que levantar: aceita a escrita e não guarda. É por isso que a sonda
  /// lê de volta em vez de só olhar se a escrita lançou.
  final bool engoleEscrita;

  final Map<String, String> valores = {};

  @override
  Future<String?> read(String key) async => valores[key];

  @override
  Future<void> write(String key, String value) async {
    if (lancaAoEscrever) throw PlatformException(code: 'Libsecret error');
    if (engoleEscrita) return;
    valores[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    valores.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(valores);
}

void main() {
  runVaultContract('SecureStorageVault', () async => SecureStorageVault(_BackendFalso()));

  group('sonda de disponibilidade', () {
    test('aprova o chaveiro que devolve o que escreveu', () async {
      expect(await probeSecureStorage(_BackendFalso()), isTrue);
    });

    test('reprova o chaveiro que levanta', () async {
      // Este é o Linux de servidor da decisão travada: sem `gnome-keyring` nem
      // KWallet no D-Bus, o plugin levanta `PlatformException`. Se a sonda
      // deixasse a exceção subir, o app quebraria no boot em vez de cair para
      // a reserva.
      expect(await probeSecureStorage(_BackendFalso(lancaAoEscrever: true)), isFalse);
    });

    test('reprova o chaveiro que engole a escrita em silêncio', () async {
      // O caso que justifica ler de volta. Se a sonda parasse em "escreveu sem
      // lançar", este backend passaria, o app anunciaria "cifrado em repouso"
      // e o token do usuário sumiria a cada reinício, sem erro nenhum.
      expect(await probeSecureStorage(_BackendFalso(engoleEscrita: true)), isFalse);
    });

    test('não deixa o canário para trás', () async {
      // A sonda roda no boot. Uma chave por boot acumulando no chaveiro do
      // sistema do usuário é lixo que o app não tem como limpar depois.
      final backend = _BackendFalso();

      await probeSecureStorage(backend);

      expect(backend.valores, isEmpty);
    });
  });
}
