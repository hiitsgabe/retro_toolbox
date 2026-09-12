import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/rts_server_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _pastas = [
  RtsFolder(path: '/home/u/psp', name: 'PSP', formats: ['.iso'], romsSubfolder: 'psp'),
  RtsFolder(path: '/home/u/snes', name: 'SNES', formats: ['.zip'], romsSubfolder: 'snes'),
];

String _emitido() => RtsServerService.buildConsolesJson(_pastas, '192.168.0.10:8080');

void main() {
  test('o que o RTS emite é um catálogo que o consumidor parseia', () {
    // A ponta a ponta da seção 6.4: o produtor monta, o consumidor lê, e os
    // dois consoles chegam do outro lado.
    final consoles = CatalogService.parseConsoles(_emitido());

    expect(consoles.keys, containsAll(<String>['psp', 'snes']));
    expect(consoles['psp']!.urls.single, 'http://192.168.0.10:8080/f/0/');
  });

  test('o id que o RTS gera é o id que o consumidor calcula', () {
    // Se as duas pontas divergirem, a pasta compartilhada vira um console com
    // id que nenhuma outra fonte casa, e o MODO PACK para de reconhecer a pasta
    // local como fonte do mesmo jogo.
    //
    // As duas asserções têm um lado **literal** de propósito. A primeira versão
    // deste caso escrevia `parseConsoles(_emitido()).containsKey(consoleId(
    // pasta.name))`, e isso não prova nada: `consoleId` é `_nameToId`
    // (`catalog_service.dart`), e `parseConsoles` chaveia com `_nameToId` do
    // mesmo `name` que o produtor emitiu verbatim. Os dois lados eram a mesma
    // chamada, então a asserção era verdadeira para **qualquer** implementação
    // da regra, inclusive uma quebrada, que é o oposto do que o nome do caso
    // promete. É o mesmo vício que o último caso deste arquivo evita de
    // propósito ao escrever o id do addon por extenso.
    final emitido = (jsonDecode(_emitido()) as List).cast<Map<String, dynamic>>();

    // O produtor manda o nome **cru** da pasta, não um slug já pronto. No dia
    // em que ele mandar pronto, o consumidor deriva em cima de derivado e o id
    // muda sem ninguém ter mexido na regra de id.
    expect(emitido.map((c) => c['name']).toList(), <String>['PSP', 'SNES']);
    // E o consumidor chaveia pelo slug, escrito por extenso. Se a regra de id
    // mudar, é aqui que cai.
    expect(CatalogService.parseConsoles(_emitido()).keys.toList(), <String>['psp', 'snes']);
  });

  test('o RTS não emite token, então a colheita não muda o que ele mandou', () async {
    final vault = MemoryVault();
    final limpo = await CatalogService.harvestAuthTokens(_emitido(), vault: vault, addonId: 'rts');

    expect(CatalogService.parseConsoles(limpo).keys, CatalogService.parseConsoles(_emitido()).keys);
    // Nenhum dos dois consoles deixou segredo no cofre. `SecretVault` não tem
    // `isEmpty`, e não vai ter: um cofre que sabe listar tudo que guarda é um
    // cofre com uma porta a mais.
    for (final pasta in _pastas) {
      expect(await vault.read(SecretRef.addonToken('rts', CatalogService.consoleId(pasta.name))), isNull);
    }
  });

  test('nenhum console do RTS pede conta', () {
    // É isto que apaga o chip de "conta" da linha do RTS na tela de addons. Se
    // um dia o RTS ganhar auth, este caso cai e a Task que o ganhar tem que
    // decidir o que a tela mostra, em vez de descobrir depois.
    for (final console in CatalogService.parseConsoles(_emitido()).values) {
      expect(authNeedsToken(console.auth), isFalse);
    }
  });

  test('o catálogo do RTS entra na fusão com o addonId de quem o instalou', () {
    final fundido = mergeCatalogs([
      (addonId: Addon.idFromUrl('http://192.168.0.10:8080/consoles.json'), consoles: CatalogService.parseConsoles(_emitido())),
    ]);

    expect(fundido.sources['psp']!.single.addonId, '192_168_0_10_8080_consoles_json');
    expect(fundido.sources['psp']!.single.auth, isNull);
  });
}
