import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';

void main() {
  group('Addon.idFromUrl', () {
    test('o mesmo catálogo em http e https dá o mesmo id', () {
      expect(Addon.idFromUrl('http://exemplo.com/catalogo.json'), Addon.idFromUrl('https://exemplo.com/catalogo.json'));
    });

    test('barra final, query e fragmento não mudam o id', () {
      final base = Addon.idFromUrl('https://exemplo.com/catalogo/');
      expect(Addon.idFromUrl('https://exemplo.com/catalogo'), base);
      expect(Addon.idFromUrl('https://exemplo.com/catalogo?v=2'), base);
      expect(Addon.idFromUrl('https://exemplo.com/catalogo#topo'), base);
    });

    test('www. e caixa alta não mudam o id', () {
      expect(Addon.idFromUrl('https://WWW.Exemplo.COM/Catalogo'), Addon.idFromUrl('https://exemplo.com/catalogo'));
    });

    test('dois catálogos no mesmo host têm ids diferentes', () {
      expect(Addon.idFromUrl('https://exemplo.com/snes.json'), isNot(Addon.idFromUrl('https://exemplo.com/nes.json')));
    });

    test('nunca devolve o id do embutido, nem para uma url que daria nele', () {
      expect(Addon.idFromUrl('https://builtin/'), isNot(kBuiltinAddonId));
    });

    test('url sem host cai num id derivado do texto, e não vazio', () {
      expect(Addon.idFromUrl('    '), isNotEmpty);
    });
  });

  group('Addon json', () {
    test('ida e volta preserva id, nome e url', () {
      const addon = Addon(id: 'ultranx', name: 'UltraNX', url: 'https://ultranx.example/catalogo.json');
      final volta = Addon.fromJson(addon.toJson());
      expect(volta.id, addon.id);
      expect(volta.name, addon.name);
      expect(volta.url, addon.url);
    });

    test('sem nome no json, o nome vira o id', () {
      expect(Addon.fromJson({'id': 'ultranx'}).name, 'ultranx');
    });
  });

  group('lista ordenada', () {
    const a = Addon(id: 'a', name: 'A');
    const b = Addon(id: 'b', name: 'B');
    const c = Addon(id: 'c', name: 'C');

    test('upsertAddon acrescenta no fim quando o id é novo', () {
      expect(upsertAddon([a, b], c).map((x) => x.id), ['a', 'b', 'c']);
    });

    test('upsertAddon substitui SEM mudar a posição', () {
      final saida = upsertAddon([a, b, c], const Addon(id: 'b', name: 'B novo'));
      expect(saida.map((x) => x.id), ['a', 'b', 'c']);
      expect(saida[1].name, 'B novo');
    });

    test('removeAddon tira o que foi pedido e preserva a ordem do resto', () {
      expect(removeAddon([a, b, c], 'b').map((x) => x.id), ['a', 'c']);
    });

    test('removeAddon com id desconhecido não muda a lista', () {
      expect(removeAddon([a, b], 'z').map((x) => x.id), ['a', 'b']);
    });

    test('reorderAddons descendo aplica o desconto do ReorderableListView', () {
      // Arrastar o "a" para o fim: o widget entrega newIndex = 3, contando com
      // a vaga que o próprio "a" vai deixar.
      expect(reorderAddons([a, b, c], 0, 3).map((x) => x.id), ['b', 'c', 'a']);
    });

    test('reorderAddons subindo não aplica desconto nenhum', () {
      expect(reorderAddons([a, b, c], 2, 0).map((x) => x.id), ['c', 'a', 'b']);
    });

    test('reorderAddons com índice de origem fora da lista devolve a mesma lista', () {
      expect(reorderAddons([a, b], 5, 0).map((x) => x.id), ['a', 'b']);
    });

    test('upsertAddon substitui na posição 0, que é a do embutido', () {
      final saida = upsertAddon([a, b, c], const Addon(id: 'a', name: 'A novo'));
      expect(saida.map((x) => x.id), ['a', 'b', 'c']);
      expect(saida.first.name, 'A novo');
    });

    test('reorderAddons descendo para o meio desconta a vaga que o item deixou', () {
      const d = Addon(id: 'd', name: 'D');
      expect(reorderAddons([a, b, c, d], 0, 2).map((x) => x.id), ['b', 'a', 'c', 'd']);
    });
  });
}
