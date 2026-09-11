import 'package:flutter/foundation.dart';

/// O id do addon que representa o `consoles.json` que o app já tinha.
///
/// Ele não é especial em nada que o usuário veja: aparece na lista, pode ser
/// arrastado e pode ser removido. A constante existe por uma razão só, e é de
/// segurança: o token que a Task 8 colheu foi guardado sob
/// `SecretRef.addonToken('builtin', consoleId)`, então mudar este valor deixa
/// o segredo do usuário órfão dentro do cofre.
const kBuiltinAddonId = 'builtin';

/// Uma fonte de catálogo instalada, na posição em que o usuário a pôs.
///
/// A posição na lista **é** a prioridade: ela alimenta o `sourcePriority` de
/// `planFromEntries` (`source_pick_service.dart:54`), que é o último critério
/// de desempate da seção 6 do spec de UI. Por isso a lista é uma `List` e não
/// um `Set` nem um mapa.
@immutable
class Addon {
  final String id;
  final String name;

  /// De onde o catálogo veio, quando veio de uma URL. É `null` no embutido e
  /// num catálogo importado de arquivo; nesses casos a tela de detalhe mostra
  /// a origem por extenso em vez de um endereço.
  final String? url;

  const Addon({required this.id, required this.name, this.url});

  bool get isBuiltin => id == kBuiltinAddonId;

  Addon copyWith({String? name, String? url}) => Addon(id: id, name: name ?? this.name, url: url ?? this.url);

  /// Um id estável para a URL de onde o catálogo veio.
  ///
  /// Estável de propósito: `http` e `https`, com `www.` ou sem, com query ou
  /// sem, com barra no fim ou sem, tudo cai no mesmo id. Reinstalar a mesma
  /// fonte tem que reencontrar o token que já está no cofre, e o token está
  /// guardado sob o id.
  ///
  /// **A porta entra no id, e não é normalização esquecida.** `Uri.host` a
  /// descarta, então sem isto `192.168.0.10:8080/f/0/` e `192.168.0.10:8081/f/0/`
  /// seriam o mesmo addon, dividindo chave de cofre e arquivo de catálogo. Dois
  /// servidores de LAN no mesmo aparelho é o caso comum aqui, não o exótico.
  /// Uso `hasPort` e não `port` porque `port` resolve o padrão do esquema: com
  /// ele, `http://e.com/c` daria 80 e `https://e.com/c` daria 443, e a estabilidade
  /// entre esquemas, que é a primeira promessa deste método, iria embora. O preço
  /// é que uma url que escreve `:80` à toa vira um id diferente da que não escreve.
  /// Esse erro cria um addon duplicado, que se vê na lista; o erro oposto apagaria
  /// um token em silêncio.
  static String idFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final cru = (uri == null || uri.host.isEmpty)
        ? url
        : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    final slug = _slug(cru);
    // Uma url cujo slug bata no embutido roubaria o token dele. Não é caso
    // realista; é barato de impedir e caro de descobrir depois.
    return slug == kBuiltinAddonId ? '${slug}_1' : slug;
  }

  factory Addon.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Addon(id: id, name: json['name'] as String? ?? id, url: json['url'] as String?);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (url != null) 'url': url};
}

String _slug(String texto) {
  final limpo = texto.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return limpo.isEmpty ? 'addon' : limpo;
}

/// Põe [novo] na lista. Se já existe um addon com o mesmo id, ele é
/// **substituído onde estava**: reinstalar uma fonte para corrigir a url não
/// pode rebaixá-la para o fim da fila de prioridade.
List<Addon> upsertAddon(List<Addon> lista, Addon novo) {
  final i = lista.indexWhere((a) => a.id == novo.id);
  if (i < 0) return [...lista, novo];
  final saida = [...lista];
  saida[i] = novo;
  return saida;
}

List<Addon> removeAddon(List<Addon> lista, String id) => [
      for (final a in lista)
        if (a.id != id) a,
    ];

/// Move um item, com a semântica do `ReorderableListView`: quando o item
/// desce, o `newIndex` que o widget entrega já conta com a vaga que o próprio
/// item vai deixar, então o destino real é um a menos. Quando sobe, não.
List<Addon> reorderAddons(List<Addon> lista, int from, int to) {
  if (from < 0 || from >= lista.length) return lista;
  final saida = [...lista];
  final item = saida.removeAt(from);
  final destino = to > from ? to - 1 : to;
  saida.insert(destino.clamp(0, saida.length), item);
  return saida;
}
