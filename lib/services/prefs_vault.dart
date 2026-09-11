import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// O cofre de reserva, em `shared_preferences`, **em texto puro**.
///
/// Usado quando o chaveiro do sistema não está disponível, que na prática é o
/// Linux sem `gnome-keyring` nem KWallet no D-Bus. A escolha do usuário foi
/// esta em vez de desabilitar o campo de login, e quem usa este cofre aparece
/// com aviso na tela (Grupo 5).
///
/// Não cifra, e não finge cifrar. O que ele entrega em relação ao que existia
/// antes é separação: o segredo deixa de morar dentro do JSON do
/// `app_settings`, que é serializado inteiro e impresso no caminho de erro.
class PrefsVault implements SecretVault {
  /// Prefixo de todas as chaves deste cofre. Serve para não colidir com
  /// `app_settings` e para conseguir varrer só segredo.
  static const String keyPrefix = 'secret:';

  final SharedPreferences _prefs;

  PrefsVault(this._prefs);

  static Future<PrefsVault> open() async => PrefsVault(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString('$keyPrefix$key');

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _prefs.setString('$keyPrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove('$keyPrefix$key');
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final alvo = '$keyPrefix$prefix';
    // `toList()` é defesa barata, não necessidade: nesta versão do plugin,
    // `getKeys()` já devolve cópia (`Set<String>.from(_preferenceCache.keys)`,
    // `shared_preferences_legacy.dart:111`), então remover enquanto itera
    // **não** lança `ConcurrentModificationError`. Medido, tirando o `toList()`
    // e rodando. Fica porque a versão do plugin pode mudar, e porque `where`
    // é preguiçoso: sem materializar, a iteração e as remoções se intercalam,
    // e é essa intercalação que dependeria da cópia continuar existindo.
    final chaves = _prefs.getKeys().where((chave) => chave.startsWith(alvo)).toList();
    for (final chave in chaves) {
      await _prefs.remove(chave);
    }
  }
}
