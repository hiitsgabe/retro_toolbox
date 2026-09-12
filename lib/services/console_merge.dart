import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';

/// Uma url de catálogo, com de qual addon ela veio e com que auth ela fala.
///
/// Existe porque `Console.auth` é um mapa só e `_fetchCatalog` passava um
/// `authToken` só para todas as urls do console (`catalog_service.dart:304` e
/// `:344`). Com dois addons servindo o mesmo console, isso mandaria o token do
/// primeiro para o servidor do segundo. A auth não pertence ao console: ela
/// pertence à url.
@immutable
class ConsoleSource {
  final String addonId;
  final String url;
  final Map<String, dynamic>? auth;

  const ConsoleSource({required this.addonId, required this.url, this.auth});
}

/// O catálogo do app: os consoles que a tela desenha e, por console, de onde
/// veio cada url.
///
/// **Invariante**, que os testes fixam e que `_fetchCatalog` usa sem conferir:
/// para todo id, `sources[id]!.map((s) => s.url)` é igual a
/// `consoles[id]!.urls`, na mesma ordem. É o que permite iterar as fontes em
/// vez das urls sem uma tabela de tradução no meio.
@immutable
class MergedCatalog {
  final Map<String, Console> consoles;
  final Map<String, List<ConsoleSource>> sources;

  const MergedCatalog({this.consoles = const {}, this.sources = const {}});

  bool get isEmpty => consoles.isEmpty;

  /// De cada addon para o que ele cobre.
  ///
  /// Percorre `sources` e não `consoles` porque é `sources` que sabe de qual
  /// addon veio cada url. Um addon que serve o mesmo console por duas urls
  /// conta uma vez.
  ///
  /// Addon que não serve console nenhum **não aparece no mapa**, e isso é o
  /// caso normal de um addon recém instalado cujo catálogo ainda não foi lido.
  /// Quem lê trata ausente como cobertura zero.
  Map<String, AddonCoverage> coverage() {
    final porAddon = <String, List<String>>{};
    final comConta = <String, List<String>>{};

    for (final entrada in sources.entries) {
      final vistos = <String>{};
      for (final fonte in entrada.value) {
        // Só a primeira fonte de cada addon neste console conta, e ela é a
        // mesma que `authForAddon` devolve. As duas concordam de propósito:
        // a tela que diz "pede conta" e a que monta o header têm que estar
        // olhando para o mesmo bloco de auth.
        if (!vistos.add(fonte.addonId)) continue;
        porAddon.putIfAbsent(fonte.addonId, () => <String>[]).add(entrada.key);
        if (authNeedsToken(fonte.auth)) {
          comConta.putIfAbsent(fonte.addonId, () => <String>[]).add(entrada.key);
        }
      }
    }

    return {
      for (final entrada in porAddon.entries)
        entrada.key: (consoles: entrada.value, authConsoles: comConta[entrada.key] ?? const <String>[]),
    };
  }
}

/// O catálogo de um addon, já parseado.
typedef AddonCatalog = ({String addonId, Map<String, Console> consoles});

/// A auth com que [addonId] fala neste console, ou `null` se ele não o serve.
///
/// Recebe a lista e não um `MergedCatalog` porque o chamador de produção é o
/// `download_provider`, que tem em mãos o retorno de
/// `CatalogService.sourcesFor(consoleId)` e nenhum catálogo fundido.
///
/// Duas ausências viram o mesmo `null`: o addon não serve este console, e o
/// addon serve e não declara auth. Quem lê faz a mesma coisa nos dois casos,
/// que é não mandar header.
Map<String, dynamic>? authForAddon(List<ConsoleSource> sources, String addonId) {
  for (final fonte in sources) {
    if (fonte.addonId == addonId) return fonte.auth;
  }
  return null;
}

/// O que um addon cobre: os consoles que ele serve, e quais deles pedem conta.
///
/// Uma estrutura só para as duas perguntas da linha da seção 9 do spec de UI:
/// o `"25 consoles"` é `consoles.length`, e o chip de conta é
/// `authConsoles.isNotEmpty`. Duas listas e não uma lista mais um contador
/// porque a tela de detalhe desenha os nomes, e a lista desenha o número.
typedef AddonCoverage = ({List<String> consoles, List<String> authConsoles});

/// Funde os catálogos na ordem em que vierem, que é a ordem de prioridade que
/// o usuário arrastou na tela de addons.
///
/// Três regras, todas decorrentes da ordem:
/// - os metadados do console (nome, regex, boxarts, formatos) são do
///   **primeiro** addon que o declarou. O segundo acrescenta url, não
///   reescreve console. Sem isso, instalar uma fonte nova mudaria em silêncio
///   como os arquivos de uma fonte antiga são parseados.
/// - as urls concatenam na ordem dos addons.
/// - url repetida entra uma vez só, da primeira vez que apareceu. Dois addons
///   apontando para o mesmo servidor não fazem o app buscar duas vezes nem
///   mostrar o jogo duplicado na grade.
MergedCatalog mergeCatalogs(List<AddonCatalog> catalogos) {
  final consoles = <String, Console>{};
  final sources = <String, List<ConsoleSource>>{};

  for (final catalogo in catalogos) {
    for (final entrada in catalogo.consoles.entries) {
      final id = entrada.key;
      final console = entrada.value;
      final fontes = sources.putIfAbsent(id, () => <ConsoleSource>[]);
      final jaTem = fontes.map((f) => f.url).toSet();
      for (final url in console.urls) {
        if (!jaTem.add(url)) continue;
        fontes.add(ConsoleSource(addonId: catalogo.addonId, url: url, auth: console.auth));
      }
      // `consoles[id] ?? console`: o primeiro que declarou manda nos
      // metadados. `withUrls` reescreve só a lista de urls, que é justamente
      // o que a fusão acumula.
      consoles[id] = (consoles[id] ?? console).withUrls([for (final f in fontes) f.url]);
    }
  }

  return MergedCatalog(consoles: consoles, sources: sources);
}
