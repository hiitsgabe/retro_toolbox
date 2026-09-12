import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Tira os quatro segredos de dentro do JSON do `app_settings` e os põe no
/// cofre.
///
/// Trabalha sobre o mapa **cru**, antes de `AppSettings.fromJson`, porque o
/// modelo descarta campo desconhecido em silêncio: rodar depois da
/// desserialização amarraria esta migração aos campos que a Grupo 2 vai tirar
/// do modelo.
///
/// Devolve o mapa limpo em vez de salvar. Quem salva é quem chama, e é lá que
/// mora o `shared_preferences`.
///
/// **Não tem flag de "já rodei".** Depois da primeira passada os campos não
/// estão mais no mapa, então a segunda é inócua sozinha. Se o salvamento
/// falhar no meio, a próxima abertura tenta de novo, e aí vale a regra de que
/// o valor já no cofre ganha do valor do arquivo.
class SecretMigration {
  final SecretVault vault;

  /// O addon a que pertencem os consoles do catálogo de hoje. Entra por
  /// parâmetro porque a constante nasce na Grupo 3 e esta Task não pode
  /// depender dela.
  final String builtinAddonId;

  const SecretMigration({required this.vault, required this.builtinAddonId});

  Future<Map<String, dynamic>> drain(Map<String, dynamic> raw) async {
    final limpo = Map<String, dynamic>.from(raw);

    await _mover(limpo, 'iaAccessKey', SecretRef.iaAccessKey);
    await _mover(limpo, 'iaSecretKey', SecretRef.iaSecretKey);
    await _mover(limpo, 'iaCookies', SecretRef.iaCookies);

    final consoles = limpo['consoleSettings'];
    if (consoles is Map) {
      final novos = <String, dynamic>{};
      for (final entrada in consoles.entries) {
        final id = entrada.key.toString();
        final valor = entrada.value;
        if (valor is! Map) {
          // Arquivo editado à mão. Deixa passar intacto: a migração roda na
          // abertura do app, e levantar aqui vira app que não abre.
          novos[id] = valor;
          continue;
        }
        // Cópia própria, e não o mapa aninhado do chamador: `Map.from` no
        // nível de cima é raso, e mexer no de dentro apagaria o token do mapa
        // de quem chamou antes de qualquer coisa ter sido salva.
        final console = Map<String, dynamic>.from(valor);
        await _mover(console, 'authToken', SecretRef.addonToken(builtinAddonId, id));
        novos[id] = console;
      }
      limpo['consoleSettings'] = novos;
    }

    return limpo;
  }

  /// Tira [campo] de [de] **sempre**, e grava no cofre só se houver o que
  /// gravar e o cofre ainda não tiver valor.
  Future<void> _mover(Map<String, dynamic> de, String campo, String chave) async {
    final valor = de.remove(campo);
    if (valor is! String || valor.isEmpty) return;
    if (await vault.read(chave) != null) return;
    await vault.write(chave, valor);
  }
}
