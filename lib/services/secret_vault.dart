/// Onde moram os segredos do app: tokens de addon, credenciais do Internet
/// Archive e, na fatia 6, chaves de debrid.
///
/// É interface e não classe concreta porque a implementação depende da
/// plataforma, e numa delas ela **falha**: no Linux, o chaveiro do sistema
/// exige um Secret Service vivo no D-Bus, e num Linux de servidor não existe.
/// A escolha do usuário foi cair para texto puro avisando, em vez de
/// desabilitar o campo, então o app precisa conseguir trocar de cofre em
/// tempo de execução.
///
/// **A ausência de um segredo tem uma representação só, `null`.** Escrever
/// string vazia apaga a chave. Sem essa regra, cada chamador precisaria tratar
/// `''` e `null` como a mesma coisa, e uma hora um esqueceria.
abstract class SecretVault {
  /// O segredo, ou `null` se nunca foi escrito ou já foi apagado.
  Future<String?> read(String key);

  /// Grava. Valor vazio **apaga**, e não grava vazio.
  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Apaga tudo que começa com [prefix]. Usado quando o usuário remove um
  /// addon: as credenciais dele vão junto, e o app não sabe de antemão quais
  /// consoles daquele addon chegaram a ter login.
  Future<void> deleteWithPrefix(String prefix);
}

/// Cofre de mentira, para teste. Não persiste nada e não sai desta instância.
class MemoryVault implements SecretVault {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    _values.removeWhere((key, value) => key.startsWith(prefix));
  }
}
