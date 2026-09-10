# Fatia 3, Grade e modos: plano de implementação

> **Para quem executa:** SUB-SKILL OBRIGATÓRIA: use `superpowers:subagent-driven-development` (recomendado) ou `superpowers:executing-plans` para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Goal:** fazer o tile da grade representar um **jogo** em vez de um **arquivo**, quando o console tem metadata pack, sem regredir em nada o console que não tem.

**Architecture:** o app passa a ter dois modos de grade, decididos por um único predicado, "existe pack para este console". O MODO FONTE é o app de hoje, byte por byte. O MODO PACK é uma grade nova, alimentada por um tipo novo de entrada (`PackGridEntry`), que junta um `PackGame` do pacote com a lista de arquivos que o `PackMatcher` da fatia 2 casou com ele. A escolha de qual arquivo baixar sai do tile e vai para a tela de detalhe e para a folha de lote, as duas movidas pela mesma regra determinística. A seleção múltipla, a barra do rodapé e a folha de confirmação não dependem de pack nenhum e são feitas primeiro, isoladas, já melhorando o app de hoje.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod: ^2.6.1`), Material 3 com seed `#7C4DEF` e ChakraPetch, `cached_network_image` para as capas, `flutter_test` sem mockito, injeção por construtor. Nenhuma dependência nova no `pubspec.yaml`.

---

## Antes de começar: leia estas quatro coisas

1. **`docs/stremio-de-jogos-ui.md` inteiro.** Este plano implementa as seções 3, 4, 5, 6, 7 e a UI da seção 8. As seções 9 e 10 são das fatias 4 e 6 e **não** são suas. A seção 12 lista o que está fora de escopo, e ela vale: coverflow e lista continuam como estão.
2. **`docs/stremio-de-jogos-design.md`, seção 7, "Modos de grade"**, linhas 428 a 445. São dezoito linhas e elas definem a fatia inteira. Leia junto com a "Armadilha de leitura" logo abaixo neste plano, porque a seção 7 tem uma linha que engana.
3. **`docs/plano-fatia-2-identidade.md`**, ao menos a tabela de "Estrutura de arquivos". Tudo que aquela fatia entregou é insumo desta, e nada dela deve ser reimplementado.
4. **`lib/models/metadata_pack_model.dart` e `lib/models/game_match_model.dart`.** São os dois tipos que atravessam esta fatia inteira. `PackGame` é um jogo canônico com uma lista de `PackDump`; `GameMatch` é o veredito do matcher sobre um nome de arquivo.

### Comandos deste repositório

O `flutter` não está no PATH. Toda linha de comando deste plano assume:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
cd /home/exedev/Workspace/retro_toolbox
```

- Suíte inteira: `flutter test`
- Um arquivo só: `flutter test test/selection_bar_test.dart`
- Análise: `flutter analyze`

A saída do `flutter test` usa retorno de carro, então `flutter test | tail` mostra lixo. Para ver o fim:

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -20
```

**Linha de base antes desta fatia**, conferida rodando, não por relato: `flutter test` sai em `+178 -1`. A única falha é `test/rar_decompress_screen_test.dart`, no caso `renders with extract disabled until a file and folder are picked`, e é anterior à fatia 1. Não é sua, não tente consertar, e ela tem que continuar sendo a única no fim. `flutter analyze` sai com **22 findings e zero erro**. A quebra exata, porque um allowlist vago já custou uma rodada de QA na fatia 2:

| Arquivo | Regra | Quantos | Origem |
| --- | --- | --- | --- |
| `tool/verify_matcher.dart` | `avoid_print` | 11 | fatia 2, aceito |
| `tool/probe_zip_cd.dart` | `avoid_print` | 1 | fatia 2, aceito |
| `lib/widgets/settings/network_address_setting.dart` | `deprecated_member_use` | 6 | pré-existente |
| `lib/screens/fbi_server_screen.dart` | `use_build_context_synchronously` | 2 | pré-existente |
| `test/webdav_server_test.dart` | `unnecessary_non_null_assertion` | 1 | pré-existente |
| `lib/utils/rom_search.dart` | `dangling_library_doc_comments` | 1 | pré-existente |

O critério de aceitação desta fatia é **22, e nenhum finding novo em arquivo tocado por ela**. Não é "só `avoid_print` é aceitável": os dez findings de baixo já estavam lá antes da fatia 1 e não são trabalho seu.

### `pubspec.lock` vive sujo e nunca entra em commit

`git log -- pubspec.lock` para em `c637fd5`, muito antes da fatia 1, e mesmo assim `git status` mostra o arquivo modificado com 18 linhas trocadas. São downgrades de pacote transitivo (`matcher` 0.12.20 para 0.12.17, `material_color_utilities` 0.13.0 para 0.11.1, `characters` 1.4.1 para 1.4.0) que o Flutter 3.35.7 local reescreve a cada `pub get`. Não é trabalho de ninguém e volta sozinho.

Consequência prática, e ela é obrigatória: **`git add` sempre por caminho explícito**. Nunca `git add -A`, nunca `git add .`, nunca `git commit -a`. Cada comando de commit deste plano já vem com os caminhos escritos.

---

## Armadilha de leitura: o badge não é confiança

A seção 7 do spec de arquitetura desenha os dois modos assim (design:437-441):

```
                    MODO PACK           MODO FONTE
        grade = jogos do pack        grade = listagem do addon
        capa/sinopse = pack          capa = console.boxarts
        badge = match do subsist. 2  badge = sempre disponível
```

Lida ao pé da letra, a linha `badge = match do subsist. 2` parece mandar pintar a **confiança** do match no tile. **Ela não manda, e fazer isso é erro.**

O eixo daquela tabela é **disponibilidade**, não confiança. Em MODO FONTE tudo que está na listagem existe por definição, então o badge é sempre "disponível". Em MODO PACK a disponibilidade vem de o matcher ter achado alguma coisa. Ou seja:

> O badge do tile depende de `sources.isEmpty`, **nunca** de `match.confidence`. As três confianças (`confirmed`, `likely`, `guess`) dão exatamente o mesmo tile.

Isso é a CONCLUSÃO 3 e a CONCLUSÃO 7 da revisão de design (task #10), e é decisão travada da seção 2 do spec de UI, linha 32: *"Confiança de match não aparece no tile. Confiança é propriedade da fonte, e fonte só aparece no detalhe. O jogo existe, o que é incerto é uma das fontes dele."*

O motivo não é estético, é de categoria: o tile representa um **jogo**, e um jogo pode ter várias fontes com confianças diferentes, então não existe uma confiança única do tile para pintar.

Dois revisores de design independentes já propuseram um badge de incerteza no tile, e as duas vezes foi rejeitado. Se você está lendo isto e achando que um badgezinho de incerteza no tile resolveria, você é o terceiro. Não resolve.

## Segunda decisão travada: CRC não é `MatchConfidence`

`MatchConfidence` é a confiança **a priori**, derivada do tier de nome, e a fatia 2 já a produz. O resultado da verificação por CRC da seção 8 do spec de UI é **a posteriori** e é outro eixo:

| Eixo | Tipo | Valores | Quem produz |
| --- | --- | --- | --- |
| A priori | `MatchConfidence` (já existe) | `confirmed`, `likely`, `guess` | fatia 2, `game_match_model.dart` |
| A posteriori | `SourceVerification` (Task 18) | `notVerified`, `verifying`, `crcOk`, `crcDiscarded`, `impossible` | esta fatia |

Um `confirmed` já nasce com CRC batido e nunca passa por `verifying`. Um `guess` passa por `verifying` e cai em `crcOk`, `crcDiscarded` ou `impossible`.

**Se você se pegar acrescentando um valor `crcOk` ao `MatchConfidence`, pare: está errado.** É a CONCLUSÃO 6 da task #10, à qual os dois revisores chegaram de forma independente.

## Terceira decisão travada: em MODO PACK não se sintetiza `Game`

Havia duas saídas para alimentar a grade de pack: sintetizar um `Game` falso por `PackGame`, reaproveitando toda a grade de hoje, ou criar um tipo novo de entrada. **É o tipo novo.** Três razões, todas verificadas no código:

1. `gameStateProvider` é um `Provider.family<GameState, Game>` (game_state_provider.dart:14) chaveado por `game.gameId` (:16), e resolve o estado chamando `snap.getStatus(game.filename)` (:164) e `path.join(downloadDir, game.filename)` (:247). Ele é **file-keyed até o osso**. Um `Game` sintético sem arquivo real faria esse provider mentir sobre estado de download.
2. `FilteringService._matchesFilter` tem literalmente `if (metadata == null) return true;` (filtering_service.dart:59-60). Um `Game` sintético sem metadata passaria por todos os filtros de região, revisão e qualidade de dump, ou seja os chips de filtro ficariam decorativos e mentirosos.
3. `_filterLatestRevisions` (filtering_service.dart:116-147) monta a chave `'$baseTitle|$regions|$languages|$diskNumber'`, que com metadata nulo colapsa em `'$title|||'`, e a filtragem final compara por **identidade de objeto** (`latestByGameIdentity[gameIdentity] == game`). Como `Game` não tem `operator ==`, dois sintéticos de mesmo título viram um só, silenciosamente. Medido no pacote SNES real: 2415 jogos, 2415 títulos distintos, zero colisão. O risco não se materializa hoje, então este é o **terceiro** argumento e não o primeiro, mas é um alçapão que não faz sentido deixar armado.

Consequência: `game_grid_item.dart`, `game_grid.dart` e `filtering_service.dart` **não são modificados por esta fatia**. O MODO PACK ganha widgets próprios. Isso é uma divergência deliberada da tabela da seção 11 do spec de UI, que fala em "duas variantes por modo" dentro de `game_grid_item.dart`; a divergência protege o `GameCoverFlow`, que reusa `GameGridItem` e está explicitamente fora de escopo (spec de UI, seção 12).

## Quarta decisão travada: a chave de seleção em MODO PACK

A seleção já existe e é um `Set<String>` em `CatalogState` (catalog_model.dart:13), lida por `gameSelectionProvider`, um `Provider.family<bool, String>` (catalog_provider.dart:17). Todo esse encanamento serve sem modificação, **desde que a string de MODO PACK não colida com a de MODO FONTE**.

- Em MODO FONTE a chave é `Game.gameId`, que é `'$consoleId/$filename'` (game_model.dart:86).
- `consoleId` sai de `CatalogService._nameToId` (catalog_service.dart:61-63), que é `[a-z0-9_]+`.
- `PackGame.id` é `'<pack_id>/<slug>'` (`tool/build_metadata_pack.py:237`), por exemplo `snes/chrono-trigger`. **Também tem barra, e também começa com `[a-z0-9]`.** Usar `PackGame.id` cru como chave de seleção não é comprovadamente disjunto de `Game.gameId`.

Por isso a chave de MODO PACK é **`'pack:${packGame.id}'`**, com o prefixo literal. O caractere `:` não pode aparecer num `consoleId` gerado por `_nameToId`, então a colisão fica impossível pelo caminho normal.

Edge conhecido e aceito: `catalog_service.dart:95-96` aceita um `consoles.json` no formato de mapa legado e usa a chave do mapa **verbatim**, sem passar por `_nameToId`. Um `consoles.json` escrito à mão com um console de id `pack:snes` e um arquivo de nome `chrono-trigger` colidiria. Não vale código para isso; vale a linha de comentário que a Task 10 manda escrever.

## Quinta decisão travada: busca sim, chips de versão não

Em MODO PACK a grade não passa pelo `FilteringService`, porque aquele serviço opera sobre `List<Game>` e a grade de pack não tem `Game`. Então:

- **A caixa de busca continua funcionando, e continua sendo a mesma.** `SearchField` (header.dart:102-107 e :145-150) segue chamando `catalogNotifier.updateFilterText(text)` (catalog_provider.dart:223-226), que segue guardando `filterText` no `CatalogState`. O que muda é só o consumidor: em MODO PACK quem lê `filterText` é `filterPackEntries` (Task 9), Dart puro, sem isolate. São 2415 entradas e um `contains` em string minúscula; medir isso em isolate seria cerimônia sem ganho.
- **Os chips de região, revisão e qualidade de dump ficam fora da grade de pack.** Região, revisão e qualidade são propriedades de uma **versão**, e em MODO PACK a grade não tem versão, então esses filtros não têm sujeito. Filtrar a grade por "tem dump nessa região" esconderia jogos com base numa propriedade que o tile nem mostra, contrariando a premissa inteira da seção 3.1 do spec de UI ("o tile marca só a exceção", e não "o tile some").
- `filter.regions` **não morre**: ele passa a alimentar a regra de escolha de versão (Task 14), que é onde região tem sujeito. É exatamente o que a tabela da seção 11 do spec de UI prevê para `catalog_filter_model.dart`.
- Consequência de UI, e ela é obrigatória: em MODO PACK o botão de funil do header **não some**, ele muda de rótulo. A Task 19 trata disso.

---

## Estrutura de arquivos

Quinze arquivos de produção novos. **Três** arquivos de produção existentes modificados. `pubspec.yaml` não muda.

### Novos

| Arquivo | Responsabilidade | Depende de |
| --- | --- | --- |
| `lib/models/grid_entry_model.dart` | `PackGridEntry` (um `PackGame` mais as fontes casadas com ele), `MatchedSource` (uma fonte casada, com confiança e tamanho) e `kPackSelectionPrefix`. Dart puro. | `metadata_pack_model`, `game_match_model` |
| `lib/models/source_verification_model.dart` | `SourceVerification`, o eixo a posteriori do CRC. Dart puro. | nada |
| `lib/models/source_pick_model.dart` | `SourcePick`, `PickFailure` e `kBuiltinSourceId`. Dart puro. | `game_model` |
| `lib/services/source_index.dart` | Índice invertido jogo para fontes, construído uma vez por console. Dart puro. | `pack_matcher`, `game_match_model` |
| `lib/services/pack_grid_filter.dart` | Busca por texto e ordenação da grade de pack (`filterPackEntries`, Task 9), mais o recorte da seleção por modo (`entriesForSelection` e `selectionKeysFor`, Task 20). Dart puro. | `grid_entry_model`, `pack_naming` |
| `lib/services/source_pick_service.dart` | Produz `BatchPlan`. Nasce na Task 6 com o caso trivial de MODO FONTE (`planFromGames`) e ganha na Task 14 a regra da seção 6 do spec de UI: região, revisão, confiança, prioridade. Dart puro. | `game_model`, `grid_entry_model`, `source_pick_model` |
| `lib/providers/pack_grid_provider.dart` | `gridModeProvider`, `sourceIndexProvider`, `allPackEntriesProvider`, `packGridEntriesProvider`, e os dois seams de teste `packTargetProvider` e `catalogGamesProvider`. | tudo acima, `identity_provider`, `catalog_provider` |
| `lib/providers/owned_games_provider.dart` | Conjunto de ids de `PackGame` que já estão no disco. | `identity_provider`, `settings_provider` |
| `lib/services/source_verification_service.dart` | Responde "este arquivo remoto contém um dump deste jogo?" lendo o CRC por `Range`. Dart puro. | `pack_matcher`, `zip_central_directory`, `source_verification_model` |
| `lib/providers/source_verification_provider.dart` | Disparo e cache da verificação por CRC, por (fonte, arquivo). | `source_verification_service`, `identity_provider` |
| `lib/widgets/footer/selection_bar.dart` | A faixa roxa da seção 5 do spec de UI. Widget puro. | nada |
| `lib/widgets/game_grid/batch_confirm_sheet.dart` | A folha de confirmação da seção 6. Widget puro. | `source_pick_model` |
| `lib/widgets/game_grid/pack_grid_item.dart` | O tile de MODO PACK. Widget puro. | nada (recebe primitivos) |
| `lib/widgets/game_grid/pack_grid.dart` | A grade de MODO PACK, com a faixa de estado vazio da seção 3.2. | `pack_grid_item`, `pack_grid_provider` |
| `lib/screens/game_detail_screen.dart` | A tela das seções 7 e 8. | quase tudo acima |

### Modificados

| Arquivo | O que muda | Na Task |
| --- | --- | --- |
| `lib/providers/catalog_provider.dart` | ganha `clearSelection()` | 1 |
| `lib/widgets/header/header.dart` | sai o botão "Download Selected" (`:184-195`), o funil ganha rótulo por modo | 3 e 19 |
| `lib/screens/home_screen.dart` | entra a `SelectionBar`, a folha de lote e o roteamento de modo | 3, 6 e 19 |
| `lib/services/task_queue_service.dart` | nenhuma. **Está aqui de propósito.** Uma versão anterior desta tabela prometia um `startDownloadsFromPicks`. Ele não existe: o corpo seria `startDownloads(ref, context, picks.map((p) => p.game).toList(), consoleId)` e nada mais, porque `SourcePick` já carrega o `Game` inteiro. Apelido de uma linha não se testa e não paga o arquivo tocado | nenhuma |
| `lib/widgets/footer/footer.dart` | nenhuma. **Está aqui de propósito, para dizer que não muda.** A barra de seleção senta *acima* dele, como irmã no `Column`, e não dentro dele | nenhuma |

### Intocados, e isso é requisito

`lib/widgets/game_grid/game_grid_item.dart`, `lib/widgets/game_grid/game_grid.dart`, `lib/widgets/game_grid/game_cover_flow.dart`, `lib/services/filtering_service.dart`, `lib/widgets/game_list/` inteiro. Note o caminho do coverflow: ele mora **dentro** de `lib/widgets/game_grid/`, e não num diretório próprio, então a conferência daquele diretório é arquivo a arquivo e não de uma vez, porque a fatia cria três arquivos novos lá dentro. O MODO FONTE é o app de hoje e tem que continuar sendo. A Task 22 prova isso com `git diff --stat`.

---

## Convenção de commit desta fatia

Cada Task abaixo é dividida entre um agente de teste e um agente de produção, e por isso **cada Task traz duas mensagens de commit**, nunca uma:

- `test(<escopo>): <texto>` para o commit que só toca `test/`
- `feat(<escopo>): <mesmo texto>` para o commit que só toca `lib/`

O texto descritivo é o mesmo nos dois. Na fatia 2 a falta dessa regra gerou onze pares de commits com mensagem idêntica, e resolver "qual é qual" só deu por `git show --stat`.

**Regra de homogeneidade:** um commit toca ou só `lib/`, ou só `test/`. As duas exceções legítimas são `tool/` e `docs/`, que podem acompanhar qualquer um dos dois. Na fatia 2 o QA teve que decidir isso sozinho no commit `15520e2`; agora está escrito.

Escopos usados nesta fatia: `selecao`, `lote`, `grade`, `detalhe`, `crc`.

---

# Grupo 1: seleção e lote

Este grupo não toca em pack, matcher nem addon. Ele melhora o app de hoje sozinho e pode começar antes de qualquer outra coisa. É a "exceção útil" da seção 13 do spec de UI.

---

### Task 1: `clearSelection` no `CatalogNotifier`

**Files:**
- Modify: `lib/providers/catalog_provider.dart`
- Test: `test/catalog_selection_test.dart`

O `×` da barra do rodapé precisa limpar a seleção inteira, e esse método não existe. Hoje só há `toggleGameSelection` (`:228`), `selectGame` (`:240`) e `deselectGame` (`:246`).

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/catalog_selection_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';

void main() {
  // O CatalogNotifier escuta favoritesProvider no construtor, e o
  // FavoritesService toca disco. Sem binding isso explode antes do teste.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearSelection zera a seleção inteira', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    notifier.selectGame('snes/a.zip');
    notifier.selectGame('snes/b.zip');
    expect(container.read(catalogProvider).selectedGames, {'snes/a.zip', 'snes/b.zip'});

    notifier.clearSelection();

    expect(container.read(catalogProvider).selectedGames, isEmpty);
  });

  test('clearSelection não emite estado quando a seleção já está vazia', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    var emissions = 0;
    container.listen(catalogProvider, (_, __) => emissions++);

    notifier.clearSelection();

    // A grade inteira reconstrói a cada emissão do catalogProvider. Limpar
    // uma seleção que já está vazia não pode custar isso.
    expect(emissions, 0);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/catalog_selection_test.dart
```

Esperado: falha de compilação, `The method 'clearSelection' isn't defined for the type 'CatalogNotifier'`.

- [ ] **Step 3: Implemente**

Em `lib/providers/catalog_provider.dart`, logo depois de `deselectGame` (que termina na linha 250), acrescente:

```dart
  /// Limpa a seleção inteira. É o `×` da barra do rodapé.
  ///
  /// A guarda de vazio não é micro-otimização: toda a grade escuta
  /// `catalogProvider`, então emitir estado igual custa um rebuild da tela.
  void clearSelection() {
    if (state.selectedGames.isEmpty) return;
    state = state.copyWith(selectedGames: {});
  }
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/catalog_selection_test.dart
```

Esperado: `+2`, zero falha.

- [ ] **Step 5: Commit**

Duas mensagens, uma por agente:

```bash
# agente de teste
git add test/catalog_selection_test.dart
git commit -m "test(selecao): clearSelection zera a selecao sem emitir a toa"

# agente de producao
git add lib/providers/catalog_provider.dart
git commit -m "feat(selecao): clearSelection zera a selecao sem emitir a toa"
```

---

### Task 2: o widget `SelectionBar`

**Files:**
- Create: `lib/widgets/footer/selection_bar.dart`
- Test: `test/selection_bar_test.dart`

A faixa roxa da seção 5 do spec de UI. Ela senta **acima** do `Footer`, como irmã dele no `Column` do `HomeScreen`, e **não dentro** dele: `footer.dart` não é modificado por esta fatia.

Widget puro, no idioma da casa: recebe número e callbacks, não conhece Riverpod, e é testado avulso dentro de `MaterialApp`/`Scaffold` sem `ProviderScope`. O modelo é `test/menu_grid_test.dart`.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/selection_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

Widget _host({required int count, VoidCallback? onClear, VoidCallback? onDownload}) {
  return MaterialApp(
    home: Scaffold(
      body: SelectionBar(
        count: count,
        onClear: onClear ?? () {},
        onDownload: onDownload ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('não ocupa altura nenhuma quando a seleção está vazia', (tester) async {
    await tester.pumpWidget(_host(count: 0));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Baixar'), findsNothing);
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('conta no singular com um item', (tester) async {
    await tester.pumpWidget(_host(count: 1));

    expect(find.text('1 selecionado'), findsOneWidget);
  });

  testWidgets('conta no plural com mais de um item', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    expect(find.text('3 selecionados'), findsOneWidget);
  });

  testWidgets('o × chama onClear e o botão chama onDownload', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_host(
      count: 3,
      onClear: () => fired.add('clear'),
      onDownload: () => fired.add('download'),
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('Baixar'));
    await tester.pump();

    expect(fired, ['clear', 'download']);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/selection_bar_test.dart
```

Esperado: erro de compilação, `Target of URI doesn't exist: 'package:roms_downloader/widgets/footer/selection_bar.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/widgets/footer/selection_bar.dart`:

```dart
import 'package:flutter/material.dart';

/// A faixa de seleção da seção 5 do spec de UI.
///
/// Senta acima do `Footer`, como irmã dele no Column do HomeScreen, nunca
/// dentro dele: as duas ficam ativas ao mesmo tempo e nenhuma esconde a outra.
///
/// Widget puro de propósito: recebe número e callbacks e não conhece Riverpod.
/// Quem liga no provider é o HomeScreen (Task 3).
class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDownload;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    // Some sozinha quando zera. SizedBox.shrink e não Visibility, porque a
    // barra não deve reservar altura nenhuma com seleção vazia.
    if (count == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              color: scheme.onPrimary,
              tooltip: 'Limpar seleção',
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                count == 1 ? '1 selecionado' : '$count selecionados',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: onDownload,
                child: const Text('Baixar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/selection_bar_test.dart
```

Esperado: `+4`, zero falha.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/selection_bar_test.dart
git commit -m "test(selecao): barra do rodape com contador, x e botao baixar"

# agente de producao
git add lib/widgets/footer/selection_bar.dart
git commit -m "feat(selecao): barra do rodape com contador, x e botao baixar"
```

---

### Task 3: ligar a barra e tirar o botão do header

**Files:**
- Modify: `lib/screens/home_screen.dart:96`
- Modify: `lib/widgets/header/header.dart:183-196`
- Test: nenhum novo. Ver a nota de teste abaixo.

**Nota de teste, leia antes de reclamar da ausência.** `HomeScreen` depende de `appStateProvider`, que carrega o catálogo do disco e da rede no construtor, e `Header` depende de `CatalogService`. Montar essa tela num teste de widget exigiria falsificar meia dúzia de providers, e o valor disso é baixo perto do custo: o widget já está testado avulso na Task 2 e o notifier na Task 1. O que esta Task muda é fiação de três linhas. A prova dela é `flutter analyze` limpo mais a suíte inteira verde, no Step 4.

- [ ] **Step 1: Ligue a barra no `HomeScreen`**

Em `lib/screens/home_screen.dart`, acrescente o import junto dos outros de widget (depois da linha 10):

```dart
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

E troque a linha 96, que hoje é só `Footer(),`, por:

```dart
          SelectionBar(
            count: ref.watch(catalogProvider.select((s) => s.selectedGames.length)),
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () {
              final catalogState = ref.read(catalogProvider);
              final selectedGames =
                  catalogState.games.where((g) => catalogState.selectedGames.contains(g.gameId)).toList();
              TaskQueueService.startDownloads(ref, context, selectedGames, appState.selectedConsole?.id);
            },
          ),
          Footer(),
```

O `select` sobre `selectedGames.length` é de propósito: a barra só reconstrói quando o **número** muda, não a cada mexida no catálogo.

O corpo do `onDownload` é o mesmo que estava no header (`header.dart:190-191`), palavra por palavra. Na Task 5 ele passa a chamar a folha de confirmação; aqui ele só muda de lugar, para o commit ser uma coisa só.

Acrescente também o import do serviço da fila:

```dart
import 'package:roms_downloader/services/task_queue_service.dart';
```

- [ ] **Step 2: Tire o botão do header**

Em `lib/widgets/header/header.dart`, apague as linhas **183 a 195, inclusive**. Confira antes de apagar que a 183 é `      SizedBox(width: 4),`, a 184 é `      _buildActionButton(` e a **195 é `      ),`**.

> **Atenção ao intervalo.** A seção 11 e a seção 5 do spec de UI dizem `:186-194`. Está errado nas duas pontas. O bloco real é `184-195`, e há um `SizedBox(width: 4)` dos **dois** lados, na 183 e na 196. Apagar até a 194 deixa um `),` órfão e não compila; apagar 184-195 sem levar um espaçador junto deixa espaço dobrado entre o funil e o botão de modo de visualização. Por isso o intervalo a apagar é 183-195: leva o espaçador de cima junto.

Depois de apagar, `_buildActionWidgets` tem que ficar assim (linhas 175 em diante, com o funil colado no botão de modo de visualização):

```dart
    return [
      _buildActionButton(
        context: context,
        icon: catalogState.filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: catalogState.filter.isActive,
        onPressed: () => FilterModal.show(context),
        tooltip: 'Filters',
      ),
      SizedBox(width: 4),
      _buildActionButton(
```

- [ ] **Step 3: Limpe o que sobrou**

Apagar aquele bloco deixa `canDownload` e o import de `TaskQueueService` possivelmente sem uso em `header.dart`. Rode:

```bash
flutter analyze lib/widgets/header/header.dart
```

Se aparecer `unused_import` ou `unused_element`, apague o que ele apontar. Se `canDownload` ainda for usado por outro botão, deixe. **Não adivinhe: rode e obedeça ao analisador.**

- [ ] **Step 4: Prove que não quebrou nada**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Esperado: 22 findings e zero erro no analyze; `+184 -1` na suíte (178 da linha de base mais 2 da Task 1 e 4 da Task 2).

- [ ] **Step 5: Commit**

Esta Task é só produção, então tem **uma** mensagem só, e isso é a exceção, não a regra:

```bash
git add lib/screens/home_screen.dart lib/widgets/header/header.dart
git commit -m "feat(selecao): barra do rodape substitui o botao Download Selected do header"
```

---

### Task 4: `SourcePick`, `PickFailure` e `BatchPlan`

**Files:**
- Create: `lib/models/source_pick_model.dart`
- Test: `test/source_pick_model_test.dart`

O resultado da regra de lote da seção 6 do spec de UI. Ele nasce aqui, no Grupo 1, mesmo que a regra que o produz só chegue na Task 14, porque a folha de confirmação da Task 5 precisa de um tipo para desenhar e a alternativa seria desenhar sobre `Game` e reescrever tudo depois.

Em MODO FONTE cada item selecionado **já é** um arquivo, então a "escolha" é trivial e o motivo é o mesmo para todos. Em MODO PACK a Task 14 preenche `reason` e `uncertain` de verdade. O tipo é o mesmo nos dois casos, e é isso que faz a folha ser escrita uma vez só.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/source_pick_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

Game _game(String name, int size) => Game(
      title: name,
      url: 'https://exemplo/$name',
      size: size,
      consoleId: 'snes',
    );

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listagem',
      reason: 'escolhido pela sua região preferida',
      uncertain: uncertain,
      game: _game(name, size),
    );

void main() {
  test('totalBytes soma o tamanho de todas as escolhas', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 1000), _pick('b.zip', 2400)]);

    expect(plan.totalBytes, 3400);
  });

  test('totalBytes é zero num plano sem escolha', () {
    const plan = BatchPlan();

    expect(plan.totalBytes, 0);
    expect(plan.isEmpty, isTrue);
  });

  test('uncertainCount conta só as escolhas marcadas como incertas', () {
    final plan = BatchPlan(picks: [
      _pick('a.zip', 10),
      _pick('b.zip', 10, uncertain: true),
      _pick('c.zip', 10, uncertain: true),
    ]);

    expect(plan.uncertainCount, 2);
  });

  test('withoutPick tira uma escolha e preserva as falhas', () {
    final plan = BatchPlan(
      picks: [_pick('a.zip', 10), _pick('b.zip', 20)],
      failures: const [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    );

    final menor = plan.withoutPick('snes/a.zip');

    expect(menor.picks.map((p) => p.gameId), ['snes/b.zip']);
    expect(menor.failures.single.title, 'C');
    // O plano original não muda: a folha guarda o anterior para desfazer.
    expect(plan.picks.length, 2);
  });

  test('withoutPick de um id que não está no plano devolve o mesmo conteúdo', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 10)]);

    expect(plan.withoutPick('snes/nao-existe').picks.length, 1);
  });

  test('um plano só de falhas não está vazio', () {
    const plan = BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    );

    // Importa porque a folha precisa abrir para explicar por que nada vai
    // ser baixado, em vez de sumir sem dizer nada.
    expect(plan.isEmpty, isFalse);
    expect(plan.picks, isEmpty);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_pick_model_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/models/source_pick_model.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/models/source_pick_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_model.dart';

/// O id de fonte das listagens que já vêm no `consoles.json`.
///
/// Nesta fatia só existe uma fonte por console, então o valor é constante. Na
/// fatia 4 ele vira o id do addon que serviu o arquivo, e é por isso que
/// [SourcePick.sourceId] e `MatchedSource.sourceId` são campos em vez de
/// serem implícitos.
///
/// Mora neste arquivo por uma razão de ordem, não de gosto: ele é o primeiro
/// arquivo Dart puro desta fatia a existir, e tanto `source_pick_service.dart`
/// (Task 6) quanto `pack_grid_provider.dart` (Task 10) precisam da constante.
/// Pô-la no provider arrastaria Riverpod para dentro de um serviço que roda
/// fora do Flutter; pô-la em `grid_entry_model.dart` a faria nascer três
/// Tasks depois do primeiro uso.
const kBuiltinSourceId = 'listagem';

/// Uma versão escolhida para um jogo, com o motivo escrito por extenso.
///
/// O motivo é obrigatório e não é decorativo: ele é a única coisa que separa
/// "o app escolheu por você" de "o app escolheu ao acaso" (spec de UI, seção 7).
@immutable
class SourcePick {
  /// A chave de seleção do jogo. Em MODO FONTE é `Game.gameId`; em MODO PACK
  /// é `'pack:${packGame.id}'`. A folha não precisa saber qual dos dois é.
  final String gameId;
  final String title;
  final String filename;

  /// Bytes. Zero quando a fonte não declara tamanho, e nesse caso a folha
  /// mostra o total como aproximado.
  final int size;

  /// De qual fonte veio. Nesta fatia é sempre [kBuiltinSourceId] e na fatia 4
  /// é o id do addon. É o que a linha "4.0 MB, Myrient" da seção 7 mostra, e
  /// é por isso que ele nasce aqui em vez de nascer na fatia 4.
  final String sourceId;
  final String reason;

  /// Marca o selo de incerteza da seção 6. É `true` quando a confiança do
  /// match é `guess`. O lote **não** verifica CRC antes de enfileirar.
  final bool uncertain;

  /// O que efetivamente vai para a fila. A folha nunca lê este campo: ela
  /// desenha os campos de exibição acima e devolve os picks inteiros.
  final Game game;

  const SourcePick({
    required this.gameId,
    required this.title,
    required this.filename,
    required this.size,
    required this.sourceId,
    required this.reason,
    required this.game,
    this.uncertain = false,
  });
}

/// Um jogo selecionado que não vai para a fila, com o motivo.
@immutable
class PickFailure {
  final String gameId;
  final String title;
  final String reason;

  const PickFailure({
    required this.gameId,
    required this.title,
    required this.reason,
  });
}

/// O que a folha de confirmação da seção 6 desenha: o que vai e o que não vai.
@immutable
class BatchPlan {
  final List<SourcePick> picks;
  final List<PickFailure> failures;

  const BatchPlan({this.picks = const [], this.failures = const []});

  int get totalBytes => picks.fold(0, (sum, pick) => sum + pick.size);

  int get uncertainCount => picks.where((pick) => pick.uncertain).length;

  /// Vazio de verdade: nada a baixar e nada a explicar. Um plano só de
  /// falhas **não** é vazio, porque a folha precisa abrir para dizer por quê.
  bool get isEmpty => picks.isEmpty && failures.isEmpty;

  /// Tira um item do lote. Devolve um plano novo; o original não muda.
  BatchPlan withoutPick(String gameId) => BatchPlan(
        picks: picks.where((pick) => pick.gameId != gameId).toList(),
        failures: failures,
      );
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_pick_model_test.dart
```

Esperado: `+6`, zero falha.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/source_pick_model_test.dart
git commit -m "test(lote): SourcePick, PickFailure e os totais do BatchPlan"

# agente de producao
git add lib/models/source_pick_model.dart
git commit -m "feat(lote): SourcePick, PickFailure e os totais do BatchPlan"
```

---

### Task 5: a folha de confirmação de lote

**Files:**
- Create: `lib/widgets/game_grid/batch_confirm_sheet.dart`
- Test: `test/batch_confirm_sheet_test.dart`

A seção 6 do spec de UI: "40 jogos, 1.2 GB", a lista do que foi escolhido, e os que não entram aparecendo separados com o motivo.

**Escopo desta Task, e leia esta linha antes de reclamar de escopo curto.** A seção 6 fala em "override por item". Override tem dois sentidos: *tirar do lote* e *trocar a versão escolhida*. Tirar do lote é o que esta Task faz, e funciona nos dois modos. Trocar a versão só tem sujeito em MODO PACK, onde existe mais de uma versão, e chega na Task 20. Não invente um seletor de versão aqui: não há o que selecionar.

O widget é puro: recebe um `BatchPlan` e dois callbacks, e não conhece Riverpod nem `showModalBottomSheet`. Quem abre a folha é a Task 6.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/batch_confirm_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listagem',
      reason: 'escolhido pela sua região preferida',
      uncertain: uncertain,
      game: Game(title: name, url: 'https://exemplo/$name', size: size, consoleId: 'snes'),
    );

Widget _host(BatchPlan plan, {ValueChanged<BatchPlan>? onConfirm, ValueChanged<String>? onRemove}) {
  return MaterialApp(
    home: Scaffold(
      body: BatchConfirmSheet(
        plan: plan,
        onConfirm: onConfirm ?? (_) {},
        onRemove: onRemove ?? (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('mostra a contagem e o total no cabeçalho', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('a.zip', 1024 * 1024),
      _pick('b.zip', 1024 * 1024),
    ])));

    expect(find.text('2 jogos, 2.0 MB'), findsOneWidget);
  });

  testWidgets('usa singular com um jogo só', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('a.zip', 1024)])));

    expect(find.text('1 jogo, 1.0 KB'), findsOneWidget);
  });

  testWidgets('lista o nome do arquivo e o motivo de cada escolha', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('Chrono.zip', 1024)])));

    expect(find.text('Chrono.zip'), findsOneWidget);
    expect(find.text('escolhido pela sua região preferida'), findsOneWidget);
  });

  testWidgets('marca com selo só as escolhas incertas', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certo.zip', 1024),
      _pick('duvida.zip', 1024, uncertain: true),
    ])));

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('separa os que não entram na fila, com o motivo', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'Sem Fonte', reason: 'nenhum addon tem este jogo')],
    )));

    expect(find.text('Não vão para a fila'), findsOneWidget);
    expect(find.text('Sem Fonte'), findsOneWidget);
    expect(find.text('nenhum addon tem este jogo'), findsOneWidget);
  });

  testWidgets('o botão de remover devolve o gameId daquela linha', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(_host(
      BatchPlan(picks: [_pick('a.zip', 1024), _pick('b.zip', 1024)]),
      onRemove: removed.add,
    ));

    await tester.tap(find.byKey(const ValueKey('remove-snes/b.zip')));
    await tester.pump();

    expect(removed, ['snes/b.zip']);
  });

  testWidgets('confirmar devolve o plano inteiro', (tester) async {
    BatchPlan? confirmado;
    final plan = BatchPlan(picks: [_pick('a.zip', 1024)]);
    await tester.pumpWidget(_host(plan, onConfirm: (p) => confirmado = p));

    await tester.tap(find.text('Baixar'));
    await tester.pump();

    expect(confirmado, same(plan));
  });

  testWidgets('sem escolha nenhuma o botão de baixar fica desligado', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    )));

    final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Baixar'));
    expect(botao.onPressed, isNull);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/batch_confirm_sheet_test.dart
```

Esperado: `Target of URI doesn't exist: '.../batch_confirm_sheet.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/widgets/game_grid/batch_confirm_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// A folha de confirmação da seção 6 do spec de UI.
///
/// Widget puro: recebe o plano e dois callbacks. Quem abre em
/// `showModalBottomSheet` e quem enfileira é o chamador.
class BatchConfirmSheet extends StatelessWidget {
  final BatchPlan plan;
  final ValueChanged<BatchPlan> onConfirm;

  /// Recebe o `gameId` da linha a tirar do lote. O chamador é quem guarda o
  /// plano corrente e aplica `plan.withoutPick`.
  final ValueChanged<String> onRemove;

  const BatchConfirmSheet({
    super.key,
    required this.plan,
    required this.onConfirm,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = plan.picks.length;
    final cabecalho = '$n ${n == 1 ? 'jogo' : 'jogos'}, ${formatBytes(plan.totalBytes)}';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cabecalho,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (plan.uncertainCount > 0)
                  Text(
                    '${plan.uncertainCount} incerto${plan.uncertainCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pick in plan.picks)
                  ListTile(
                    dense: true,
                    // O selo de incerteza da seção 6. Ele mora AQUI e não no
                    // tile da grade: ver "Armadilha de leitura" no topo.
                    leading: pick.uncertain ? const Icon(Icons.help_outline, size: 20) : null,
                    title: Text(pick.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(pick.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      key: ValueKey('remove-${pick.gameId}'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Tirar do lote',
                      onPressed: () => onRemove(pick.gameId),
                    ),
                  ),
                if (plan.failures.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Não vão para a fila',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final falha in plan.failures)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onSurfaceVariant),
                      title: Text(falha.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(falha.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancelar'),
                ),
                const Spacer(),
                FilledButton(
                  // Sem nada escolhido não há o que enfileirar, mas a folha
                  // continua aberta para mostrar os motivos das falhas.
                  onPressed: plan.picks.isEmpty ? null : () => onConfirm(plan),
                  child: const Text('Baixar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/batch_confirm_sheet_test.dart
```

Esperado: `+8`, zero falha.

Se `2 jogos, 2.0 MB` falhar por causa do formato, confira `formatBytes` em `lib/utils/formatters.dart:6-13`: ele usa uma casa decimal por padrão e a escala 1024. **Ajuste o teste ao `formatBytes`, não o `formatBytes` ao teste**: ele já é usado em outras telas e mudá-lo é regressão fora de escopo.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/batch_confirm_sheet_test.dart
git commit -m "test(lote): folha de confirmacao com total, motivos e o que nao vai"

# agente de producao
git add lib/widgets/game_grid/batch_confirm_sheet.dart
git commit -m "feat(lote): folha de confirmacao com total, motivos e o que nao vai"
```

---

### Task 6: o lote passa pela folha antes de virar fila

**Files:**
- Create: `lib/services/source_pick_service.dart`
- Modify: `lib/screens/home_screen.dart`
- Test: `test/source_pick_service_test.dart`

A Task 3 mudou o botão de lugar e a Task 5 desenhou a folha, mas as duas ainda não se falam: apertar "Baixar" na barra enfileira tudo direto, sem confirmação. Esta Task fecha o Grupo 1.

O `BatchPlan` do MODO FONTE nasce aqui, e ele é o caso trivial: cada item selecionado **já é** um arquivo, todo arquivo da listagem existe, então nenhuma escolha é incerta e nenhuma falha é possível. Mesmo assim ele passa pela mesma função e pela mesma folha do MODO PACK, porque é isso que faz a Task 20 ser pequena.

**Por que uma função e não um `map` inline no `HomeScreen`.** Porque `HomeScreen` não se testa (ver a nota de teste da Task 3) e uma função de topo em `lib/services/` se testa. A regra de verdade chega na Task 14, no mesmo arquivo, e vai querer o mesmo lugar.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/source_pick_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

Game _game(String filename, int size) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://exemplo.org/snes/$filename',
      size: size,
      consoleId: 'snes',
    );

void main() {
  test('cada jogo selecionado vira uma escolha, na mesma ordem', () {
    final plan = planFromGames([
      _game('Chrono Trigger (USA).zip', 4 * 1024 * 1024),
      _game('Super Metroid (USA).zip', 3 * 1024 * 1024),
    ]);

    expect(plan.picks.map((p) => p.filename),
        ['Chrono Trigger (USA).zip', 'Super Metroid (USA).zip']);
    expect(plan.totalBytes, 7 * 1024 * 1024);
  });

  test('a chave e o Game inteiro viajam junto, porque é o que vai para a fila', () {
    final game = _game('Chrono Trigger (USA).zip', 1024);
    final pick = planFromGames([game]).picks.single;

    expect(pick.gameId, game.gameId);
    expect(pick.game, same(game));
    expect(pick.size, 1024);
  });

  test('em MODO FONTE nada é incerto e nada fica de fora', () {
    // A folha existe para mostrar incerteza e falha. Em MODO FONTE ela não
    // tem nenhuma das duas para mostrar, e isso é correto, não é bug: o
    // arquivo que o usuário marcou é o arquivo que ele vai receber.
    final plan = planFromGames([_game('a.zip', 1), _game('b.zip', 2)]);

    expect(plan.uncertainCount, 0);
    expect(plan.failures, isEmpty);
    expect(plan.picks.every((p) => p.reason.isNotEmpty), isTrue);
  });

  test('sem jogo nenhum o plano fica vazio de verdade', () {
    expect(planFromGames(const []).isEmpty, isTrue);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/services/source_pick_service.dart'`.

- [ ] **Step 3: Implemente a função**

Crie `lib/services/source_pick_service.dart`:

```dart
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

/// O plano de lote do MODO FONTE.
///
/// Não há escolha a fazer aqui: cada `Game` selecionado já é um arquivo, e
/// todo arquivo da listagem existe. Por isso nenhum pick é incerto e a lista
/// de falhas é sempre vazia.
///
/// A regra de verdade da seção 6 do spec de UI, com região, revisão,
/// confiança e prioridade de addon, mora em `planFromEntries` (Task 14) e só
/// tem sujeito em MODO PACK, onde existe mais de uma versão do mesmo jogo.
BatchPlan planFromGames(List<Game> games) {
  return BatchPlan(
    picks: [
      for (final game in games)
        SourcePick(
          gameId: game.gameId,
          title: game.displayTitle,
          filename: game.filename,
          size: game.size,
          sourceId: kBuiltinSourceId,
          reason: 'você escolheu este arquivo',
          game: game,
        ),
    ],
  );
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `+4`, zero falha.

- [ ] **Step 5: Ligue a folha no `HomeScreen`**

Em `lib/screens/home_screen.dart`, acrescente os imports que faltam:

```dart
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';
```

Dentro de `_HomeScreenState`, antes do `build`, escreva o método:

```dart
  /// Abre a folha da seção 6, e só enfileira o que voltar dela.
  Future<void> _confirmarLote() async {
    final catalogState = ref.read(catalogProvider);
    final selecionados =
        catalogState.games.where((g) => catalogState.selectedGames.contains(g.gameId)).toList();
    if (selecionados.isEmpty) return;

    // O plano corrente vive aqui, e não dentro da folha, porque a folha é um
    // widget puro (Task 5): ela avisa que uma linha saiu e quem guarda o
    // resultado é este método.
    var plano = planFromGames(selecionados);
    final confirmado = await showModalBottomSheet<BatchPlan>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => BatchConfirmSheet(
          plan: plano,
          onConfirm: (p) => Navigator.of(sheetContext).pop(p),
          onRemove: (gameId) => setSheetState(() => plano = plano.withoutPick(gameId)),
        ),
      ),
    );
    if (confirmado == null || !mounted) return;

    await TaskQueueService.startDownloads(
      ref,
      context,
      confirmado.picks.map((pick) => pick.game).toList(),
      ref.read(appStateProvider).selectedConsole?.id,
    );
    if (!mounted) return;
    ref.read(catalogProvider.notifier).clearSelection();
  }
```

E troque o `onDownload` da `SelectionBar`, que a Task 3 deixou com o corpo antigo do header, por uma linha:

```dart
          SelectionBar(
            count: ref.watch(catalogProvider.select((s) => s.selectedGames.length)),
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: _confirmarLote,
          ),
```

Três coisas nesse método não são estilo, são requisito:

1. **`if (!mounted) return;` depois de cada `await`.** Sem isso o `flutter analyze` ganha dois `use_build_context_synchronously` novos, e o critério de aceitação desta fatia é 22 findings e nenhum novo. Num `State` o analisador entende `mounted`; não troque por `context.mounted` sem rodar o analisador.
2. **A seleção é limpa depois de enfileirar.** Isso é diferente do app de hoje, que deixava os 40 jogos marcados depois de mandar baixar. Hoje isso passava porque não havia como desmarcar tudo de uma vez; a partir da Task 1 há, e deixar a barra roxa acesa sobre uma fila já enviada é convite para enfileirar duas vezes.
3. **`Navigator.pop` mora no `onConfirm`, não dentro da folha.** A folha não conhece navegação (Task 5), e é isso que permite testá-la sem `Navigator`.

- [ ] **Step 6: Prove que não quebrou nada**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Esperado: 22 findings e zero erro; `+202 -1` na suíte. A conta: 178 da linha de base, mais 2 da Task 1, 4 da Task 2, 6 da Task 4, 8 da Task 5 e 4 desta.

Confira à mão, porque nenhum teste cobre isso: rode o app, marque três jogos, aperte "Baixar", tire um da folha, confirme, e veja que dois entram na fila e a barra roxa apaga.

- [ ] **Step 7: Commit**

```bash
# agente de teste
git add test/source_pick_service_test.dart
git commit -m "test(lote): plano de lote do MODO FONTE, um pick por arquivo selecionado"

# agente de producao
git add lib/services/source_pick_service.dart lib/screens/home_screen.dart
git commit -m "feat(lote): plano de lote do MODO FONTE, um pick por arquivo selecionado"
```

O commit de produção leva os dois arquivos junto de propósito: a função sozinha não tem chamador e a tela sozinha não compila.

---

# Grupo 2: o índice invertido e os dados da grade

Aqui começa o MODO PACK. Este grupo é Dart puro do começo ao fim, exceto o último arquivo, que é de providers. Nenhum widget é tocado. Se um agente deste grupo abrir um arquivo em `lib/widgets/`, ele saiu do escopo.

O insumo é a fatia 2 inteira: `PackMatcher` casa nome de arquivo com `PackGame`, e `MetadataPack` traz os jogos. O que falta é a direção contrária, que é a que a grade precisa: **dado um jogo, quais arquivos existem para ele.**

---

### Task 7: `PackGridEntry`, uma entrada da grade de pack

**Files:**
- Create: `lib/models/grid_entry_model.dart`
- Test: `test/grid_entry_model_test.dart`

O tipo que a grade de MODO PACK desenha. Um `PackGame` mais as fontes que o matcher casou com ele. Dart puro, sem Flutter.

Leia a "Terceira decisão travada" no topo antes de começar: este tipo existe justamente para **não** sintetizar `Game`.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/grid_entry_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: const []);

MatchedSource _src(String filename, {MatchConfidence confidence = MatchConfidence.likely}) =>
    MatchedSource(filename: filename, sourceId: 'listagem', confidence: confidence, size: 1024);

void main() {
  test('sem fonte nenhuma a entrada não está disponível', () {
    final entry = PackGridEntry(game: _pg('snes/chrono-trigger', 'Chrono Trigger'), sources: const []);

    expect(entry.hasSource, isFalse);
    expect(entry.sourceCount, 0);
  });

  test('com pelo menos uma fonte a entrada está disponível', () {
    final entry = PackGridEntry(
      game: _pg('snes/chrono-trigger', 'Chrono Trigger'),
      sources: [_src('Chrono Trigger (USA).zip')],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 1);
  });

  test('a chave de seleção tem o prefixo pack:, e não colide com gameId', () {
    // Ver "Quarta decisão travada" no topo do plano. `Game.gameId` é
    // 'snes/arquivo.zip' e `PackGame.id` é 'snes/chrono-trigger': os dois
    // começam com letra e têm barra. O prefixo é o que os separa.
    final entry = PackGridEntry(game: _pg('snes/chrono-trigger', 'Chrono Trigger'), sources: const []);

    expect(entry.selectionKey, 'pack:snes/chrono-trigger');
  });

  test('a entrada não inventa confiança própria a partir das fontes', () {
    // Ver "Armadilha de leitura" no topo. Um jogo com uma fonte confirmada e
    // uma no chute continua sendo um jogo só, e o tile dele é igual ao de
    // qualquer outro jogo com fonte.
    final entry = PackGridEntry(
      game: _pg('snes/chrono-trigger', 'Chrono Trigger'),
      sources: [
        _src('a.zip', confidence: MatchConfidence.confirmed),
        _src('b.zip', confidence: MatchConfidence.guess),
      ],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 2);
    // Se você acabou de escrever `entry.confidence`, apague: não existe e não
    // vai existir.
  });
}
```

- [ ] **Step 2: Confira o nome real de `MatchedSource`**

Este é o passo que evita reescrever a Task inteira depois. `MatchedSource` **não existe ainda**: a fatia 2 entregou `GameMatch`, que é o veredito do matcher sobre **um nome de arquivo** e aponta para o `PackGame`. A grade precisa do sentido inverso e com o tamanho do arquivo junto, que o matcher não conhece.

Abra `lib/models/game_match_model.dart` e confira, com os seus olhos, os nomes de `MatchTier`, `MatchConfidence` e dos campos de `GameMatch`. Se algum nome deste plano divergir do arquivo, **o arquivo ganha**, e você corrige o plano ao passar.

- [ ] **Step 3: Implemente**

Crie `lib/models/grid_entry_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Um arquivo de uma fonte que o matcher casou com um `PackGame`.
///
/// É o `GameMatch` da fatia 2 virado do avesso: lá a chave é o nome do
/// arquivo e o valor é o jogo; aqui a chave é o jogo e isto é um dos valores.
/// O tamanho vem da listagem, não do matcher.
@immutable
class MatchedSource {
  final String filename;

  /// De qual fonte veio. Nesta fatia é sempre a listagem do console; na
  /// fatia 4 passa a ser o id do addon, e é por isso que o campo já existe.
  final String sourceId;
  final MatchConfidence confidence;

  /// Bytes, ou zero quando a listagem não declara tamanho.
  final int size;

  /// A URL de download. Fica nula quando a fonte não a fornece de imediato.
  final String? url;

  const MatchedSource({
    required this.filename,
    required this.sourceId,
    required this.confidence,
    required this.size,
    this.url,
  });
}

/// Uma entrada da grade em MODO PACK: um jogo canônico e as fontes dele.
///
/// A grade desenha isto, e não `Game`. Ver "Terceira decisão travada" no
/// plano da fatia 3.
@immutable
class PackGridEntry {
  final PackGame game;
  final List<MatchedSource> sources;

  const PackGridEntry({required this.game, this.sources = const []});

  /// O único eixo que o tile pinta. Ver "Armadilha de leitura": o tile mostra
  /// **disponibilidade**, nunca confiança.
  bool get hasSource => sources.isNotEmpty;

  int get sourceCount => sources.length;

  /// A chave de seleção em MODO PACK. O prefixo `pack:` é obrigatório porque
  /// `Game.gameId` e `PackGame.id` não são provadamente disjuntos, e `:` não
  /// pode aparecer num id gerado por `_nameToId` (`catalog_service.dart:61-63`).
  String get selectionKey => 'pack:${game.id}';
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/grid_entry_model_test.dart
```

Esperado: `+4`, zero falha.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/grid_entry_model_test.dart
git commit -m "test(grade): entrada de grade de pack, disponibilidade e chave de selecao"

# agente de producao
git add lib/models/grid_entry_model.dart
git commit -m "feat(grade): entrada de grade de pack, disponibilidade e chave de selecao"
```

---

### Task 8: `SourceIndex`, o matcher virado do avesso

**Files:**
- Create: `lib/services/source_index.dart`
- Test: `test/source_index_test.dart`

O `PackMatcher` da fatia 2 responde "que jogo é este arquivo". A grade precisa do contrário: "que arquivos existem para este jogo". Este é o índice invertido, construído uma vez por console e consultado por tile.

**Custo, porque isso decide a forma.** São 2415 jogos e alguns milhares de arquivos no console médio. Construir de uma vez é uma passada; perguntar por tile durante o scroll seria uma passada por tile. Por isso `build` é estático e o resultado é guardado num provider (Task 10), nunca recalculado no `build` de um widget.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/source_index_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';

PackGame _pg(String id, String dumpName) => PackGame(
      id: id,
      title: dumpName,
      dumps: [PackDump(name: dumpName)],
    );

PackMatcher _matcher() => PackMatcher(MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/chrono-trigger', 'Chrono Trigger (USA)'),
        _pg('snes/super-metroid', 'Super Metroid (USA)'),
        _pg('snes/earthbound', 'EarthBound (USA)'),
      ],
    ));

SourceFile _f(String filename, {int size = 1024}) =>
    (filename: filename, sourceId: 'listagem', size: size, url: null);

void main() {
  test('cada arquivo casado entra na lista do jogo dele', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),
      _f('Super Metroid (USA).zip'),
    ]);

    expect(index.sourcesFor('snes/chrono-trigger').single.filename, 'Chrono Trigger (USA).zip');
    expect(index.sourcesFor('snes/super-metroid').single.filename, 'Super Metroid (USA).zip');
    expect(index.hasSource('snes/earthbound'), isFalse);
  });

  test('duas versões do mesmo jogo ficam juntas, na ordem da listagem', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),
      _f('Chrono Trigger (Europe).zip'),
    ]);

    expect(
      index.sourcesFor('snes/chrono-trigger').map((s) => s.filename),
      ['Chrono Trigger (USA).zip', 'Chrono Trigger (Europe).zip'],
    );
  });

  test('a confiança de cada fonte vem do tier daquele arquivo', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),   // nome exato
      _f('Chrono Triggr (USA).zip'),    // erro de digitação, cai no fuzzy
    ]);

    final fontes = index.sourcesFor('snes/chrono-trigger');
    expect(fontes.map((s) => s.confidence),
        [MatchConfidence.likely, MatchConfidence.guess]);
  });

  test('o tamanho e a fonte de origem sobrevivem à travessia', () {
    final index = SourceIndex.build(_matcher(), [_f('Chrono Trigger (USA).zip', size: 4096)]);

    final fonte = index.sourcesFor('snes/chrono-trigger').single;
    expect(fonte.size, 4096);
    expect(fonte.sourceId, 'listagem');
  });

  test('arquivo que não casa com jogo nenhum vira um não reconhecido', () {
    final index = SourceIndex.build(_matcher(), [_f('Jogo Que Nao Existe (USA).zip')]);

    expect(index.unmatched, ['Jogo Que Nao Existe (USA).zip']);
    expect(index.matchedGameCount, 0);
  });

  test('o que não é ROM é ignorado, e não conta como não reconhecido', () {
    // A listagem do archive.org vem cheia de .txt, .png e .xml de índice.
    // Chamar isso de "não reconhecido" mentiria na faixa da Task 12.
    final index = SourceIndex.build(_matcher(), [
      _f('leiame.txt'),
      _f('Chrono Trigger (USA).zip'),
    ]);

    expect(index.unmatched, isEmpty);
    expect(index.matchedGameCount, 1);
  });

  test('jogo sem fonte devolve lista vazia, nunca nulo', () {
    final index = SourceIndex.build(_matcher(), const []);

    expect(index.sourcesFor('snes/earthbound'), isEmpty);
    expect(index.sourcesFor('id/que/nao/existe'), isEmpty);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_index_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/services/source_index.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/services/source_index.dart`:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Um arquivo cru de uma fonte, antes de o matcher opinar sobre ele.
///
/// É um registro e não uma classe porque não tem comportamento nenhum e
/// porque quem o produz muda por fatia: nesta é a listagem do console, na
/// fatia 4 é o addon. `pack_matcher.dart:25` já usa registro pelo mesmo motivo.
typedef SourceFile = ({String filename, String sourceId, int size, String? url});

/// Índice invertido: dado o id de um `PackGame`, quais arquivos existem.
///
/// O `PackMatcher` responde "que jogo é este arquivo". Isto responde
/// "que arquivos são este jogo", que é o que a grade pergunta.
///
/// Construa uma vez por console, em `build`, e guarde. Não construa dentro do
/// `build` de um widget: são milhares de chamadas de `match` por vez.
class SourceIndex {
  final Map<String, List<MatchedSource>> _byGameId;

  /// Nomes com extensão de ROM que o matcher não atribuiu a jogo nenhum.
  /// O que não é ROM nunca entra aqui: seria ruído de índice de listagem.
  final List<String> unmatched;

  const SourceIndex._(this._byGameId, this.unmatched);

  static SourceIndex build(PackMatcher matcher, List<SourceFile> files) {
    final byGameId = <String, List<MatchedSource>>{};
    final unmatched = <String>[];

    for (final file in files) {
      if (!hasRomExtension(file.filename)) continue;
      final match = matcher.match(file.filename);
      if (match == null) {
        unmatched.add(file.filename);
        continue;
      }
      byGameId.putIfAbsent(match.game.id, () => <MatchedSource>[]).add(MatchedSource(
            filename: file.filename,
            sourceId: file.sourceId,
            confidence: match.confidence,
            size: file.size,
            url: file.url,
          ));
    }

    return SourceIndex._(byGameId, unmatched);
  }

  /// As fontes daquele jogo, **na ordem da listagem**. Quem ordena por
  /// preferência é a regra de escolha (Task 14), não o índice.
  List<MatchedSource> sourcesFor(String gameId) => _byGameId[gameId] ?? const [];

  bool hasSource(String gameId) => _byGameId.containsKey(gameId);

  /// Quantos jogos do pacote têm ao menos uma fonte. É o que decide a faixa
  /// de estado vazio da Task 12.
  int get matchedGameCount => _byGameId.length;
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_index_test.dart
```

Esperado: `+7`, zero falha.

Se o caso do fuzzy falhar dizendo que a confiança veio `likely` em vez de `guess`, não mexa no `SourceIndex`: leia `pack_matcher.dart:12`, onde mora `fuzzyCutoff = 90.0`, e confirme que `Chrono Triggr` ainda cai acima do corte. O teste está aí justamente para avisar se o corte mudar.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/source_index_test.dart
git commit -m "test(grade): indice invertido de jogo para fontes casadas"

# agente de producao
git add lib/services/source_index.dart
git commit -m "feat(grade): indice invertido de jogo para fontes casadas"
```

---

### Task 9: `filterPackEntries`, a busca da grade de pack

**Files:**
- Create: `lib/services/pack_grid_filter.dart`
- Test: `test/pack_grid_filter_test.dart`

Leia a "Quinta decisão travada" no topo antes de começar. Resumo em uma linha: **busca por texto sim, chips de região e revisão não.** Se você se pegar escrevendo `filter.regions` neste arquivo, parou no lugar errado.

Duas funções em uma: filtra pelo texto que veio da caixa de busca do header e ordena. A ordenação está aqui, e não no provider, porque ordenar é decisão de apresentação e porque assim ela se testa sem Riverpod.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_grid_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';

PackGridEntry _e(String title, {bool comFonte = true}) => PackGridEntry(
      game: PackGame(id: 'snes/${title.toLowerCase()}', title: title, dumps: const []),
      sources: comFonte
          ? [const MatchedSource(filename: 'a.zip', sourceId: 'listagem', confidence: MatchConfidence.likely, size: 1)]
          : const [],
    );

void main() {
  test('busca vazia devolve tudo', () {
    final saida = filterPackEntries([_e('Super Metroid'), _e('Chrono Trigger')], '');

    expect(saida.length, 2);
  });

  test('a saída sai ordenada por título, não na ordem do pacote', () {
    final saida = filterPackEntries([_e('Super Metroid'), _e('Chrono Trigger'), _e('EarthBound')], '');

    expect(saida.map((e) => e.game.title), ['Chrono Trigger', 'EarthBound', 'Super Metroid']);
  });

  test('a busca ignora caixa e acento', () {
    // `norm` já dobra acento e baixa a caixa desde a fatia 2. Não reimplemente.
    final saida = filterPackEntries([_e('Pokémon Red'), _e('Super Metroid')], 'pokemon');

    expect(saida.single.game.title, 'Pokémon Red');
  });

  test('a busca casa pedaço do meio do título', () {
    final saida = filterPackEntries([_e('The Legend of Zelda'), _e('Super Metroid')], 'zelda');

    expect(saida.single.game.title, 'The Legend of Zelda');
  });

  test('busca sem resultado devolve lista vazia', () {
    final saida = filterPackEntries([_e('Super Metroid')], 'halo');

    expect(saida, isEmpty);
  });

  test('jogo sem fonte continua aparecendo, porque a grade mostra tudo', () {
    // Decisão travada do projeto inteiro: a grade mostra todos os jogos do
    // pacote e marca a exceção. Filtrar por disponibilidade aqui é o erro que
    // esta linha existe para impedir.
    final saida = filterPackEntries([_e('Super Metroid', comFonte: false)], '');

    expect(saida.single.hasSource, isFalse);
  });

  test('espaço em volta da busca não conta', () {
    final saida = filterPackEntries([_e('Super Metroid')], '  metroid  ');

    expect(saida.length, 1);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_filter_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/services/pack_grid_filter.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/services/pack_grid_filter.dart`:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Busca e ordenação da grade em MODO PACK.
///
/// Dart puro e síncrono de propósito. O MODO FONTE usa `FilteringService` num
/// isolate porque lá o filtro é caro (regex de região, revisão, agrupamento de
/// revisão mais recente). Aqui é um `contains` sobre alguns milhares de
/// títulos já normalizados; mandar isso para um isolate custaria mais em
/// serialização do que o próprio filtro.
///
/// **Não** filtra por região, revisão ou qualidade de dump. Ver "Quinta
/// decisão travada" no plano da fatia 3: essas são propriedades de uma versão,
/// e em MODO PACK a grade não tem versão.
///
/// **Não** filtra por disponibilidade. A grade mostra o pacote inteiro e marca
/// a exceção; esconder o que não tem fonte é o oposto do que o spec pede.
List<PackGridEntry> filterPackEntries(List<PackGridEntry> entries, String query) {
  final needle = norm(query);
  final out = needle.isEmpty
      ? [...entries]
      : entries.where((entry) => norm(entry.game.title).contains(needle)).toList();

  out.sort((a, b) {
    final byTitle = norm(a.game.title).compareTo(norm(b.game.title));
    // Desempate estável por id: dois jogos de título igual existem (uma
    // reedição, um homônimo de região), e sem isto a ordem da grade mudaria
    // de uma reconstrução para a outra.
    return byTitle != 0 ? byTitle : a.game.id.compareTo(b.game.id);
  });
  return out;
}
```

Uma nota sobre `norm`, conferida rodando e não por leitura: ele apara extensão de ROM (`pack_naming.dart:80`), mas só quando o texto **termina** com a extensão, ponto incluso. `norm('md')` é `'md'` e `norm('bin')` é `'bin'`, então buscar por essas letras funciona normalmente. O único caso degenerado é uma busca que seja exatamente uma extensão com o ponto, como `.md`: `norm` devolve string vazia e a grade mostra tudo. Ninguém digita isso, e consertar exigiria uma segunda função de normalização só para busca. Não conserte nesta fatia.

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_filter_test.dart
```

Esperado: `+7`, zero falha.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/pack_grid_filter_test.dart
git commit -m "test(grade): busca e ordenacao da grade de pack, sem chip de versao"

# agente de producao
git add lib/services/pack_grid_filter.dart
git commit -m "feat(grade): busca e ordenacao da grade de pack, sem chip de versao"
```

---

### Task 10: os providers da grade de pack

**Files:**
- Create: `lib/providers/pack_grid_provider.dart`
- Test: `test/pack_grid_provider_test.dart`

Seis providers pequenos. Três são entradas, e existem para que os outros três se testem sem tocar em `AppStateNotifier` nem em `CatalogNotifier`, que fazem IO no construtor.

**A decisão que este arquivo trava, e ela é a mais importante da fatia:** enquanto o pacote não chegou, e também se ele nunca chegar, o modo é **FONTE**. Nada de spinner novo, nada de tela em branco. O MODO FONTE é o app de hoje, e cair nele é por definição não regredir. Um console sem pacote, um usuário sem rede e o primeiro segundo de qualquer sessão são o mesmo caso, e todos eles veem exatamente o app que já viam.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_grid_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';

const _alvo = PackTarget('snes', 'Super Nintendo');

PackGame _pg(String id, String dumpName) =>
    PackGame(id: id, title: dumpName, dumps: [PackDump(name: dumpName)]);

MetadataPack _pack() => MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/chrono-trigger', 'Chrono Trigger (USA)'),
        _pg('snes/super-metroid', 'Super Metroid (USA)'),
      ],
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://exemplo.org/snes/$filename',
      size: 2048,
      consoleId: 'snes',
    );

ProviderContainer _container({
  PackTarget? alvo = _alvo,
  Future<MetadataPack?>? pacote,
  List<Game> jogos = const [],
  String busca = '',
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(alvo),
    if (alvo != null)
      metadataPackProvider(alvo).overrideWith((ref) => pacote ?? Future.value(_pack())),
    catalogGamesProvider.overrideWithValue(jogos),
    gridSearchQueryProvider.overrideWithValue(busca),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Espera o pacote e o matcher resolverem. Sem isto os providers síncronos
/// ainda estão vendo `AsyncLoading`, que é um estado legítimo e testado à parte.
Future<void> _pronto(ProviderContainer container) async {
  await container.read(metadataPackProvider(_alvo).future);
  await container.read(packMatcherProvider(_alvo).future);
}

void main() {
  test('sem console selecionado o modo é FONTE e a grade fica vazia', () {
    final container = _container(alvo: null);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
    expect(container.read(sourceIndexProvider), isNull);
  });

  test('enquanto o pacote carrega o modo é FONTE', () {
    // Sem `await`. É este o estado do primeiro quadro de toda sessão.
    final container = _container(pacote: Future.delayed(const Duration(seconds: 1), _pack));

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('console sem pacote fica em MODO FONTE', () async {
    final container = _container(pacote: Future.value(null));
    await container.read(metadataPackProvider(_alvo).future);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
  });

  test('erro ao buscar o pacote cai em MODO FONTE, não em tela de erro', () async {
    final container = _container(pacote: Future.error(Exception('sem rede')));
    await expectLater(container.read(metadataPackProvider(_alvo).future), throwsException);

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('com pacote o modo é PACK e a grade traz todos os jogos do pacote', () async {
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')]);
    await _pronto(container);

    expect(container.read(gridModeProvider), GridMode.pack);
    final entradas = container.read(packGridEntriesProvider);
    expect(entradas.map((e) => e.game.id), ['snes/chrono-trigger', 'snes/super-metroid']);
    // O que não tem fonte continua na grade, marcado, e não some dela.
    expect(entradas.map((e) => e.hasSource), [true, false]);
  });

  test('a fonte casada carrega o tamanho e o id de fonte embutido', () async {
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')]);
    await _pronto(container);

    final fonte = container.read(packGridEntriesProvider).first.sources.single;
    expect(fonte.filename, 'Chrono Trigger (USA).zip');
    expect(fonte.size, 2048);
    expect(fonte.sourceId, kBuiltinSourceId);
    expect(fonte.url, 'https://exemplo.org/snes/Chrono Trigger (USA).zip');
  });

  test('a busca do header filtra a grade de pack', () async {
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')], busca: 'metroid');
    await _pronto(container);

    expect(container.read(packGridEntriesProvider).single.game.id, 'snes/super-metroid');
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/providers/pack_grid_provider.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/providers/pack_grid_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_index.dart';

/// Os dois modos de grade da seção 7 do spec de arquitetura.
enum GridMode {
  /// A grade de hoje: um tile por arquivo da listagem.
  source,

  /// A grade nova: um tile por jogo do pacote.
  pack,
}

/// O console selecionado, na forma que o provider de pacote entende.
///
/// Este é o seam de teste: sobrescreva **este** provider, nunca o
/// `appStateProvider`, que faz IO de disco e de rede no construtor.
///
/// Nota sobre colisão de chave, que é a "Quarta decisão travada" do plano da
/// fatia 3: a chave de seleção em MODO PACK é `'pack:${packGame.id}'`. O `:`
/// não pode sair de `CatalogService._nameToId` (`catalog_service.dart:61-63`),
/// então ela não colide com `Game.gameId`. O único caminho de colisão é um
/// `consoles.json` no formato de mapa legado (`catalog_service.dart:95-96`),
/// que usa a chave do mapa verbatim: um console escrito à mão com id
/// `pack:snes` colidiria. É edge conhecido e aceito, sem código de defesa.
final packTargetProvider = Provider<PackTarget?>((ref) {
  final console = ref.watch(appStateProvider.select((s) => s.selectedConsole));
  if (console == null) return null;
  return PackTarget(console.id, console.name);
});

/// A listagem do console. Seam de teste pelo mesmo motivo acima.
final catalogGamesProvider =
    Provider<List<Game>>((ref) => ref.watch(catalogProvider.select((s) => s.games)));

/// O texto da caixa de busca do header. A mesma caixa dos dois modos: o que
/// muda é só quem consome. Ver "Quinta decisão travada" no plano.
final gridSearchQueryProvider =
    Provider<String>((ref) => ref.watch(catalogProvider.select((s) => s.filterText)));

/// Qual grade desenhar.
///
/// **Tudo que não é "o pacote chegou" é MODO FONTE**: sem console, pacote
/// carregando, console sem pacote, erro de rede. O MODO FONTE é o app de hoje,
/// então degradar para ele nunca é regressão, e essa é a única razão de este
/// provider ser síncrono em vez de devolver `AsyncValue`.
final gridModeProvider = Provider<GridMode>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return GridMode.source;
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  return pack == null ? GridMode.source : GridMode.pack;
});

/// O índice invertido do console atual. Null enquanto não há matcher.
///
/// Reconstrói quando a listagem muda, o que acontece uma vez por carga de
/// catálogo. **Não** reconstrói a cada tecla digitada: a busca é aplicada
/// depois, no provider de entradas.
final sourceIndexProvider = Provider<SourceIndex?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  final matcher = ref.watch(packMatcherProvider(target)).valueOrNull;
  if (matcher == null) return null;
  return SourceIndex.build(matcher, <SourceFile>[
    for (final game in ref.watch(catalogGamesProvider))
      (filename: game.filename, sourceId: kBuiltinSourceId, size: game.size, url: game.url),
  ]);
});

/// O que a grade de MODO PACK desenha, já filtrado e ordenado.
///
/// Em MODO FONTE ninguém lê este provider, e ele devolve lista vazia sem
/// custo, porque `metadataPackProvider` já resolveu para null.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], ref.watch(gridSearchQueryProvider));
});
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `+7`, zero falha.

Dois tropeços prováveis, e os dois têm conserto conhecido:

- Se `metadataPackProvider(alvo).overrideWith(...)` não compilar, confira a versão do Riverpod em `pubspec.yaml`. Em 2.6 a sobrescrita de um membro de família é `provider(arg).overrideWith((ref) => valor)`. Não troque por `overrideWithValue` num `FutureProvider`: essa forma foi removida.
- Se o caso do erro de rede fizer o teste inteiro falhar em vez de passar, é o `ProviderContainer` propagando o erro no descarte. O `expectLater(..., throwsException)` antes da asserção existe para consumir esse erro; mantenha-o.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/pack_grid_provider_test.dart
git commit -m "test(grade): providers de modo, indice e entradas da grade de pack"

# agente de producao
git add lib/providers/pack_grid_provider.dart
git commit -m "feat(grade): providers de modo, indice e entradas da grade de pack"
```

---

# Grupo 3: o tile, a grade e o roteamento

Agora a UI. Os dois widgets deste grupo são puros: recebem primitivos e callbacks, não conhecem Riverpod, e por isso se testam sozinhos num `MaterialApp`, sem `ProviderScope`. O modelo é `test/menu_grid_test.dart`, 31 linhas.

Lembrete que vale para o grupo inteiro: **`game_grid_item.dart` e `game_grid.dart` não são tocados.** O que a seção 3.1 do spec de UI descreve como "sai do tile" já nasce fora do tile novo.

---

### Task 11: `PackGridItem`, o tile de um jogo

**Files:**
- Create: `lib/widgets/game_grid/pack_grid_item.dart`
- Test: `test/pack_grid_item_test.dart`

O tile da seção 3.1. Capa, título sobreposto, a marca de "sem fonte", o checkbox de seleção, a borda de estado.

**O que este tile não faz nesta fatia, e por quê.** A seção 3.1 lista a barra de progresso entre o que o tile mantém. Ela **não** entra aqui. Progresso é propriedade de um arquivo, e este tile é um jogo com N arquivos; descobrir "alguma fonte deste jogo está baixando" exige ler o estado de N fontes por tile, a cada quadro de scroll, que é exatamente o custo que a Task 8 existe para evitar. Enquanto isso, a fila do rodapé continua mostrando todo download em andamento, e ela não muda nesta fatia. Quando alguém quiser a barra de volta, a receita é a mesma da Task 13: um `Set<String>` de jogos com download ativo, calculado uma vez, nunca por tile. **Não improvise isso agora.**

**O hover do desktop também não entra, e é divergência anotada.** A seção 4 do spec de UI diz que no desktop o checkbox aparece no hover do tile mesmo com a seleção vazia. Fazer isso exige virar este widget em `StatefulWidget` só para guardar um `bool` de `MouseRegion`, e o teste de hover em `flutter_test` exige montar um ponteiro de mouse à mão. O que se perde sem ele é **descoberta**, não capacidade: o toque longo funciona com o mouse (pressionar e segurar), e assim que existe uma seleção o checkbox aparece em todos os tiles. Fica anotado como divergência deliberada, junto das outras três da tabela de "Estrutura de arquivos".

Leia a "Armadilha de leitura" no topo do plano antes do Step 1. O tile não pinta confiança. Ele pinta disponibilidade.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_grid_item_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

// `coverUrl` fica nulo em todo teste de propósito: com URL, o
// `CachedNetworkImage` tentaria rede dentro do teste. A capa é coberta à mão.
Widget _host(
  Widget child, {
  double largura = 200,
}) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: largura, child: child))));

void main() {
  testWidgets('mostra o título do jogo', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.text('Chrono Trigger'), findsOneWidget);
  });

  testWidgets('sem fonte ganha a marca de nuvem cortada', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('com fonte não ganha marca nenhuma', (tester) async {
    // A premissa da seção 3.1: marca-se a exceção, não a regra.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('o tile é igual com fonte confirmada e com fonte no chute', (tester) async {
    // Não existe parâmetro de confiança neste widget, e este teste existe para
    // que a ausência seja intencional e visível. Se alguém acrescentar
    // `confidence:` aqui, este teste não compila mais e é isso que se quer.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets('sem seleção ativa não há checkbox', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('com seleção ativa todo tile mostra checkbox, marcado ou não', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      isSelected: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('o tile selecionado mostra o checkbox marcado', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      isSelected: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('toque curto abre e toque longo seleciona', (tester) async {
    var abriu = 0;
    var selecionou = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () => abriu++,
      onLongPress: () => selecionou++,
      onToggleSelection: () {},
    )));

    await tester.tap(find.byType(PackGridItem));
    await tester.longPress(find.byType(PackGridItem));
    await tester.pump();

    expect(abriu, 1);
    expect(selecionou, 1);
  });

  testWidgets('o checkbox alterna a seleção sem abrir o detalhe', (tester) async {
    var abriu = 0;
    var alternou = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      onTap: () => abriu++,
      onLongPress: () {},
      onToggleSelection: () => alternou++,
    )));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(alternou, 1);
    expect(abriu, 0);
  });

  testWidgets('a borda grossa aparece quando o jogo já está no disco', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      isOwned: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final borda = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((borda.decoration as BoxDecoration).border!.top.width, 3);
  });

  testWidgets('sem estado nenhum a borda é fina', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final borda = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((borda.decoration as BoxDecoration).border!.top.width, 1);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_item_test.dart
```

Esperado: `Target of URI doesn't exist: '.../pack_grid_item.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/widgets/game_grid/pack_grid_item.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// O tile de MODO PACK: representa um **jogo**, não um arquivo.
///
/// Widget puro de propósito. Ele não sabe o que é `PackGridEntry`, não lê
/// provider nenhum e não decide nada: quem monta é `PackGrid` (Task 12).
///
/// O que ele **não** tem, e a ausência é a parte importante:
/// - nenhum parâmetro de confiança de match. O tile mostra disponibilidade,
///   e um jogo com uma fonte confirmada e uma no chute é um jogo só. Ver
///   "Armadilha de leitura" no plano da fatia 3.
/// - nenhum botão de baixar. O tile não sabe qual arquivo baixar, então não
///   pode ter botão de baixar (spec de UI, seção 3.1).
/// - nenhuma tag de região, revisão ou disco. Essas descrevem uma versão.
class PackGridItem extends StatelessWidget {
  final String title;

  /// URL da capa do pacote. Nulo cai no marcador de capa ausente.
  final String? coverUrl;

  /// Se algum addon tem algum arquivo para este jogo. **É o único eixo que
  /// muda o desenho do tile.**
  final bool hasSource;

  /// Se alguma versão deste jogo já está no disco (Task 13). Enquanto o scan
  /// não terminou vem `false`, porque borda errada é pior que borda ausente.
  final bool isOwned;

  final bool isSelected;

  /// Se há seleção em curso. Com seleção vazia o checkbox some de **todos**
  /// os tiles, para a capa ficar limpa (spec de UI, seção 4).
  final bool selectionActive;

  final double aspectRatio;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelection;

  const PackGridItem({
    super.key,
    required this.title,
    required this.hasSource,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelection,
    this.coverUrl,
    this.isOwned = false,
    this.isSelected = false,
    this.selectionActive = false,
    this.aspectRatio = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color? borderColor = isSelected
        ? scheme.primary
        : isOwned
            ? scheme.secondaryContainer
            : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: const ValueKey('pack-tile-border'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: borderColor != null ? 3 : 1,
          ),
        ),
        child: Tooltip(
          message: title,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _cover(context),
                ),
                if (selectionActive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelection(),
                        shape: const CircleBorder(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                // Dois sinais redundantes para "sem fonte": a capa dessaturada
                // e este ícone. Cinza sozinho confunde com "carregando", e
                // muita capa de época já é quase monocromática.
                if (!hasSource)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = coverUrl;
    final capa = url == null
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (context, _, __) => _placeholder(context),
            errorListener: (_) {},
          );
    if (hasSource) return capa;
    // Matriz de saturação zero. É o mesmo truque do `ColorFilter.mode` com
    // cinza, mas preserva o brilho da arte em vez de achatá-la.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: capa,
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.3),
            scheme.secondaryContainer.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videogame_asset_rounded,
          size: 32,
          color: scheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_item_test.dart
```

Esperado: `+11`, zero falha.

Se `tester.tap(find.byType(PackGridItem))` reclamar de alvo ambíguo ou de ponteiro fora da tela, aumente a `largura` do `_host`: o tile respeita `aspectRatio` e um `SizedBox` estreito demais pode estourar a altura da tela de teste.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/pack_grid_item_test.dart
git commit -m "test(grade): tile de jogo com marca de sem fonte e selecao por toque longo"

# agente de producao
git add lib/widgets/game_grid/pack_grid_item.dart
git commit -m "feat(grade): tile de jogo com marca de sem fonte e selecao por toque longo"
```

---

### Task 12: `PackGrid`, a grade de MODO PACK

**Files:**
- Create: `lib/widgets/game_grid/pack_grid.dart`
- Test: `test/pack_grid_test.dart`

A grade que desenha os tiles da Task 11 a partir dos providers da Task 10, mais a faixa de estado vazio da seção 3.2.

**A grade não navega.** O toque curto chama `onOpenGame`, e quem empurra a rota é o `HomeScreen`, na Task 19. Isso não é purismo: é o que permite testar a grade sem `Navigator` e sem a tela de detalhe, que só existe a partir da Task 15.

**A faixa de estado vazio nesta fatia.** A seção 3.2 fala em "nenhum addon instalado", e addon é fatia 4. Nesta fatia a única fonte é a listagem que já vem no `consoles.json`, então a condição equivalente, e verdadeira hoje, é **o índice não casou nenhum jogo**. Um pacote de SNES contra uma listagem de Nintendo Switch cai exatamente aí. Na fatia 4 a condição vira "nenhum addon cobre este console" e o texto já está pronto.

**A borda de "já baixado" não entra aqui.** `PackGridItem.isOwned` fica no padrão `false`. Ela chega na Task 13, que é a única que sabe o que está no disco.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: [PackDump(name: '$title (USA)')]);

PackGridEntry _entrada(String id, String title, {bool comFonte = true}) => PackGridEntry(
      game: _pg(id, title),
      sources: comFonte
          ? [MatchedSource(filename: '$title (USA).zip', sourceId: kBuiltinSourceId, confidence: MatchConfidence.likely, size: 1024)]
          : const [],
    );

/// Um índice de verdade, porque a faixa de estado vazio lê `matchedGameCount`
/// e um índice falso não provaria nada.
SourceIndex _indice({required bool casaAlgo}) {
  final matcher = PackMatcher(MetadataPack(
    pack: 'snes',
    system: 'Super Nintendo',
    built: '2026-01-01',
    games: [_pg('snes/chrono-trigger', 'Chrono Trigger')],
  ));
  return SourceIndex.build(matcher, [
    if (casaAlgo)
      (filename: 'Chrono Trigger (USA).zip', sourceId: kBuiltinSourceId, size: 1024, url: null),
  ]);
}

Widget _host(
  List<PackGridEntry> entradas, {
  SourceIndex? indice,
  void Function(PackGridEntry)? onOpenGame,
}) {
  return ProviderScope(
    overrides: [
      packGridEntriesProvider.overrideWithValue(entradas),
      sourceIndexProvider.overrideWithValue(indice ?? _indice(casaAlgo: true)),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}

void main() {
  testWidgets('desenha um tile por entrada', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/super-metroid', 'Super Metroid'),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.text('Chrono Trigger'), findsOneWidget);
  });

  testWidgets('o jogo sem fonte continua na grade, marcado', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/earthbound', 'EarthBound', comFonte: false),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('com o índice vazio aparece a faixa de sem cobertura', (tester) async {
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger', comFonte: false)],
      indice: _indice(casaAlgo: false),
    ));

    expect(find.text('Nenhuma fonte cobre este console'), findsOneWidget);
    // A faixa é estado da grade, não do tile: os tiles continuam lá.
    expect(find.byType(PackGridItem), findsOneWidget);
  });

  testWidgets('com o índice cobrindo alguma coisa não há faixa', (tester) async {
    await tester.pumpWidget(_host([_entrada('snes/chrono-trigger', 'Chrono Trigger')]));

    expect(find.text('Nenhuma fonte cobre este console'), findsNothing);
  });

  testWidgets('busca sem resultado mostra o vazio de busca, não o de cobertura', (tester) async {
    await tester.pumpWidget(_host(const []));

    expect(find.text('Nenhum jogo com esse nome'), findsOneWidget);
    expect(find.text('Nenhuma fonte cobre este console'), findsNothing);
  });

  testWidgets('o toque curto devolve a entrada tocada', (tester) async {
    final abertas = <String>[];
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger'), _entrada('snes/super-metroid', 'Super Metroid')],
      onOpenGame: (entry) => abertas.add(entry.game.id),
    ));

    await tester.tap(find.text('Super Metroid'));
    await tester.pump();

    expect(abertas, ['snes/super-metroid']);
  });

  testWidgets('o toque longo seleciona, e aí o checkbox aparece em todo tile', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/super-metroid', 'Super Metroid'),
    ]));

    expect(find.byType(Checkbox), findsNothing);

    await tester.longPress(find.text('Chrono Trigger'));
    await tester.pump();

    // Dois checkboxes, um marcado. É a regra da seção 4: a visibilidade do
    // checkbox é global, o valor dele é por tile.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).where((c) => c.value == true).length,
      1,
    );
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_test.dart
```

Esperado: `Target of URI doesn't exist: '.../pack_grid.dart'`.

- [ ] **Step 3: Implemente**

Crie `lib/widgets/game_grid/pack_grid.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

/// A grade de MODO PACK: um tile por jogo do pacote.
///
/// Não substitui `GameGrid`, convive com ela. Quem escolhe qual das duas
/// desenhar é o `HomeScreen`, pelo `gridModeProvider` (Task 19).
class PackGrid extends ConsumerWidget {
  /// Chamado no toque curto de um tile. A grade não conhece `Navigator`: quem
  /// empurra a rota do detalhe é o `HomeScreen`.
  final void Function(PackGridEntry entry) onOpenGame;

  const PackGrid({super.key, required this.onOpenGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(packGridEntriesProvider);
    final index = ref.watch(sourceIndexProvider);
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final catalogNotifier = ref.read(catalogProvider.notifier);

    // Seção 4 do spec de UI: a visibilidade do checkbox é global e depende só
    // de haver seleção em curso. Com seleção vazia, capa limpa em todo tile.
    final selectionActive = selected.isNotEmpty;

    // Seção 3.2. Nesta fatia "nenhuma fonte" quer dizer "a listagem deste
    // console não casou com nenhum jogo do pacote". Na fatia 4 a condição
    // passa a ser "nenhum addon instalado cobre este console" e o texto fica.
    final semCobertura = (index?.matchedGameCount ?? 0) == 0;

    return Column(
      children: [
        if (semCobertura) const _SemCoberturaBanner(),
        Expanded(
          child: entries.isEmpty
              ? const _VazioDeBusca()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    // Proporção fixa, ao contrário de `GameGrid`, que mede a
                    // primeira capa da listagem. As capas do pacote vêm todas
                    // da mesma origem e já são consistentes, então medir seria
                    // um round-trip de imagem por troca de console, de graça.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return PackGridItem(
                        key: ValueKey(entry.selectionKey),
                        title: entry.game.title,
                        coverUrl: entry.game.cover,
                        hasSource: entry.hasSource,
                        isSelected: selected.contains(entry.selectionKey),
                        selectionActive: selectionActive,
                        onTap: () => onOpenGame(entry),
                        onLongPress: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                        onToggleSelection: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _SemCoberturaBanner extends StatelessWidget {
  const _SemCoberturaBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nenhuma fonte cobre este console',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Os jogos aparecem para consulta, mas não há nada para baixar.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VazioDeBusca extends StatelessWidget {
  const _VazioDeBusca();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Nenhum jogo com esse nome',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_test.dart
```

Esperado: `+7`, zero falha.

Dois tropeços prováveis:

- Se o toque longo não selecionar nada, o culpado é o `catalogProvider` de verdade dentro do `ProviderScope`. Ele é real de propósito, para provar a fiação inteira; o construtor dele escuta `favoritesProvider`, que toca disco, e num `testWidgets` o binding já está inicializado, então funciona. Se mesmo assim quebrar, o conserto é `TestWidgetsFlutterBinding.ensureInitialized()` na primeira linha de `main`, e **não** sobrescrever `catalogProvider`.
- Se `find.text('Super Metroid')` achar mais de um widget, é o `Tooltip` do tile duplicando o texto na árvore. Nesse caso use `find.byKey(const ValueKey('pack:snes/super-metroid'))`.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/pack_grid_test.dart
git commit -m "test(grade): grade de pack com faixa de sem cobertura e selecao por toque longo"

# agente de producao
git add lib/widgets/game_grid/pack_grid.dart
git commit -m "feat(grade): grade de pack com faixa de sem cobertura e selecao por toque longo"
```

---

### Task 13: `ownedGameIdsProvider`, quem já está no disco

**Files:**
- Create: `lib/providers/owned_games_provider.dart`
- Create: `test/owned_games_provider_test.dart`
- Modify: `lib/widgets/game_grid/pack_grid.dart` (a grade passa a preencher `isOwned`)
- Modify: `test/pack_grid_test.dart` (dois testes novos no fim)

A borda de "já baixado" da seção 3.1. O tile já sabe desenhá-la desde a Task 11 e a grade já a deixou no padrão `false` na Task 12. Esta Task é a única que olha o disco.

**Uma varredura por console, nunca uma por tile.** É o mesmo argumento da Task 8. `identify` é uma chamada que pode calcular CRC, e chamá-la de dentro de um `itemBuilder` significa chamá-la de novo a cada quadro de scroll. Então a varredura roda uma vez, devolve um `Set<String>` de `PackGame.id`, e o tile faz `contains`.

**Enquanto a varredura não termina, ninguém ganha borda.** `AsyncValue.valueOrNull ?? {}` resolve isso sozinho, e é o que a seção 3.1 pede: "não mostra nada enquanto está varrendo". Borda errada é pior que borda ausente.

**Similaridade não pinta borda.** `LocalIdentityService.identify` pode devolver um casamento de tier 3, `MatchTier.fuzzyName`, que vira `MatchConfidence.guess`. Isso serve para sugerir, não para afirmar que o arquivo está no disco. `guess` é descartado aqui. Nome exato, título canônico e CRC entram.

**A borda não se atualiza sozinha quando um download termina.** Isso é deliberado nesta fatia: o gancho ficaria dentro do `task_queue_service` / `download_provider`, que esta fatia não toca (ver a tabela de intocados no topo, que a Task 22 confere com `git diff --stat`). A receita para quando alguém quiser, e são duas linhas, é `ref.invalidate(ownedGameIdsProvider)` no ponto em que o download é marcado como concluído. **Não improvise isso agora**, porque tocar o download provider quebra o critério da Task 22.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/owned_games_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

const _alvo = PackTarget('snes', 'Super Nintendo');

final _pacote = MetadataPack(
  pack: 'snes',
  system: 'Super Nintendo',
  built: '2026-01-01',
  games: [
    PackGame(
      id: 'snes/chrono-trigger',
      title: 'Chrono Trigger',
      dumps: [PackDump(name: 'Chrono Trigger (USA)', crc: 'AABBCCDD')],
    ),
    PackGame(
      id: 'snes/super-metroid',
      title: 'Super Metroid',
      dumps: [PackDump(name: 'Super Metroid (Japan, USA)')],
    ),
  ],
);

/// CRC fixo de propósito: nenhum teste aqui é sobre checksum, e ler o disco
/// para calcular um deixaria o teste lento e dependente do conteúdo do
/// arquivo. `FFFFFFFF` não está no pacote, então o eixo de CRC nunca casa e
/// cada teste mede exatamente o eixo de nome que ele diz medir.
LocalIdentityService _servico() => LocalIdentityService(
      matcher: PackMatcher(_pacote),
      crcOfFile: (_) async => 'FFFFFFFF',
    );

Future<Directory> _pasta() async {
  final dir = await Directory.systemTemp.createTemp('owned_games_test');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

Future<File> _arquivo(Directory dir, String nome) async {
  final file = File(p.join(dir.path, nome));
  await file.parent.create(recursive: true);
  await file.writeAsString('rom');
  return file;
}

ProviderContainer _container({
  required String? libraryDir,
  PackTarget? alvo = _alvo,
  LocalIdentityService? servico,
  bool comServico = true,
}) {
  final container = ProviderContainer(
    overrides: [
      packTargetProvider.overrideWithValue(alvo),
      libraryDirProvider.overrideWithValue(libraryDir),
      if (alvo != null)
        localIdentityServiceProvider(alvo).overrideWith(
          (ref) => comServico ? (servico ?? _servico()) : null,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('sem console selecionado o conjunto é vazio', () async {
    final container = _container(libraryDir: null, alvo: null);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('sem pacote não há identidade, e o conjunto é vazio', () async {
    final dir = await _pasta();
    await _arquivo(dir, 'Chrono Trigger (USA).sfc');
    final container = _container(libraryDir: dir.path, comServico: false);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('pasta que não existe não derruba a varredura', () async {
    final container = _container(libraryDir: p.join(Directory.systemTemp.path, 'nao_existe_mesmo'));

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM que casa pelo nome entra no conjunto', () async {
    final dir = await _pasta();
    await _arquivo(dir, 'Chrono Trigger (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/chrono-trigger'});
  });

  test('o que não é ROM é ignorado', () async {
    final dir = await _pasta();
    await _arquivo(dir, 'Chrono Trigger (USA).txt');
    await _arquivo(dir, 'Super Metroid (Japan, USA).nfo');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM que não casa com nada não entra', () async {
    final dir = await _pasta();
    await _arquivo(dir, 'Um Jogo Que Nao Existe (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM extraída dentro de uma subpasta também conta', () async {
    final dir = await _pasta();
    // É a forma que `extractToFolder` deixa no disco, e é a profundidade que
    // `_scanLibraryDirIsolate` já varre hoje.
    await _arquivo(dir, p.join('Super Metroid (Japan, USA)', 'Super Metroid (Japan, USA).sfc'));
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/super-metroid'});
  });

  test('casamento só por semelhança não conta como baixado', () async {
    final dir = await _pasta();
    // Tier 3: `ratio('chrono triggr', 'chrono trigger')` passa de 90, então
    // o matcher devolve um `fuzzyName`. Bom o bastante para sugerir, não o
    // bastante para pintar borda.
    await _arquivo(dir, 'Chrono Triggr (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/owned_games_provider_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/providers/owned_games_provider.dart'`.

- [ ] **Step 3: Implemente o provider**

Crie `lib/providers/owned_games_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Onde a biblioteca do console selecionado está no disco.
///
/// Existe separado do provider de baixo por um motivo só: é o ponto de
/// injeção do teste. `getDownloadDir` mora no notifier de settings, e o
/// construtor de `SettingsNotifier` lê o disco; sobrescrever este provider é o
/// que permite varrer uma pasta temporária sem subir settings de verdade.
final libraryDirProvider = Provider<String?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  // O `watch` é do estado e a chamada é no notifier. É esse par que faz este
  // provider recalcular quando o usuário troca a pasta nas configurações.
  ref.watch(settingsProvider);
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(target.consoleId);
  return dir.isEmpty ? null : dir;
});

/// Os `PackGame.id` que já têm alguma versão no disco.
///
/// Uma varredura por console, nunca uma por tile: `identify` pode calcular
/// CRC, e chamá-la de dentro de um `itemBuilder` seria chamá-la de novo a
/// cada quadro de scroll. O tile recebe o conjunto pronto e faz `contains`.
final ownedGameIdsProvider = FutureProvider<Set<String>>((ref) async {
  final target = ref.watch(packTargetProvider);
  final dir = ref.watch(libraryDirProvider);
  if (target == null || dir == null) return const <String>{};

  final identity = await ref.watch(localIdentityServiceProvider(target).future);
  if (identity == null) return const <String>{};

  final owned = <String>{};
  for (final file in await _libraryFiles(dir)) {
    if (!hasRomExtension(p.basename(file.path))) continue;
    final match = await identity.identify(file);
    // `guess` é o tier de similaridade, e ele erra. Borda errada é pior que
    // borda ausente (spec de UI, seção 3.1), então só nome exato, título
    // canônico e CRC pintam.
    if (match == null || match.confidence == MatchConfidence.guess) continue;
    owned.add(match.game.id);
  }
  return owned;
});

/// Os arquivos da pasta e de um nível abaixo dela.
///
/// O nível a mais não é capricho: com `extractToFolder` ligado a ROM extraída
/// fica em `<pasta>/<nome do jogo>/`, e `_scanLibraryDirIsolate`
/// (`lib/providers/library_snapshot_provider.dart:273-294`) já conta essa
/// profundidade. Varrer diferente daria duas respostas para "eu já baixei
/// isso?" dentro da mesma tela.
Future<List<File>> _libraryFiles(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return const [];

  final files = <File>[];
  try {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        try {
          await for (final sub in entity.list(followLinks: false)) {
            if (sub is File) files.add(sub);
          }
        } catch (_) {
          // Subpasta sem permissão. Não é motivo para a grade inteira ficar
          // sem borda.
        }
      }
    }
  } catch (_) {
    // Pasta apagada no meio da varredura, pendrive removido, permissão
    // negada. Devolve o que deu para ler.
  }
  return files;
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/owned_games_provider_test.dart
```

Esperado: `+8`, zero falha.

Se o teste da subpasta falhar com o conjunto vazio, confira se `_arquivo` criou o pai: `File.writeAsString` não cria diretório, por isso o helper chama `file.parent.create(recursive: true)` antes.

- [ ] **Step 5: Commit do provider**

```bash
# agente de teste
git add test/owned_games_provider_test.dart
git commit -m "test(grade): varredura da biblioteca devolve os jogos ja baixados"

# agente de producao
git add lib/providers/owned_games_provider.dart
git commit -m "feat(grade): varredura da biblioteca devolve os jogos ja baixados"
```

- [ ] **Step 6: Escreva os testes da grade com borda**

Em `test/pack_grid_test.dart`, troque o helper `_host` inteiro por esta versão, que ganha um parâmetro de jogos já baixados:

```dart
Widget _host(
  List<PackGridEntry> entradas, {
  SourceIndex? indice,
  void Function(PackGridEntry)? onOpenGame,
  Set<String>? baixados,
  bool varrendo = false,
}) {
  return ProviderScope(
    overrides: [
      packGridEntriesProvider.overrideWithValue(entradas),
      sourceIndexProvider.overrideWithValue(indice ?? _indice(casaAlgo: true)),
      ownedGameIdsProvider.overrideWith(
        // Um `Completer` que ninguém completa é a varredura em curso. Um
        // `Future.delayed` deixaria timer pendente e o teste falharia no fim.
        (ref) => varrendo ? Completer<Set<String>>().future : Future.value(baixados ?? const <String>{}),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}
```

Acrescente os dois imports no topo do arquivo:

```dart
import 'dart:async';
import 'package:roms_downloader/providers/owned_games_provider.dart';
```

E acrescente os dois testes no fim de `main`:

```dart
  testWidgets('o jogo que já está no disco vai marcado para o tile', (tester) async {
    await tester.pumpWidget(_host(
      [
        _entrada('snes/chrono-trigger', 'Chrono Trigger'),
        _entrada('snes/super-metroid', 'Super Metroid'),
      ],
      baixados: {'snes/chrono-trigger'},
    ));
    await tester.pump();

    final tiles = tester.widgetList<PackGridItem>(find.byType(PackGridItem)).toList();
    expect(tiles.firstWhere((t) => t.title == 'Chrono Trigger').isOwned, isTrue);
    expect(tiles.firstWhere((t) => t.title == 'Super Metroid').isOwned, isFalse);
  });

  testWidgets('enquanto a varredura não termina ninguém vai marcado', (tester) async {
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger')],
      baixados: {'snes/chrono-trigger'},
      varrendo: true,
    ));
    await tester.pump();

    // Seção 3.1: nada de borda enquanto o scan roda. Borda errada é pior que
    // borda ausente, e neste instante a resposta ainda não existe.
    expect(tester.widget<PackGridItem>(find.byType(PackGridItem)).isOwned, isFalse);
  });
```

- [ ] **Step 7: Rode e veja falhar**

```bash
flutter test test/pack_grid_test.dart
```

Esperado: `+7 -2`. Os sete da Task 12 continuam passando, e os dois novos falham porque `PackGrid` ainda não lê o provider: `Expected: true / Actual: <false>`.

- [ ] **Step 8: Ligue a grade ao provider**

Em `lib/widgets/game_grid/pack_grid.dart`, acrescente o import:

```dart
import 'package:roms_downloader/providers/owned_games_provider.dart';
```

Dentro de `build`, logo depois da linha do `selected`, acrescente:

```dart
    // A varredura da biblioteca (Task 13). `valueOrNull` é o que entrega a
    // regra da seção 3.1 de graça: enquanto ela não resolve, o conjunto é
    // vazio e nenhum tile ganha borda.
    final owned = ref.watch(ownedGameIdsProvider).valueOrNull ?? const <String>{};
```

E no `PackGridItem` do `itemBuilder`, troque a linha de `hasSource` por este par:

```dart
                        hasSource: entry.hasSource,
                        isOwned: owned.contains(entry.game.id),
```

- [ ] **Step 9: Rode e veja passar**

```bash
flutter test test/pack_grid_test.dart
```

Esperado: `+9`, zero falha.

Agora a suíte inteira, porque esta Task fecha o Grupo 3:

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Esperado: `+255 -1`, com a única falha sendo a de sempre, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Qualquer outra falha é regressão desta Task.

- [ ] **Step 10: Commit da ligação**

```bash
# agente de teste
git add test/pack_grid_test.dart
git commit -m "test(grade): grade marca o tile do jogo ja baixado e nada durante a varredura"

# agente de producao
git add lib/widgets/game_grid/pack_grid.dart
git commit -m "feat(grade): grade marca o tile do jogo ja baixado e nada durante a varredura"
```

---

### Task 14: `planFromEntries`, a regra da seção 6

**Files:**
- Modify: `lib/services/source_pick_service.dart` (a função nova convive com `planFromGames`)
- Modify: `test/source_pick_service_test.dart` (os testes novos vão no fim de `main`)

A regra de escolha da seção 6 do spec de UI, na ordem exata dela: região preferida, maior revisão, maior confiança, prioridade do addon. É a mesma regra que vai escolher o destaque da tela de detalhe na Task 15. **Uma regra só, dois lugares**, e o lugar dela é este arquivo.

**De onde saem região e revisão.** `MatchedSource` não carrega nenhuma das duas, e isso é de propósito: um addon devolve nome de arquivo e nada mais (decisão travada da fatia 4, "o addon é burro"). Quem extrai as duas do nome é `TitleMetadataParser.parseRomTitle`, que já existe, já é Dart puro e já é o parser que a listagem inteira usa. Conferido rodando, não por leitura:

| Nome | `regions` | `revision` |
| --- | --- | --- |
| `Chrono Trigger (USA).zip` | `[USA]` | `''` |
| `Chrono Trigger (Japan).zip` | `[Japan]` | `''` |
| `Chrono Trigger (USA) (Rev A).zip` | `[USA]` | `'A'` |
| `Super Metroid (Japan, USA) (En,Ja).zip` | `[Japan, USA]` | `''` |
| `Chrono Trigger (World).zip` | `[World]` | `''` |

**Duas heranças que você não vai consertar aqui.** A primeira: `World` não é tratado como coringa, então contra um filtro `{'USA'}` uma ROM `(World)` perde de uma `(USA)`. A segunda: revisão é comparada com `compareTo` de string, então `Rev A` ganha de `Rev 1` porque `'A' > '1'` na tabela de caracteres. As duas vêm de `filtering_service.dart:61-65` e `:151-157`, valem para a grade de hoje, e mudar qualquer uma delas aqui faria a grade e o lote discordarem sobre o mesmo arquivo. Essa discordância é pior que as duas heranças juntas. Se algum dia forem consertadas, é lá, e as duas ao mesmo tempo.

**Por que a função pede um resolvedor de `Game`.** `SourcePick.game` é o que efetivamente entra na fila, e `TaskQueueService.startDownloads` só sabe lidar com `Game`. Um `MatchedSource` não é um `Game`: nesta fatia ele veio de um, mas na fatia 4 vem de um addon. Em vez de sintetizar um `Game` aqui, e perder `details` e o `gameId` que a fila já usa, a função recebe `resolveGame` e quem chama decide como resolver. Na Task 20 é um mapa por nome de arquivo montado sobre o catálogo; na fatia 4 é o addon.

**Prioridade de addon nesta fatia é o eixo morto.** Só existe uma fonte, `kBuiltinSourceId`, então `sourcePriority` fica no padrão vazio e o eixo nunca decide nada. Ele está aqui porque a seção 6 o lista e porque implementá-lo depois significaria mexer no comparador de novo, com a regra já em produção em dois lugares.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao topo de `test/source_pick_service_test.dart` os imports que faltam:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
```

Acrescente os helpers logo abaixo do `_game` que já está lá:

```dart
MatchedSource _fonte(
  String filename, {
  MatchConfidence confianca = MatchConfidence.likely,
  String sourceId = 'listagem',
  int size = 1000,
}) =>
    MatchedSource(filename: filename, sourceId: sourceId, confidence: confianca, size: size);

PackGridEntry _entrada(String title, List<MatchedSource> fontes) => PackGridEntry(
      game: PackGame(id: 'snes/${title.toLowerCase()}', title: title, dumps: [PackDump(name: title)]),
      sources: fontes,
    );

/// O resolvedor do teste: todo nome de arquivo resolve, e o `Game` que sai é
/// reconhecível pelo nome. A Task 20 troca isto por um mapa sobre o catálogo.
Game? _resolve(MatchedSource source) => _game(source.filename, source.size);

BatchPlan _plano(
  List<PackGridEntry> entradas, {
  Set<String> regioes = const {'USA'},
  List<String> prioridade = const [],
  GameResolver? resolver,
}) =>
    planFromEntries(
      entradas,
      preferredRegions: regioes,
      resolveGame: resolver ?? _resolve,
      sourcePriority: prioridade,
    );
```

E os testes no fim de `main`:

```dart
  test('com uma fonte só, o motivo diz que não houve escolha', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [_fonte('Chrono Trigger (Japan).zip')]),
    ]);

    expect(plan.picks.single.filename, 'Chrono Trigger (Japan).zip');
    expect(plan.picks.single.reason, 'é a única fonte que tem este jogo');
    // A região não é preferida e mesmo assim a fonte foi escolhida: a regra
    // ordena candidatos, ela não descarta nenhum.
    expect(plan.failures, isEmpty);
  });

  test('a região preferida ganha, e o motivo nomeia a região', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [
        _fonte('Chrono Trigger (Japan).zip'),
        _fonte('Chrono Trigger (USA).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Chrono Trigger (USA).zip');
    expect(plan.picks.single.reason, 'escolhido pela sua região preferida (USA)');
  });

  test('com o filtro de região vazio o eixo é neutro e a revisão decide', () {
    final plan = _plano(
      [
        _entrada('Chrono Trigger', [
          _fonte('Chrono Trigger (USA).zip'),
          _fonte('Chrono Trigger (Japan) (Rev A).zip'),
        ]),
      ],
      regioes: const {},
    );

    expect(plan.picks.single.filename, 'Chrono Trigger (Japan) (Rev A).zip');
    expect(plan.picks.single.reason, 'é a revisão mais nova (Rev A)');
  });

  test('o arquivo sem tag de região não perde do preferido', () {
    // Espelha `filtering_service.dart:61-65`, onde metadados sem região
    // passam pelo filtro em vez de serem descartados.
    final plan = _plano([
      _entrada('Chrono Trigger', [
        _fonte('Chrono Trigger.zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Chrono Trigger.zip');
  });

  test('na mesma região, a revisão maior ganha', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (USA) (Rev A).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Chrono Trigger (USA) (Rev A).zip');
    expect(plan.picks.single.reason, 'é a revisão mais nova (Rev A)');
  });

  test('empatadas região e revisão, a confiança maior ganha', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [
        _fonte('Chrono Trigger (USA).zip', confianca: MatchConfidence.guess),
        _fonte('Chrono Trigger (USA).zip', confianca: MatchConfidence.confirmed),
      ]),
    ]);

    expect(plan.picks.single.reason, 'é o casamento mais confiável entre as 2 fontes');
    expect(plan.picks.single.uncertain, isFalse);
  });

  test('empatado o resto, a prioridade do addon decide', () {
    final plan = _plano(
      [
        _entrada('Chrono Trigger', [
          _fonte('Chrono Trigger (USA).zip', sourceId: 'lento'),
          _fonte('Chrono Trigger (USA).zip', sourceId: 'rapido'),
        ]),
      ],
      prioridade: const ['rapido', 'lento'],
    );

    expect(plan.picks.single.reason, 'vem do addon de maior prioridade');
  });

  test('empate em tudo fica com a primeira, e o motivo admite o empate', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [
        _fonte('Chrono Trigger (USA).zip', size: 10),
        _fonte('Chrono Trigger (USA).zip', size: 20),
      ]),
    ]);

    expect(plan.picks.single.size, 10);
    expect(plan.picks.single.reason, 'empate entre 2 fontes, ficou a primeira');
  });

  test('a escolha por palpite vai marcada como incerta', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [_fonte('Chrono Trigger (USA).zip', confianca: MatchConfidence.guess)]),
    ]);

    // O lote não verifica CRC antes de enfileirar (seção 6). Ele marca.
    expect(plan.picks.single.uncertain, isTrue);
  });

  test('o jogo sem fonte vira falha, não escolha', () {
    final plan = _plano([
      _entrada('Chrono Trigger', [_fonte('Chrono Trigger (USA).zip')]),
      _entrada('EarthBound', const []),
    ]);

    expect(plan.picks.map((p) => p.title), ['Chrono Trigger']);
    expect(plan.failures.single.title, 'EarthBound');
    expect(plan.failures.single.gameId, 'pack:snes/earthbound');
    expect(plan.failures.single.reason, 'nenhuma fonte instalada tem este jogo');
  });

  test('o jogo cujas fontes não resolvem vira falha com outro motivo', () {
    final plan = _plano(
      [
        _entrada('Chrono Trigger', [_fonte('Chrono Trigger (USA).zip')]),
      ],
      resolver: (_) => null,
    );

    expect(plan.picks, isEmpty);
    expect(plan.failures.single.reason, 'a fonte saiu da listagem antes de a fila começar');
  });
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `The function 'planFromEntries' isn't defined` e `Undefined class 'GameResolver'`.

- [ ] **Step 3: Implemente**

Acrescente a `lib/services/source_pick_service.dart`. Os imports novos, no topo:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_metadata_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';
```

E o corpo, abaixo de `planFromGames`:

```dart
/// Como quem chama transforma uma fonte no `Game` que vai para a fila.
///
/// Nesta fatia é uma busca no catálogo por nome de arquivo (Task 20). Na
/// fatia 4 é o addon que responde. Devolve `null` quando a fonte não existe
/// mais, e aí o jogo vira `PickFailure` em vez de escolha.
typedef GameResolver = Game? Function(MatchedSource source);

typedef _Candidate = ({MatchedSource source, GameMetadata meta, Game game, int order});

/// A regra de escolha da seção 6 do spec de UI, na ordem dela: região
/// preferida, maior revisão, maior confiança, prioridade do addon.
///
/// É a mesma regra que escolhe o destaque da tela de detalhe. Uma regra só,
/// dois lugares: se você precisar de uma variação, mude esta função, não
/// escreva outra.
BatchPlan planFromEntries(
  List<PackGridEntry> entries, {
  required Set<String> preferredRegions,
  required GameResolver resolveGame,
  List<String> sourcePriority = const [],
}) {
  final picks = <SourcePick>[];
  final failures = <PickFailure>[];

  for (final entry in entries) {
    if (entry.sources.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'nenhuma fonte instalada tem este jogo',
      ));
      continue;
    }

    final candidates = <_Candidate>[];
    for (var i = 0; i < entry.sources.length; i++) {
      final source = entry.sources[i];
      final game = resolveGame(source);
      if (game == null) continue;
      candidates.add((
        source: source,
        meta: TitleMetadataParser.parseRomTitle(source.filename),
        game: game,
        order: i,
      ));
    }

    if (candidates.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'a fonte saiu da listagem antes de a fila começar',
      ));
      continue;
    }

    candidates.sort((a, b) => _compare(a, b, preferredRegions, sourcePriority));
    final winner = candidates.first;

    picks.add(SourcePick(
      gameId: entry.selectionKey,
      title: entry.game.title,
      filename: winner.source.filename,
      size: winner.source.size,
      sourceId: winner.source.sourceId,
      reason: _reason(winner, candidates, preferredRegions, sourcePriority),
      // O lote não verifica CRC antes de enfileirar (seção 6): ele marca o
      // palpite e deixa a rede de segurança para a verificação pós-download.
      uncertain: winner.source.confidence == MatchConfidence.guess,
      game: winner.game,
    ));
  }

  return BatchPlan(picks: picks, failures: failures);
}

int _compare(_Candidate a, _Candidate b, Set<String> preferred, List<String> priority) {
  final region = _regionRank(a, preferred).compareTo(_regionRank(b, preferred));
  if (region != 0) return region;

  // Invertido de propósito: revisão maior vem primeiro.
  final revision = _compareRevision(b.meta.revision, a.meta.revision);
  if (revision != 0) return revision;

  // `MatchConfidence` está declarado do mais confiável para o menos, então
  // o índice menor é o melhor.
  final confidence = a.source.confidence.index.compareTo(b.source.confidence.index);
  if (confidence != 0) return confidence;

  final addon = _priorityRank(a, priority).compareTo(_priorityRank(b, priority));
  if (addon != 0) return addon;

  // O desempate final é a ordem de chegada. Está aqui porque `List.sort` não
  // promete estabilidade, e um lote que muda de resultado entre duas rodadas
  // com a mesma entrada seria impossível de reportar como bug.
  return a.order.compareTo(b.order);
}

/// 0 é preferida, 1 não é.
///
/// Sem região no nome o candidato **não** perde, o que espelha
/// `filtering_service.dart:61-65`, onde metadados sem região passam pelo
/// filtro em vez de serem descartados.
int _regionRank(_Candidate candidate, Set<String> preferred) {
  if (preferred.isEmpty) return 0;
  if (candidate.meta.regions.isEmpty) return 0;
  return candidate.meta.regions.any(preferred.contains) ? 0 : 1;
}

/// Positivo quando [a] é mais nova que [b].
///
/// Comparação lexical, igual à de `filtering_service.dart:151-157`, com a
/// mesma limitação conhecida: `Rev A` ganha de `Rev 1`, e `1.10` perde de
/// `1.2`. Divergir daqui faria a grade e o lote discordarem.
int _compareRevision(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  return a.compareTo(b);
}

int _priorityRank(_Candidate candidate, List<String> priority) {
  final index = priority.indexOf(candidate.source.sourceId);
  return index < 0 ? priority.length : index;
}

/// O motivo por extenso, que é o eixo em que o vencedor bateu o segundo
/// colocado. Obrigatório, não decorativo: é a única coisa que separa "o app
/// escolheu por você" de "o app escolheu ao acaso" (seção 7).
String _reason(
  _Candidate winner,
  List<_Candidate> ordered,
  Set<String> preferred,
  List<String> priority,
) {
  if (ordered.length == 1) return 'é a única fonte que tem este jogo';
  final runnerUp = ordered[1];

  if (_regionRank(winner, preferred) != _regionRank(runnerUp, preferred)) {
    final region = winner.meta.regions.where(preferred.contains).firstOrNull;
    return region == null
        ? 'escolhido pela sua região preferida'
        : 'escolhido pela sua região preferida ($region)';
  }

  // Se as revisões diferem, a do vencedor é a maior, senão ele não seria o
  // vencedor. Por isso dá para nomeá-la sem checar de novo.
  if (_compareRevision(winner.meta.revision, runnerUp.meta.revision) != 0) {
    return 'é a revisão mais nova (Rev ${winner.meta.revision})';
  }

  if (winner.source.confidence != runnerUp.source.confidence) {
    return 'é o casamento mais confiável entre as ${ordered.length} fontes';
  }

  if (_priorityRank(winner, priority) != _priorityRank(runnerUp, priority)) {
    return 'vem do addon de maior prioridade';
  }

  return 'empate entre ${ordered.length} fontes, ficou a primeira';
}
```

`firstOrNull` **não** precisa de import. Conferido rodando um arquivo Dart sem import nenhum: `<String>[].firstOrNull` compila e devolve `null`. É o mesmo uso de `game_model.dart:90`, que também não importa `package:collection`.

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `+15`, zero falha. São os 4 da Task 6 mais os 11 desta.

Se o teste do empate total falhar escolhendo a segunda fonte, o culpado é o desempate por `order`: confira que ele é a **última** linha de `_compare` e que `order` é o índice do laço, não o índice depois do `sort`.

- [ ] **Step 5: Commit**

```bash
# agente de teste
git add test/source_pick_service_test.dart
git commit -m "test(lote): regra de escolha por regiao, revisao, confianca e prioridade"

# agente de producao
git add lib/services/source_pick_service.dart
git commit -m "feat(lote): regra de escolha por regiao, revisao, confianca e prioridade"
```

---

# Grupo 4: a tela de detalhe

Aqui a fatia deixa de ser grade e passa a ser a tela que justifica a grade. As três Tasks deste grupo são a seção 7 do spec de UI, e nenhuma delas toca em rede: a verificação por CRC da seção 8 é o Grupo 5.

---

### Task 15: a tela de detalhe, caso comum

**Files:**
- Create: `lib/screens/game_detail_screen.dart`
- Create: `test/game_detail_screen_test.dart`
- Modify: `lib/providers/pack_grid_provider.dart` (dois providers novos no fim)
- Modify: `test/pack_grid_provider_test.dart` (dois testes novos no fim)

A tela da seção 7: topo com capa, título, metadados, sinopse, coração e checkbox; corpo com o card de destaque, o motivo por extenso e o botão Baixar.

**A tela não conhece a fila.** `onDownload` é um callback, pelo mesmo motivo que `PackGrid.onOpenGame` é um callback: `TaskQueueService.startDownloads` puxa o pipeline inteiro de download, e uma tela que o chama direto não se testa. Quem liga os dois é o `HomeScreen`, na Task 19.

**A tela não escolhe a versão sozinha.** Ela chama `planFromEntries` com uma entrada só. É literalmente a regra do lote, e é isso que a seção 6 quer dizer com "uma regra só, dois lugares". Se o destaque da tela e a escolha do lote divergirem algum dia, o bug é um só e o conserto é num arquivo só.

**A chave de favorito em MODO PACK é `entry.selectionKey`**, com o prefixo `pack:`. Favorito de MODO FONTE continua sendo `Game.gameId`. Os dois convivem no mesmo `Set` do `favorites_model.dart`, e é exatamente para isso que o prefixo existe (ver a "Quarta decisão travada").

**O que esta Task deliberadamente não desenha:** a faixa de "sem fonte" e a lista de "outras N fontes". As duas são a Task 16. Aqui, quando não há escolha, o card simplesmente não aparece, e um teste prova isso, para a Task 16 ter onde encaixar a faixa.

- [ ] **Step 1: Escreva os dois testes de provider que falham**

No fim de `main` em `test/pack_grid_provider_test.dart`:

```dart
  test('o resolvedor acha o jogo do catálogo pelo nome do arquivo', () async {
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')]);
    await _pronto(container);

    final resolver = container.read(gameResolverProvider);
    final achado = resolver(const MatchedSource(
      filename: 'Chrono Trigger (USA).zip',
      sourceId: kBuiltinSourceId,
      confidence: MatchConfidence.likely,
      size: 2048,
    ));

    expect(achado?.filename, 'Chrono Trigger (USA).zip');
  });

  test('o resolvedor devolve nulo para uma fonte que não está no catálogo', () async {
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')]);
    await _pronto(container);

    final resolver = container.read(gameResolverProvider);
    final achado = resolver(const MatchedSource(
      filename: 'Um Jogo Que Saiu Da Listagem.zip',
      sourceId: kBuiltinSourceId,
      confidence: MatchConfidence.likely,
      size: 10,
    ));

    // É o caminho que vira `PickFailure` na Task 14, e ele tem que existir de
    // verdade, senão o lote quebraria com um `null check` no primeiro catálogo
    // recarregado durante uma seleção.
    expect(achado, isNull);
  });
```

Acrescente ao topo do arquivo os imports que faltam:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `Undefined name 'gameResolverProvider'`.

- [ ] **Step 3: Implemente os dois providers**

No fim de `lib/providers/pack_grid_provider.dart`:

```dart
/// A região preferida do usuário, lida do filtro que já existe.
///
/// É seam de teste, como `catalogGamesProvider` e `gridSearchQueryProvider`:
/// sobrescreva **este** provider nos testes, nunca o `catalogProvider`.
final preferredRegionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(catalogProvider.select((state) => state.filter.regions));
});

/// Como uma fonte vira o `Game` que entra na fila.
///
/// Nesta fatia toda fonte veio da listagem do console, então resolver é achar
/// de volta o `Game` pelo nome do arquivo. Na fatia 4 quem responde é o addon,
/// e este provider passa a consultá-lo. `planFromEntries` não precisa saber
/// de nenhum dos dois.
final gameResolverProvider = Provider<GameResolver>((ref) {
  final byFilename = <String, Game>{};
  for (final game in ref.watch(catalogGamesProvider)) {
    // `putIfAbsent`: se dois arquivos da listagem tiverem o mesmo nome, o
    // primeiro do catálogo vence, que é a mesma ordem que `SourceIndex.build`
    // já usa. Duas respostas diferentes para o mesmo nome seria pior.
    byFilename.putIfAbsent(game.filename, () => game);
  }
  return (source) => byFilename[source.filename];
});
```

O import novo, no topo do arquivo:

```dart
import 'package:roms_downloader/services/source_pick_service.dart';
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `+9`, zero falha. São os 7 da Task 10 mais os 2 desta.

- [ ] **Step 5: Escreva o teste da tela, que falha**

Crie `test/game_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';

const _alvo = PackTarget('snes', 'Super Nintendo');

PackGame _pg() => const PackGame(
      id: 'snes/chrono-trigger',
      title: 'Chrono Trigger',
      dumps: [PackDump(name: 'Chrono Trigger (USA)')],
      synopsis: 'Um garoto, uma feira e uma máquina do tempo.',
      genre: 'RPG',
      publisher: 'Square',
      year: 1995,
    );

// Sem `cover` de propósito em todo teste: com URL, o `CachedNetworkImage`
// tentaria rede dentro do teste.
PackGridEntry _entrada({List<MatchedSource> fontes = const []}) =>
    PackGridEntry(game: _pg(), sources: fontes);

MatchedSource _fonte(String filename, {int size = 4 * 1024 * 1024}) => MatchedSource(
      filename: filename,
      sourceId: kBuiltinSourceId,
      confidence: MatchConfidence.likely,
      size: size,
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://exemplo.org/snes/$filename',
      size: 4 * 1024 * 1024,
      consoleId: 'snes',
    );

Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
}) {
  return ProviderScope(
    overrides: [
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entrada, onDownload: onDownload ?? (_) {}),
    ),
  );
}

void main() {
  testWidgets('mostra título, sistema, ano, publisher e gênero', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.text('Chrono Trigger'), findsWidgets);
    expect(find.text('Super Nintendo, 1995, Square, RPG'), findsOneWidget);
  });

  testWidgets('mostra a sinopse', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.text('Um garoto, uma feira e uma máquina do tempo.'), findsOneWidget);
  });

  testWidgets('o card de destaque traz arquivo, tamanho e motivo', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    expect(find.text('Chrono Trigger (USA).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listagem'), findsOneWidget);
    // O motivo é obrigatório, não decorativo (seção 7).
    expect(find.text('escolhido pela sua região preferida (USA)'), findsOneWidget);
  });

  testWidgets('o botão Baixar devolve a escolha inteira', (tester) async {
    final baixados = <String>[];
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      onDownload: (pick) => baixados.add(pick.game.filename),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Baixar'));
    await tester.pump();

    // O `Game` que sai do callback é o que a fila entende, não um sintético.
    expect(baixados, ['Chrono Trigger (USA).zip']);
  });

  testWidgets('sem fonte a tela abre inteira e sem card de destaque', (tester) async {
    await tester.pumpWidget(_host(_entrada()));

    // Os 3% da seção 3.1: o jogo continua existindo e continua favoritável.
    expect(find.text('Um garoto, uma feira e uma máquina do tempo.'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNothing);
  });

  testWidgets('o coração alterna o favorito', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('o checkbox alterna a seleção pela chave de pack', (tester) async {
    late WidgetRef capturado;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        packTargetProvider.overrideWithValue(_alvo),
        preferredRegionsProvider.overrideWithValue(const {'USA'}),
        gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturado = ref;
          return GameDetailScreen(
            entry: _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
            onDownload: (_) {},
          );
        }),
      ),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(
      capturado.read(catalogProvider).selectedGames,
      contains('pack:snes/chrono-trigger'),
    );
  });
}
```

- [ ] **Step 6: Rode e veja falhar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `Target of URI doesn't exist: '.../game_detail_screen.dart'`.

- [ ] **Step 7: Implemente a tela**

Crie `lib/screens/game_detail_screen.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// A tela da seção 7 do spec de UI: um jogo, as fontes dele e o motivo da
/// escolha.
///
/// Não é bottom sheet e não é expansão inline. É rota.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// O que fazer quando o usuário aperta Baixar.
  ///
  /// A tela não conhece a fila, pelo mesmo motivo que `PackGrid` não conhece
  /// `Navigator`: `TaskQueueService.startDownloads` puxa o pipeline inteiro de
  /// download, e uma tela que o chama direto não se testa. Quem liga os dois é
  /// o `HomeScreen`.
  final void Function(SourcePick pick) onDownload;

  const GameDetailScreen({super.key, required this.entry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final chave = entry.selectionKey;
    final favorito = ref.watch(favoritesProvider).isFavorite(chave);
    final selecionado = ref.watch(catalogProvider.select((s) => s.selectedGames)).contains(chave);

    // A mesma regra do lote, com uma entrada só. Seção 6: uma regra só, dois
    // lugares. Não escreva uma escolha diferente aqui.
    final plan = planFromEntries(
      [entry],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: ref.watch(gameResolverProvider),
    );
    final pick = plan.picks.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorito ? 'Tirar dos favoritos' : 'Favoritar',
            icon: Icon(
              favorito ? Icons.favorite : Icons.favorite_border,
              color: favorito ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(chave),
          ),
          Checkbox(
            value: selecionado,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(chave),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Topo(game: game, sistema: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (pick != null) ...[
            const SizedBox(height: 16),
            _Destaque(pick: pick, onDownload: () => onDownload(pick)),
          ],
        ],
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  final PackGame game;
  final String sistema;

  const _Topo({required this.game, required this.sistema});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Só o que existe entra na linha, senão sobra vírgula solta num jogo sem
    // ano ou sem publisher, que é a maioria dos homebrews.
    final ficha = [
      sistema,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((parte) => parte.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _capa(context),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(ficha, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _capa(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videogame_asset_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorListener: (_) {},
    );
  }
}

/// O card da versão escolhida. O motivo é a linha que não pode faltar.
class _Destaque extends StatelessWidget {
  final SourcePick pick;
  final VoidCallback onDownload;

  const _Destaque({required this.pick, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pick.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)}, ${pick.sourceId}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(pick.reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDownload, child: const Text('Baixar')),
          ),
        ],
      ),
    );
  }
}
```

`pick.sourceId` é o campo que a Task 4 já criou em `SourcePick` e que a Task 14 já preenche com `winner.source.sourceId`. Ele é a origem da linha "4.0 MB, Myrient" da seção 7. Nesta fatia ele sai sempre como `listagem`, porque só existe uma fonte, e é justamente por isso que ele é campo e não texto fixo.

- [ ] **Step 8: Rode e veja passar**

```bash
flutter test test/game_detail_screen_test.dart test/source_pick_model_test.dart test/source_pick_service_test.dart test/pack_grid_provider_test.dart
```

Esperado: `+37`, zero falha. São 7 desta tela, 6 do modelo, 15 do serviço e 9 dos providers.

Tropeço provável: se `find.text('Chrono Trigger')` achar mais de um widget no primeiro teste, é o título no `AppBar` mais o título no topo. Por isso o teste usa `findsWidgets` e não `findsOneWidget`.

- [ ] **Step 9: Commit**

```bash
# agente de teste
git add test/game_detail_screen_test.dart test/pack_grid_provider_test.dart
git commit -m "test(detalhe): tela de detalhe com destaque, motivo, favorito e selecao"

# agente de producao
git add lib/screens/game_detail_screen.dart lib/providers/pack_grid_provider.dart
git commit -m "feat(detalhe): tela de detalhe com destaque, motivo, favorito e selecao"
```

---

### Task 16: a faixa de "sem fonte" e a lista de "outras N fontes"

**Files:**
- Modify: `lib/screens/game_detail_screen.dart`
- Modify: `test/game_detail_screen_test.dart`

Os dois pedaços que a Task 15 deixou de fora, e que fecham a seção 7 do spec de UI: a faixa que aparece no lugar do card quando nenhuma fonte tem o jogo, e a lista colapsada com as fontes que perderam o destaque.

**A faixa não escreve texto próprio.** Ela mostra `plan.failures.first.reason`, que é a mesma string que a folha de lote mostra para o mesmo jogo. Se um dia a regra passar a distinguir mais casos, os dois lugares mudam juntos, de graça. É a "uma regra só, dois lugares" da seção 6 aplicada também ao fracasso.

**A faixa ainda não tem o atalho para a tela de addons** que a seção 7 pede. A tela de addons é a fatia 4, e um botão que não navega para lugar nenhum é pior do que a ausência dele. Quando a fatia 4 criar a tela, o atalho entra aqui, dentro de `_SemFonte`.

**As linhas da lista não têm botão Baixar.** A seção 8 pede botão por linha só no estado "verificação impossível", que é a Task 18. Aqui a lista é informativa: ela existe para o usuário conferir que o app viu as outras fontes e escolheu com critério.

**O tipo de fonte é `HTTP` fixo nesta fatia.** Toda fonte vem da listagem do console, que é HTTP e nada mais. `SEED` e `RD` chegam quando o addon declarar o tipo, na fatia 4 e na 6. A constante existe para o dia em que o valor deixar de ser um só.

**Cuidado com a palavra "confiança" nas linhas.** O rótulo da linha é a confiança do **casamento** (`MatchConfidence`, da fatia 2), não a verificação por CRC. Ver a "Segunda decisão travada" no topo: são dois eixos e eles não se misturam. A Task 18 acrescenta o estado de CRC como um quinto pedaço da mesma linha, sem tirar este.

- [ ] **Step 1: Ajuste os dois helpers do arquivo de teste**

Em `test/game_detail_screen_test.dart`, `_fonte` precisa saber variar a confiança e `_host` precisa saber trocar o resolvedor. Substitua `_fonte` e `_host` inteiros por estes:

```dart
MatchedSource _fonte(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confianca = MatchConfidence.likely,
}) =>
    MatchedSource(
      filename: filename,
      sourceId: kBuiltinSourceId,
      confidence: confianca,
      size: size,
    );

// Função de topo, e não variável com lambda, por causa do lint
// `prefer_function_declarations_over_variables`, que vem ligado no
// `flutter_lints`.
Game? _resolvePadrao(MatchedSource source) => _game(source.filename);

Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  GameResolver? resolver,
}) {
  return ProviderScope(
    overrides: [
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolvePadrao),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entrada, onDownload: onDownload ?? (_) {}),
    ),
  );
}
```

E acrescente o import que falta, no topo:

```dart
import 'package:roms_downloader/services/source_pick_service.dart';
```

Os sete testes da Task 15 continuam chamando `_fonte('x.zip')` e `_host(entrada)` sem parâmetro nomeado nenhum, então nenhum deles muda.

- [ ] **Step 2: Escreva os onze testes que faltam**

No fim de `main`, no mesmo arquivo:

```dart
  testWidgets('sem fonte, a faixa diz por que não há de onde baixar', (tester) async {
    await tester.pumpWidget(_host(_entrada()));

    // A mesma string que a folha de lote mostra para o mesmo jogo. Se você
    // acabou de escrever um texto novo aqui, ele já existe em
    // `source_pick_service.dart` e tem que sair de lá.
    expect(find.text('nenhuma fonte instalada tem este jogo'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNothing);
  });

  testWidgets('quando a fonte não resolve, a faixa usa o outro motivo', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      resolver: (_) => null,
    ));

    expect(find.text('a fonte saiu da listagem antes de a fila começar'), findsOneWidget);
  });

  testWidgets('sem pick, a fonte que não resolveu ainda aparece na lista', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      resolver: (_) => null,
    ));

    // Nada foi escolhido, então nenhuma fonte é "a outra". Mesmo assim a
    // lista abre: esconder o que existe deixaria a faixa parecendo mentira.
    expect(find.text('outra fonte'), findsOneWidget);
  });

  testWidgets('com uma fonte só, não existe lista de outras fontes', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    // Este teste passa antes e depois da implementação. Ele não é uma trava
    // de implementação, é uma trava contra a lista aparecer vazia depois.
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('com três fontes, o contador diz outras 2 fontes', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
      _fonte('Chrono Trigger (Europe).zip'),
    ])));

    expect(find.text('outras 2 fontes'), findsOneWidget);
  });

  testWidgets('com duas fontes, o contador vai no singular', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    // "outras 1 fontes" seria o texto que sai de um contador escrito sem
    // pensar, e o spec de UI escreve contadores em português.
    expect(find.text('outra fonte'), findsOneWidget);
  });

  testWidgets('a lista começa fechada', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    expect(find.text('outra fonte'), findsOneWidget);
    expect(find.text('Chrono Trigger (Japan).zip'), findsNothing);
  });

  testWidgets('expandida, cada linha traz arquivo, tamanho, addon, tipo e confiança', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    expect(find.text('Chrono Trigger (Japan).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listagem, HTTP, casamento provável'), findsOneWidget);
  });

  testWidgets('a linha de palpite mostra o casamento no chute', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (USA).zip'),
      _fonte('Chrono Trigger (Japan).zip', confianca: MatchConfidence.guess),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    // É a confiança do casamento, não o CRC. Ver a "Segunda decisão travada".
    expect(find.text('4.0 MB, listagem, HTTP, casamento no chute'), findsOneWidget);
  });

  testWidgets('duas fontes idênticas: a escolhida sai da lista uma vez só', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (USA).zip', size: 10),
      _fonte('Chrono Trigger (USA).zip', size: 20),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    // A de 10 bytes venceu pelo desempate de ordem (Task 14). Se a lista
    // tirasse todas as fontes de mesmo nome, a de 20 sumiria junto e o
    // usuário perderia uma fonte real de vista.
    expect(find.text('10.0 B, listagem'), findsOneWidget);
    expect(find.text('20.0 B, listagem, HTTP, casamento provável'), findsOneWidget);
  });

  testWidgets('o card de destaque marca o tipo da fonte', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    // O `HTTP` do canto direito do mockup da seção 7. Com uma fonte só não há
    // lista, então este é o único `HTTP` da tela.
    expect(find.text('HTTP'), findsOneWidget);
  });
```

- [ ] **Step 3: Rode e veja falhar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `+8 -10`. Passam os 7 da Task 15 mais o `com uma fonte só, não existe lista de outras fontes`, que é o teste que já passava antes de propósito. Os dez outros falham com `Expected: exactly one matching candidate` e `Actual: _TextFinder:<zero widgets with text ...>`, e os dois que dão `tap` falham antes disso, no próprio `tap`, porque não existe o que tocar.

- [ ] **Step 4: Implemente**

Em `lib/screens/game_detail_screen.dart`, acrescente o import de `MatchConfidence`, no topo:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
```

Dentro de `build`, logo abaixo da linha `final pick = plan.picks.firstOrNull;`:

```dart
    // Uma entrada só entra em `planFromEntries`, e ela sai como exatamente uma
    // escolha ou exatamente uma falha. O `else if` lá embaixo existe para não
    // haver um `.first` numa lista que o compilador não garante.
    final falha = plan.failures.firstOrNull;
    final outras = _outrasFontes(entry, pick);
```

E substitua a lista `children:` do `ListView` inteira por esta:

```dart
        children: [
          _Topo(game: game, sistema: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (pick != null) ...[
            const SizedBox(height: 16),
            _Destaque(pick: pick, onDownload: () => onDownload(pick)),
          ] else if (falha != null) ...[
            const SizedBox(height: 16),
            _SemFonte(reason: falha.reason),
          ],
          if (outras.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OutrasFontes(sources: outras),
          ],
        ],
```

No `_Destaque`, substitua a primeira linha da `Column`, a que hoje é `Text(pick.filename, ...)`, por esta `Row`:

```dart
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pick.filename,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _kTipoFonte,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
```

E acrescente, no fim do arquivo:

```dart
/// O tipo de fonte, que nesta fatia é um só.
///
/// Toda fonte vem da listagem HTTP do console. `SEED` e `RD` da seção 7 do
/// spec de UI chegam quando o addon declarar o tipo (fatia 4 e fatia 6). É
/// constante em vez de literal solto para o dia em que virar campo.
const _kTipoFonte = 'HTTP';

/// As fontes que não ganharam o destaque, na ordem em que a fonte as deu.
///
/// Tira **uma** cópia da vencedora, não todas as de mesmo nome: duas fontes
/// podem servir arquivos homônimos de tamanhos diferentes, e sumir com as duas
/// esconderia uma fonte real. Sem escolha nenhuma, devolve tudo, porque aí
/// nenhuma delas é "a outra" e esconder o que existe deixaria a faixa de
/// "sem fonte" parecendo mentira.
List<MatchedSource> _outrasFontes(PackGridEntry entry, SourcePick? pick) {
  if (pick == null) return entry.sources;

  final outras = <MatchedSource>[];
  var jaTirou = false;
  for (final source in entry.sources) {
    final ehAVencedora = !jaTirou &&
        source.filename == pick.filename &&
        source.size == pick.size &&
        source.sourceId == pick.sourceId;
    if (ehAVencedora) {
      jaTirou = true;
      continue;
    }
    outras.add(source);
  }
  return outras;
}

String _rotuloOutras(int quantas) => quantas == 1 ? 'outra fonte' : 'outras $quantas fontes';

/// A confiança do **casamento**, que não é a verificação por CRC.
///
/// Ver a "Segunda decisão travada" do plano da fatia 3: são dois eixos e eles
/// não se misturam. A Task 18 acrescenta o estado de CRC como mais um pedaço
/// da mesma linha, sem tirar este.
String _rotuloConfianca(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'casamento confirmado',
      MatchConfidence.likely => 'casamento provável',
      MatchConfidence.guess => 'casamento no chute',
    };

/// A faixa que substitui o card quando não há o que baixar.
///
/// O texto vem de `PickFailure.reason`, ou seja da mesma regra que a folha de
/// lote usa. A tela não inventa motivo próprio.
///
/// Falta aqui o atalho para a tela de addons que a seção 7 pede. A tela de
/// addons é a fatia 4; quando ela existir, o botão entra neste widget.
class _SemFonte extends StatelessWidget {
  final String reason;

  const _SemFonte({required this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// A lista colapsada da seção 7. Informativa: o botão Baixar por linha é o
/// estado "verificação impossível" da seção 8, que é a Task 18.
class _OutrasFontes extends StatelessWidget {
  final List<MatchedSource> sources;

  const _OutrasFontes({required this.sources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` desenha uma divisória em cima e outra embaixo assim
      // que abre, e dentro de um `ListView` de cards isso vira duas linhas
      // soltas no meio da tela.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _rotuloOutras(sources.length),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [for (final source in sources) _LinhaFonte(source: source)],
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  final MatchedSource source;

  const _LinhaFonte({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // Os cinco pedaços que a seção 7 pede, nesta ordem.
            '${formatBytes(source.size)}, ${source.sourceId}, '
            '$_kTipoFonte, ${_rotuloConfianca(source.confidence)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Rode e veja passar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `+18`, zero falha. São os 7 da Task 15 mais os 11 desta.

Dois tropeços prováveis:

Se `a lista começa fechada` falhar achando `Chrono Trigger (Japan).zip` com a lista fechada, você trocou `ExpansionTile` por um `Column` com `Visibility` ou pôs `maintainState: true`. O `ExpansionTile` fechado **não** constrói os filhos, e é disso que este teste depende.

Se os dois testes de `tap` falharem com `Actual: _TextFinder:<zero widgets>` logo depois do `pumpAndSettle`, confira que você chamou `pumpAndSettle` e não `pump`: a abertura é animada, e um `pump` só deixa a lista no meio do caminho, ainda `Offstage`.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Esperado: `+286 -1`, com a falha sendo a de sempre, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Fecha o Grupo 4: 178 do baseline mais 108 das dezesseis Tasks.

- [ ] **Step 7: Commit**

```bash
# agente de teste
git add test/game_detail_screen_test.dart
git commit -m "test(detalhe): faixa de sem fonte e lista de outras fontes"

# agente de producao
git add lib/screens/game_detail_screen.dart
git commit -m "feat(detalhe): faixa de sem fonte e lista de outras fontes"
```

---

# Grupo 5: a verificação por CRC

A seção 8 do spec de UI inteira. É o único grupo desta fatia que toca a rede, e toca de leve: duas requisições de 326 bytes por fonte suspeita, sem baixar nada.

Leia a "Segunda decisão travada" no topo antes de escrever a primeira linha. O erro caro deste grupo é achar que `MatchConfidence` ganha um valor novo. Não ganha.

---

### Task 17: `SourceVerification`, o serviço e o provider

**Files:**
- Create: `lib/models/source_verification_model.dart`
- Create: `lib/services/source_verification_service.dart`
- Create: `lib/providers/source_verification_provider.dart`
- Test: `test/source_verification_service_test.dart`
- Test: `test/source_verification_provider_test.dart`

O encanamento da verificação, sem nenhuma tela. A Task 18 pluga.

**Por que não é o `CrcConfirmService` da fatia 2.** Aquele serviço responde uma pergunta **aberta**: "de que jogo é este arquivo?", e a resposta dele é um `GameMatch` que pode corrigir o palpite de nome. Aqui a pergunta é **fechada**: "este arquivo é deste jogo?", e a resposta é um veredito de três valores que a tela pinta. A diferença não é de estilo: `confirm` devolve `byName` intocado tanto quando não conseguiu ler nada quanto quando leu e não decidiu, e para a seção 8 esses são dois estados diferentes, `impossible` e `crcDiscarded`. Espremer os dois num método só custaria um retorno com campos opcionais que só um dos dois chamadores lê.

**O que os dois compartilham de verdade** é `ZipCentralDirectory.read`, que é onde mora a parte difícil e que os dois chamam sem copiar uma linha.

**O cache é a família viva do Riverpod.** O provider **não** é `autoDispose`, e isso é a implementação literal de "o resultado da verificação é cacheado por (fonte, arquivo), então a segunda abertura do mesmo jogo é instantânea". O que sobra na memória é um enum por arquivo visto, não os bytes.

- [ ] **Step 1: Escreva os testes do serviço, que falham**

Crie `test/source_verification_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs do pacote de teste, na forma numérica que o diretório central grava.
const chronoUsa = 0x2D206BF7;
const chronoJapan = 0xABCD1234;
const smwEurope = 0xA31BEAD4;
const forasteiro = 0xDEADBEEF;

const chrono = 'snes/chrono-trigger';

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://exemplo/arquivo.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  test('não vai à rede quando o arquivo não é zip', () async {
    var chamadas = 0;
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: (u, r) async {
        chamadas++;
        throw StateError('não deveria ter ido à rede');
      },
    );

    final out = await service.verify(uri, 'Chrono Trigger (USA).7z', chrono);

    // Não existe leitor de 7z ou rar por Range. Impossível não é "fonte
    // ruim", é "não dá para saber".
    expect(out, SourceVerification.impossible);
    expect(chamadas, 0);
  });

  test('o CRC de dentro é um dump deste jogo', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)])).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcOk,
    );
  });

  test('qualquer dump do jogo serve, não precisa ser o do nome', () async {
    // O arquivo se chama USA e contém o dump japonês. Continua sendo Chrono
    // Trigger, e a pergunta desta classe é sobre o jogo, não sobre a versão.
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', chronoJapan)])).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcOk,
    );
  });

  test('o CRC de dentro é de outro jogo', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', smwEurope)])).fetch,
    );

    // O nome mente e o CRC desmente. Esta é a fonte que a seção 8 manda
    // descartar do destaque.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcDiscarded,
    );
  });

  test('o CRC de dentro não é de jogo nenhum do pacote', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', forasteiro)])).fetch,
    );

    // Um hack, um bad dump, uma tradução. Não é este jogo, então desce.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcDiscarded,
    );
  });

  test('zip sem ROM dentro não desmente nada', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([
        cdEntry('leiame.txt', forasteiro),
        cdEntry('bonus.zip', forasteiro),
      ])).fetch,
    );

    // Nenhuma das duas entradas tem CRC comparável com o pacote (seção 5.8,
    // limite 1), então não há evidência nem a favor nem contra.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.impossible,
    );
  });

  test('o servidor que não fala Range deixa a verificação impossível', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]),
        status: 200,
      ).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.impossible,
    );
  });

  test('são duas requisições curtas, e não o arquivo inteiro', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final service = SourceVerificationService(matcher: matcher, fetch: server.fetch);

    await service.verify(uri, 'Chrono Trigger (USA).zip', chrono);

    // Os 326 bytes da seção 8: um sufixo para achar o EOCD e um intervalo
    // exato para o diretório central.
    expect(server.asked.length, 2);
    expect(server.asked.first, 'bytes=-256');
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_verification_service_test.dart
```

Esperado: `Target of URI doesn't exist: 'package:roms_downloader/models/source_verification_model.dart'`.

- [ ] **Step 3: Implemente o modelo e o serviço**

Crie `lib/models/source_verification_model.dart`:

```dart
/// O eixo **a posteriori** da confiança numa fonte: o que a verificação por
/// CRC disse depois de ler o cabeçalho do arquivo remoto.
///
/// Não confunda com `MatchConfidence`, que é o eixo **a priori** e sai do tier
/// de nome (fatia 2). São dois eixos e eles não se misturam: ver a "Segunda
/// decisão travada" no plano da fatia 3. Se você se pegou querendo acrescentar
/// um `crcOk` ao `MatchConfidence`, é este enum que você queria.
///
/// Dart puro, sem import nenhum, de propósito.
enum SourceVerification {
  /// Ninguém perguntou. É o estado de toda fonte fora da tela de detalhe: a
  /// grade não verifica e o lote não verifica (seção 6 do spec de UI), e um
  /// console sem pacote não tem com o que verificar.
  notVerified,

  /// As duas requisições estão no ar.
  verifying,

  /// Um dump deste jogo está lá dentro. Certeza, não palpite.
  crcOk,

  /// Leu o CRC e ele não é deste jogo. A fonte sai do destaque e desce para a
  /// lista, marcada (seção 8).
  crcDiscarded,

  /// Não deu para saber: servidor sem `Range`, arquivo que não é ZIP, ZIP sem
  /// ROM dentro. **Não** é sinônimo de fonte ruim, e por isso não descarta.
  impossible,
}
```

Crie `lib/services/source_verification_service.dart`:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Responde uma pergunta fechada: **este** arquivo remoto contém um dump
/// **deste** jogo?
///
/// É prima de `CrcConfirmService` e não é a mesma coisa. Lá a pergunta é
/// aberta, "de que jogo é este arquivo", e a resposta é um `GameMatch` que
/// pode corrigir o palpite de nome. Aqui a resposta é um veredito que a tela
/// pinta. O `confirm` devolve `byName` intocado tanto quando não leu nada
/// quanto quando leu e não decidiu, e aqui esses dois casos são estados
/// diferentes. O que as duas compartilham de verdade é
/// `ZipCentralDirectory.read`, que é onde mora a parte difícil.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
class SourceVerificationService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const SourceVerificationService({required this.matcher, required this.fetch});

  /// Nunca levanta: toda falha vira [SourceVerification.impossible].
  Future<SourceVerification> verify(
      Uri uri, String sourceName, String gameId) async {
    // Sem leitor de 7z ou rar por Range, então nem gaste a requisição.
    if (!sourceName.toLowerCase().endsWith('.zip')) {
      return SourceVerification.impossible;
    }

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return SourceVerification.impossible;

    var viuRom = false;
    for (final entry in entries) {
      // `crcMatchesRom` exclui o compactado dentro do compactado, cujo CRC é
      // do comprimido e não da ROM (seção 5.8, limite 1).
      if (!entry.crcMatchesRom) continue;
      viuRom = true;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null && hit.game.id == gameId) return SourceVerification.crcOk;
    }

    // Um zip só com leia-me e capa não desmente nada, então não descarta. Um
    // zip com ROM que não é deste jogo desmente, e descarta.
    return viuRom
        ? SourceVerification.crcDiscarded
        : SourceVerification.impossible;
  }
}
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_verification_service_test.dart
```

Esperado: `+8`, zero falha.

- [ ] **Step 5: Escreva os testes do provider, que falham**

Crie `test/source_verification_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

const _alvo = PackTarget('snes', 'Super Nintendo');
const chronoUsa = 0x2D206BF7;

SourceVerificationRequest _pedido({String? url = 'https://exemplo/ct.zip'}) => (
      sourceId: 'listagem',
      filename: 'Chrono Trigger (USA).zip',
      url: url,
      gameId: 'snes/chrono-trigger',
    );

SourceVerificationService _servico(FakeRangeServer server) =>
    SourceVerificationService(matcher: PackMatcher(buildPack()), fetch: server.fetch);

ProviderContainer _container({
  PackTarget? alvo = _alvo,
  SourceVerificationService? servico,
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(alvo),
    if (servico != null)
      sourceVerificationServiceProvider(_alvo).overrideWith((ref) => servico),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('sem console selecionado ninguém verifica nada', () async {
    final container = _container(alvo: null);

    // Nenhuma sobrescrita de serviço aqui: se o provider tentasse construir
    // um, ele iria à rede de verdade dentro do teste.
    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.notVerified,
    );
  });

  test('console sem pacote fica em notVerified', () async {
    final container = ProviderContainer(overrides: [
      packTargetProvider.overrideWithValue(_alvo),
      packMatcherProvider(_alvo).overrideWith((ref) => null),
    ]);
    addTearDown(container.dispose);

    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.notVerified,
    );
  });

  test('fonte sem url tem verificação impossível', () async {
    final container = _container();

    expect(
      await container.read(sourceVerificationProvider(_pedido(url: null)).future),
      SourceVerification.impossible,
    );
  });

  test('url que não parseia tem verificação impossível', () async {
    final container = _container();

    // `Uri.tryParse` devolve null aqui por causa do colchete sem par.
    expect(
      await container.read(sourceVerificationProvider(_pedido(url: 'http://[')).future),
      SourceVerification.impossible,
    );
  });

  test('o veredito do serviço chega inteiro', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.crcOk,
    );
  });

  test('enquanto a leitura roda o estado é verificando', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    // `verifying` não sai do provider: ele é o `AsyncLoading` traduzido.
    expect(
      verificationOf(container.read(sourceVerificationProvider(_pedido()))),
      SourceVerification.verifying,
    );

    await container.read(sourceVerificationProvider(_pedido()).future);

    expect(
      verificationOf(container.read(sourceVerificationProvider(_pedido()))),
      SourceVerification.crcOk,
    );
  });

  test('o mesmo par fonte e arquivo é lido uma vez só', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    await container.read(sourceVerificationProvider(_pedido()).future);
    await container.read(sourceVerificationProvider(_pedido()).future);

    // Duas requisições, não quatro. É o cache da seção 8, e ele é a família
    // viva do Riverpod, não um `Map` escrito à mão.
    expect(server.asked.length, 2);
  });

  test('erro vira impossível, e não tela vermelha', () async {
    expect(
      verificationOf(AsyncError(Exception('pacote não carregou'), StackTrace.empty)),
      SourceVerification.impossible,
    );
  });
}
```

- [ ] **Step 6: Rode e veja falhar**

```bash
flutter test test/source_verification_provider_test.dart
```

Esperado: `Target of URI doesn't exist: '.../source_verification_provider.dart'`.

- [ ] **Step 7: Implemente o provider**

Crie `lib/providers/source_verification_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_verification_service.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// O que identifica uma verificação.
///
/// É record, e não classe, porque record tem igualdade estrutural de graça, e
/// é essa igualdade que faz a família do Riverpod cachear. Com uma classe sem
/// `operator ==`, cada rebuild criaria uma chave nova e a verificação rodaria
/// de novo a cada frame, com duas requisições por vez.
///
/// A chave efetiva é (fonte, arquivo), como pede a seção 8 do spec de UI. Os
/// outros dois campos são função desses dois e estão aqui só para o provider
/// não precisar receber a fonte inteira.
typedef SourceVerificationRequest = ({
  String sourceId,
  String filename,
  String? url,
  String gameId,
});

/// O verificador do console atual. Null quando o console não tem pacote, que é
/// o mesmo contrato de `packMatcherProvider`.
///
/// Fica separado do provider de veredito porque é ele que carrega o `fetch` de
/// produção, e é ele que o teste sobrescreve para não ir à rede.
final sourceVerificationServiceProvider =
    FutureProvider.family<SourceVerificationService?, PackTarget>((ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return SourceVerificationService(
    matcher: matcher,
    fetch: ZipCentralDirectory.httpRangeFetch,
  );
});

/// O veredito de CRC de uma fonte.
///
/// **Não é `autoDispose`, de propósito.** A família viva é o cache que a seção
/// 8 pede quando diz que a segunda abertura do mesmo jogo é instantânea. O que
/// fica na memória é um enum por (fonte, arquivo) visto, não os bytes.
///
/// Nunca devolve [SourceVerification.verifying]: enquanto a leitura roda, quem
/// está em `verifying` é o próprio `AsyncValue`. Traduza com [verificationOf].
final sourceVerificationProvider =
    FutureProvider.family<SourceVerification, SourceVerificationRequest>((ref, request) async {
  final target = ref.watch(packTargetProvider);
  if (target == null) return SourceVerification.notVerified;

  final url = request.url;
  if (url == null) return SourceVerification.impossible;
  final uri = Uri.tryParse(url);
  if (uri == null) return SourceVerification.impossible;

  final service = await ref.watch(sourceVerificationServiceProvider(target).future);
  if (service == null) return SourceVerification.notVerified;

  return service.verify(uri, request.filename, request.gameId);
});

/// O estado que a tela pinta, a partir do que o provider devolveu.
///
/// Erro vira `impossible` e não tela vermelha: `verify` não levanta, então
/// chegar aqui significa que o pacote do console não carregou, e nesse caso o
/// que o usuário precisa saber é que não deu para verificar.
SourceVerification verificationOf(AsyncValue<SourceVerification> value) => value.when(
      data: (veredito) => veredito,
      loading: () => SourceVerification.verifying,
      error: (_, __) => SourceVerification.impossible,
    );
```

- [ ] **Step 8: Rode e veja passar**

```bash
flutter test test/source_verification_service_test.dart test/source_verification_provider_test.dart
```

Esperado: `+16`, zero falha.

Tropeço provável: se `console sem pacote fica em notVerified` estourar tentando rede, é porque `packMatcherProvider` não aceitou a sobrescrita e caiu no corpo real, que chama `metadataPackProvider`. A forma certa para um membro de família em Riverpod 2.6 é `packMatcherProvider(_alvo).overrideWith((ref) => null)`, com o argumento entre parênteses **antes** do `overrideWith`.

- [ ] **Step 9: Commit**

```bash
# agente de teste
git add test/source_verification_service_test.dart test/source_verification_provider_test.dart
git commit -m "test(crc): veredito de verificacao por CRC e o cache por fonte e arquivo"

# agente de producao
git add lib/models/source_verification_model.dart lib/services/source_verification_service.dart lib/providers/source_verification_provider.dart
git commit -m "feat(crc): veredito de verificacao por CRC e o cache por fonte e arquivo"
```

---

### Task 18: a verificação por CRC na tela de detalhe

**Files:**
- Modify: `lib/services/source_pick_service.dart` (uma função nova no fim)
- Modify: `lib/screens/game_detail_screen.dart` (o arquivo inteiro)
- Modify: `test/source_pick_service_test.dart` (oito testes novos no fim)
- Modify: `test/game_detail_screen_test.dart` (dez testes novos no fim, mais o `_host`)

A seção 8 do spec de UI ligada na tela. É a Task mais longa da fatia, e a razão é que a regra de destaque passa a depender de um estado assíncrono por fonte.

**A regra, travada, na ordem:**

1. Fonte `crcDiscarded` **nunca** disputa o destaque. Ela desce para a lista, marcada.
2. Se sobrou alguma `crcOk`, o destaque sai **só** entre as `crcOk`, e o motivo vira `confirmado pelo CRC, é exatamente este dump`. É aqui que o destaque troca de arquivo, que é o ponto inteiro da seção 8.
3. Se não sobrou nenhuma `crcOk` e **todas** as que sobraram são `impossible`, entra o estado "não tenho certeza de nenhuma": nada em destaque, a lista abre expandida e cada linha ganha o seu Baixar.
4. Fora disso, o destaque é o da Task 16, escolhido por nome.
5. Se não sobrou fonte nenhuma porque todas foram descartadas, a faixa aparece com o motivo `nenhuma fonte passou na verificação por CRC`.

**O botão diz "Baixar mesmo assim" quando `verificando && !confirmado`.** Se uma fonte já bateu o CRC, a certeza está dada e a leitura que ainda roda numa fonte perdedora não pode mais mudar o destaque. Fazer o botão hesitar nesse caso seria hesitar por nada.

**A regra é função pura, e mora fora do widget.** `splitByVerification` vai para `source_pick_service.dart`, ao lado de `planFromEntries`, e recebe os estados já resolvidos em vez de um `WidgetRef`. Oito dos dezoito testes desta Task não sobem widget nenhum por causa disso.

**Não chame `ref.watch` de dentro de um widget filho.** A tela resolve o estado das fontes **uma vez**, no `build` do `ConsumerWidget`, e passa dados prontos para baixo. `_OutrasFontes` e `_LinhaFonte` continuam widgets burros, como todo o resto desta fatia.

**A `faixa de "nenhuma fonte passou na verificação por CRC"` é a única string desta tela que não vem de `PickFailure`.** E tem que ser: o lote não verifica CRC, então a regra de lote não tem como conhecer esse estado. Está anotada no código para ninguém "consertar" isso movendo a string para o serviço.

- [ ] **Step 1: Escreva os oito testes da função pura, que falham**

No fim de `main` em `test/source_pick_service_test.dart`:

```dart
  VerifiedSource _v(String filename, SourceVerification state) => (
        source: MatchedSource(
          filename: filename,
          sourceId: kBuiltinSourceId,
          confidence: MatchConfidence.likely,
          size: 100,
        ),
        state: state,
      );

  test('sem fonte nenhuma não há nada elegível e não há incerteza', () {
    final split = splitByVerification(const []);

    expect(split.eligible, isEmpty);
    expect(split.discarded, isEmpty);
    expect(split.confirmed, isFalse);
    expect(split.verifying, isFalse);
    // Zero fonte é a faixa de "sem fonte" da Task 16, não o estado novo.
    expect(split.noCertainty, isFalse);
  });

  test('sem verificação, todas disputam', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.length, 2);
    expect(split.confirmed, isFalse);
    expect(split.noCertainty, isFalse);
  });

  test('uma confirmada por CRC tira as não confirmadas da disputa', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.crcOk),
    ]);

    // É aqui que o destaque troca de arquivo (seção 8).
    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.confirmed, isTrue);
  });

  test('a descartada nunca disputa e sai contada à parte', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.discarded.map((v) => v.source.filename), ['a.zip']);
  });

  test('enquanto alguma verifica, ninguém é excluído', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.verifying),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.verifying, isTrue);
    expect(split.eligible.length, 2);
    expect(split.noCertainty, isFalse);
  });

  test('todas impossíveis viram o estado de não tenho certeza de nenhuma', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.impossible),
    ]);

    expect(split.noCertainty, isTrue);
  });

  test('uma impossível e uma sem verificar não é incerteza total', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    // A segunda nunca foi perguntada, então ainda não se sabe. Abrir a lista
    // e desistir do destaque aqui seria desistir cedo demais.
    expect(split.noCertainty, isFalse);
    expect(split.eligible.length, 2);
  });

  test('tudo descartado deixa a disputa vazia sem virar incerteza', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.crcDiscarded),
    ]);

    expect(split.eligible, isEmpty);
    expect(split.discarded.length, 2);
    // Não é incerteza: é certeza de que nenhuma serve. A tela mostra a faixa.
    expect(split.noCertainty, isFalse);
  });
```

Acrescente o import que falta, no topo do arquivo:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `Undefined name 'splitByVerification'` e `Undefined class 'VerifiedSource'`.

- [ ] **Step 3: Implemente a função pura**

No fim de `lib/services/source_pick_service.dart`, com o import novo no topo:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
```

```dart
/// Uma fonte com o veredito de CRC dela já resolvido.
///
/// A tela resolve os vereditos uma vez, no `build` do `ConsumerWidget`, e
/// passa isto para baixo. Assim esta função não conhece Riverpod e os testes
/// dela não sobem widget.
typedef VerifiedSource = ({MatchedSource source, SourceVerification state});

/// Como a verificação por CRC reorganiza as fontes de um jogo (seção 8).
typedef VerificationSplit = ({
  /// Quem pode disputar o destaque: só as confirmadas quando existe alguma
  /// confirmada, senão tudo que não foi descartado.
  List<VerifiedSource> eligible,

  /// Quem saiu da disputa porque o CRC desmentiu o nome.
  List<VerifiedSource> discarded,

  /// Alguma leitura ainda no ar.
  bool verifying,

  /// Alguma fonte confirmada por CRC.
  bool confirmed,

  /// Sobrou fonte, nenhuma confirmada, e **todas** as que sobraram são
  /// impossíveis de verificar. É o "não tenho certeza de nenhuma" da seção 8.
  bool noCertainty,
});

/// A regra da seção 8, na ordem dela. Pura, e é de propósito: a tela de
/// detalhe fica só com o desenho.
VerificationSplit splitByVerification(List<VerifiedSource> sources) {
  final ok = <VerifiedSource>[];
  final discarded = <VerifiedSource>[];
  final rest = <VerifiedSource>[];
  var verifying = false;
  var impossible = 0;

  for (final item in sources) {
    switch (item.state) {
      case SourceVerification.crcOk:
        ok.add(item);
      case SourceVerification.crcDiscarded:
        discarded.add(item);
      case SourceVerification.verifying:
        verifying = true;
        rest.add(item);
      case SourceVerification.impossible:
        impossible++;
        rest.add(item);
      case SourceVerification.notVerified:
        rest.add(item);
    }
  }

  return (
    eligible: ok.isNotEmpty ? ok : rest,
    discarded: discarded,
    verifying: verifying,
    confirmed: ok.isNotEmpty,
    // `impossible == rest.length` e não `!verifying`: uma fonte que ninguém
    // perguntou ainda não desistiu, e desistir por ela seria desistir cedo.
    noCertainty: ok.isEmpty && rest.isNotEmpty && impossible == rest.length,
  );
}
```

O `switch` sem `break` é Dart 3 e passa no analisador. Conferido rodando `dart analyze` num arquivo com exatamente esta forma.

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/source_pick_service_test.dart
```

Esperado: `+23`, zero falha. São os 15 das Tasks 6 e 14 mais os 8 desta.

- [ ] **Step 5: Ajuste o `_host` do teste de tela**

Em `test/game_detail_screen_test.dart`, `_host` precisa de um seam para a verificação. **Sem ele os testes vão à rede de verdade**, porque `sourceVerificationProvider` carrega o pacote do console para montar o matcher, e a tela ficaria presa em "verificando" para sempre, quebrando os dezoito testes das Tasks 15 e 16.

Substitua `_host` inteiro por este:

```dart
Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verificacao,
}) {
  return ProviderScope(
    overrides: [
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolvePadrao),
      // Sobrescrita da família inteira, que vale para qualquer argumento.
      // Conferido que compila no Riverpod 2.6: `familia.overrideWith((ref,
      // arg) => ...)`, sem parênteses de argumento antes do `overrideWith`.
      sourceVerificationProvider.overrideWith((ref, pedido) {
        final estado = verificacao?.call(pedido.filename) ?? SourceVerification.notVerified;
        // `verifying` não é valor que o provider devolva: ele é o
        // `AsyncLoading`. Um `Completer` que nunca completa segura a tela
        // nesse estado sem deixar timer pendente no fim do teste.
        if (estado == SourceVerification.verifying) {
          return Completer<SourceVerification>().future;
        }
        return estado;
      }),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entrada, onDownload: onDownload ?? (_) {}),
    ),
  );
}
```

E os imports novos, no topo:

```dart
import 'dart:async';

import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
```

O teste do checkbox da Task 15 monta o próprio `ProviderScope` à mão e **também** precisa da sobrescrita, senão ele vai à rede. Acrescente a mesma linha na lista de `overrides` dele:

```dart
        sourceVerificationProvider.overrideWith((ref, pedido) => SourceVerification.notVerified),
```

- [ ] **Step 6: Escreva os dez testes de tela, que falham**

No fim de `main`, no mesmo arquivo:

```dart
  testWidgets('enquanto verifica, o botão diz Baixar mesmo assim', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      verificacao: (_) => SourceVerification.verifying,
    ));

    expect(find.widgetWithText(FilledButton, 'Baixar mesmo assim'), findsOneWidget);
    expect(find.text('4.0 MB, listagem, verificando'), findsOneWidget);
  });

  testWidgets('CRC ok troca o motivo pelo motivo do CRC', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      verificacao: (_) => SourceVerification.crcOk,
    ));

    expect(find.text('confirmado pelo CRC, é exatamente este dump'), findsOneWidget);
    expect(find.text('4.0 MB, listagem, CRC ok'), findsOneWidget);
    // Com certeza dada, o botão não hesita.
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsOneWidget);
  });

  testWidgets('a fonte descartada sai do destaque e a outra sobe', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    // Por nome, a USA ganharia pela região preferida. O CRC desmentiu, e o
    // destaque trocou de arquivo. É o ponto inteiro da seção 8.
    expect(find.text('Chrono Trigger (Japan).zip'), findsOneWidget);
    expect(find.text('outra fonte, 1 descartada'), findsOneWidget);
  });

  testWidgets('a linha descartada aparece marcada', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    await tester.tap(find.text('outra fonte, 1 descartada'));
    await tester.pumpAndSettle();

    expect(
      find.text('4.0 MB, listagem, HTTP, casamento provável, descartada pelo CRC'),
      findsOneWidget,
    );
  });

  testWidgets('com uma confirmada, a que ainda verifica não faz o botão hesitar', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (filename) => filename.contains('USA')
          ? SourceVerification.verifying
          : SourceVerification.crcOk,
    ));

    // A leitura que ainda roda é de uma fonte que já perdeu, então ela não
    // pode mais mudar o destaque.
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsOneWidget);
    expect(find.text('confirmado pelo CRC, é exatamente este dump'), findsOneWidget);
  });

  testWidgets('nenhuma verificável: o card diz que não tem certeza de nenhuma', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (_) => SourceVerification.impossible,
    ));

    expect(find.text('não tenho certeza de nenhuma'), findsOneWidget);
    // Nada em destaque significa nada de motivo de escolha por nome.
    expect(find.text('escolhido pela sua região preferida (USA)'), findsNothing);
  });

  testWidgets('nesse estado a lista já abre e cada linha tem o seu Baixar', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (_) => SourceVerification.impossible,
    ));

    // Sem tap nenhum: a lista nasce aberta.
    expect(find.text('Chrono Trigger (USA).zip'), findsOneWidget);
    expect(find.text('Chrono Trigger (Japan).zip'), findsOneWidget);
    // Dois botões, e nenhum terceiro: não há card de destaque.
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNWidgets(2));
  });

  testWidgets('o Baixar da linha devolve aquela fonte, marcada como incerta', (tester) async {
    final baixados = <SourcePick>[];
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      onDownload: baixados.add,
      verificacao: (_) => SourceVerification.impossible,
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Baixar').first);
    await tester.pump();

    expect(baixados.single.filename, 'Chrono Trigger (USA).zip');
    expect(baixados.single.uncertain, isTrue);
  });

  testWidgets('todas descartadas: a faixa diz que nenhuma passou', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (_) => SourceVerification.crcDiscarded,
    ));

    expect(find.text('nenhuma fonte passou na verificação por CRC'), findsOneWidget);
    expect(find.text('outras 2 fontes, 2 descartadas'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNothing);
  });

  testWidgets('a fonte impossível de verificar diz isso na linha', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip'),
        _fonte('Chrono Trigger (Japan).zip'),
      ]),
      verificacao: (filename) => filename.contains('USA')
          ? SourceVerification.crcOk
          : SourceVerification.impossible,
    ));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    expect(
      find.text('4.0 MB, listagem, HTTP, casamento provável, sem como verificar'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 7: Rode e veja falhar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `+18 -10`. Os dezoito das Tasks 15 e 16 continuam passando, o que é metade do valor desta rodada: se algum deles falhar agora, o culpado é o `_host`, não a tela.

- [ ] **Step 8: Reescreva a tela**

`lib/screens/game_detail_screen.dart` inteiro passa a ser este arquivo:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// O tipo de fonte, que nesta fatia é um só.
///
/// Toda fonte vem da listagem HTTP do console. `SEED` e `RD` da seção 7 do
/// spec de UI chegam quando o addon declarar o tipo (fatia 4 e fatia 6). É
/// constante em vez de literal solto para o dia em que virar campo.
const _kTipoFonte = 'HTTP';

/// A tela das seções 7 e 8 do spec de UI: um jogo, as fontes dele, o motivo da
/// escolha e o que a verificação por CRC disse sobre cada uma.
///
/// Não é bottom sheet e não é expansão inline. É rota.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// O que fazer quando o usuário aperta Baixar.
  ///
  /// A tela não conhece a fila, pelo mesmo motivo que `PackGrid` não conhece
  /// `Navigator`: `TaskQueueService.startDownloads` puxa o pipeline inteiro de
  /// download, e uma tela que o chama direto não se testa. Quem liga os dois é
  /// o `HomeScreen`.
  final void Function(SourcePick pick) onDownload;

  const GameDetailScreen({super.key, required this.entry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final chave = entry.selectionKey;
    final favorito = ref.watch(favoritesProvider).isFavorite(chave);
    final selecionado = ref.watch(catalogProvider.select((s) => s.selectedGames)).contains(chave);
    final resolver = ref.watch(gameResolverProvider);

    // Os vereditos são resolvidos **aqui**, uma vez, e descem como dado. Os
    // widgets filhos não veem `ref`: eles são burros como todo o resto desta
    // fatia. O `watch` por fonte é barato porque a família do Riverpod cacheia
    // por (fonte, arquivo).
    final verificadas = <VerifiedSource>[
      for (final source in entry.sources) (source: source, state: _estadoDe(ref, game.id, source)),
    ];
    final split = splitByVerification(verificadas);

    // A mesma regra do lote, com uma entrada só, sobre quem sobrou da
    // verificação. Seção 6: uma regra só, dois lugares.
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
    );

    final escolha = split.noCertainty ? null : plan.picks.firstOrNull;
    final vencedora = _vencedora(split.eligible, escolha);
    final outras = [
      for (final v in verificadas)
        if (!identical(v.source, vencedora?.source)) v,
    ];

    // A única string desta tela que não sai de `PickFailure`, e tem que ser: o
    // lote não verifica CRC, então a regra de lote não conhece este estado.
    // Não "conserte" isso movendo a string para o serviço.
    final faixa = split.eligible.isEmpty && split.discarded.isNotEmpty
        ? 'nenhuma fonte passou na verificação por CRC'
        : (split.noCertainty ? null : plan.failures.firstOrNull?.reason);

    void baixarFonte(VerifiedSource item) {
      final jogo = resolver(item.source);
      if (jogo == null) return;
      onDownload(SourcePick(
        gameId: chave,
        title: game.title,
        filename: item.source.filename,
        size: item.source.size,
        sourceId: item.source.sourceId,
        reason: 'escolhida por você, sem verificação possível',
        uncertain: true,
        game: jogo,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorito ? 'Tirar dos favoritos' : 'Favoritar',
            icon: Icon(
              favorito ? Icons.favorite : Icons.favorite_border,
              color: favorito ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(chave),
          ),
          Checkbox(
            value: selecionado,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(chave),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Topo(game: game, sistema: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (escolha != null && vencedora != null) ...[
            const SizedBox(height: 16),
            _Destaque(
              pick: escolha,
              verification: vencedora.state,
              confirmadoPorCrc: split.confirmed,
              // Hesita só enquanto a hesitação pode mudar alguma coisa.
              hesita: split.verifying && !split.confirmed,
              onDownload: () => onDownload(escolha),
            ),
          ] else if (split.noCertainty) ...[
            const SizedBox(height: 16),
            const _SemCerteza(),
          ] else if (faixa != null) ...[
            const SizedBox(height: 16),
            _SemFonte(reason: faixa),
          ],
          if (outras.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OutrasFontes(
              sources: outras,
              descartadas: split.discarded.length,
              comecaAberta: split.noCertainty,
              onDownload: split.noCertainty ? baixarFonte : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// O veredito de uma fonte.
///
/// Um match de tier `checksum` já nasceu de um CRC batido contra o pacote, e
/// por isso ele não passa por `verifying`: perguntar de novo seria gastar duas
/// requisições para reconfirmar o que já se sabe. Ver a "Segunda decisão
/// travada" do plano da fatia 3.
SourceVerification _estadoDe(WidgetRef ref, String gameId, MatchedSource source) {
  if (source.confidence == MatchConfidence.confirmed) return SourceVerification.crcOk;
  return verificationOf(ref.watch(sourceVerificationProvider((
    sourceId: source.sourceId,
    filename: source.filename,
    url: source.url,
    gameId: gameId,
  ))));
}

/// Qual objeto da lista de elegíveis virou a escolha.
///
/// Compara os três campos e devolve a **instância**, porque quem chama tira a
/// vencedora da lista por identidade. Duas fontes podem servir arquivos de
/// mesmo nome, e tirar as duas esconderia uma fonte real.
VerifiedSource? _vencedora(List<VerifiedSource> eligible, SourcePick? pick) {
  if (pick == null) return null;
  for (final item in eligible) {
    if (item.source.filename == pick.filename &&
        item.source.size == pick.size &&
        item.source.sourceId == pick.sourceId) {
      return item;
    }
  }
  return null;
}

/// Null quando não há o que dizer, e aí a linha fica igual à da Task 16.
String? _rotuloVerificacao(SourceVerification state) => switch (state) {
      SourceVerification.notVerified => null,
      SourceVerification.verifying => 'verificando',
      SourceVerification.crcOk => 'CRC ok',
      SourceVerification.crcDiscarded => 'descartada pelo CRC',
      SourceVerification.impossible => 'sem como verificar',
    };

String _rotuloOutras(int quantas, int descartadas) {
  final base = quantas == 1 ? 'outra fonte' : 'outras $quantas fontes';
  if (descartadas == 0) return base;
  // As descartadas estão **dentro** de [quantas]: elas desceram para a lista,
  // não sumiram (seção 8).
  return descartadas == 1 ? '$base, 1 descartada' : '$base, $descartadas descartadas';
}

class _Topo extends StatelessWidget {
  final PackGame game;
  final String sistema;

  const _Topo({required this.game, required this.sistema});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Só o que existe entra na linha, senão sobra vírgula solta num jogo sem
    // ano ou sem publisher, que é a maioria dos homebrews.
    final ficha = [
      sistema,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((parte) => parte.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _capa(context),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(ficha, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _capa(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videogame_asset_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorListener: (_) {},
    );
  }
}

/// O card da versão escolhida. O motivo é a linha que não pode faltar.
class _Destaque extends StatelessWidget {
  final SourcePick pick;
  final SourceVerification verification;
  final bool confirmadoPorCrc;
  final bool hesita;
  final VoidCallback onDownload;

  const _Destaque({
    required this.pick,
    required this.verification,
    required this.confirmadoPorCrc,
    required this.hesita,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selo = _rotuloVerificacao(verification);
    final motivo = confirmadoPorCrc
        ? 'confirmado pelo CRC, é exatamente este dump'
        : pick.reason;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pick.filename,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _kTipoFonte,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)}, ${pick.sourceId}${selo == null ? '' : ', $selo'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(motivo, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDownload,
              child: Text(hesita ? 'Baixar mesmo assim' : 'Baixar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faixa que substitui o card quando não há o que baixar.
///
/// O texto vem de `PickFailure.reason` na maioria dos casos, ou seja da mesma
/// regra que a folha de lote usa. A tela não inventa motivo próprio, com a
/// única exceção anotada no `build` da tela.
///
/// Falta aqui o atalho para a tela de addons que a seção 7 pede. A tela de
/// addons é a fatia 4; quando ela existir, o botão entra neste widget.
class _SemFonte extends StatelessWidget {
  final String reason;

  const _SemFonte({required this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// O card do estado "verificação impossível" da seção 8. Nunca finge certeza.
class _SemCerteza extends StatelessWidget {
  const _SemCerteza();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'não tenho certeza de nenhuma',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Nenhuma das fontes deixou ler o CRC. Escolha uma abaixo.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A lista da seção 7, com o contador da seção 8.
class _OutrasFontes extends StatelessWidget {
  final List<VerifiedSource> sources;
  final int descartadas;
  final bool comecaAberta;

  /// Null na maioria das vezes: o botão por linha é só o estado "verificação
  /// impossível" da seção 8.
  final void Function(VerifiedSource item)? onDownload;

  const _OutrasFontes({
    required this.sources,
    required this.descartadas,
    required this.comecaAberta,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` desenha uma divisória em cima e outra embaixo assim
      // que abre, e dentro de um `ListView` de cards isso vira duas linhas
      // soltas no meio da tela.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: comecaAberta,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _rotuloOutras(sources.length, descartadas),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final item in sources)
            _LinhaFonte(
              item: item,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
        ],
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  final VerifiedSource item;
  final VoidCallback? onDownload;

  const _LinhaFonte({required this.item, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selo = _rotuloVerificacao(item.state);
    final baixar = onDownload;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // Os cinco pedaços que a seção 7 pede, mais o veredito da seção 8
            // quando existe um.
            '${formatBytes(item.source.size)}, ${item.source.sourceId}, '
            '$_kTipoFonte, ${_rotuloConfianca(item.source.confidence)}'
            '${selo == null ? '' : ', $selo'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (baixar != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: baixar, child: const Text('Baixar')),
            ),
          ],
        ],
      ),
    );
  }
}

/// A confiança do **casamento**, que não é a verificação por CRC.
///
/// Ver a "Segunda decisão travada" do plano da fatia 3: são dois eixos e eles
/// não se misturam. O veredito de CRC entra na mesma linha, depois deste, como
/// um pedaço à parte.
String _rotuloConfianca(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'casamento confirmado',
      MatchConfidence.likely => 'casamento provável',
      MatchConfidence.guess => 'casamento no chute',
    };
```

Sumiu o `_outrasFontes` da Task 16: quem tira a vencedora da lista agora é o filtro por identidade lá no `build`, sobre a lista já verificada. O comportamento é o mesmo, inclusive o de tirar uma cópia só quando duas fontes têm o mesmo nome, e o teste da Task 16 que prova isso continua valendo sem mudança.

- [ ] **Step 9: Rode e veja passar**

```bash
flutter test test/game_detail_screen_test.dart test/source_pick_service_test.dart
```

Esperado: `+51`, zero falha. São 28 da tela e 23 do serviço.

Três tropeços prováveis:

Se os dezoito testes das Tasks 15 e 16 começarem a falhar com timeout ou com "pending timer", o `_host` não está sobrescrevendo `sourceVerificationProvider` e a tela está tentando carregar o pacote de verdade.

Se `a fonte descartada sai do destaque` continuar mostrando a USA, confira que `planFromEntries` está recebendo `split.eligible` e não `entry.sources`.

Se `o Baixar da linha devolve aquela fonte` pegar o botão errado, confira a ordem: `outras` preserva a ordem de `entry.sources`, então `.first` é a USA.

- [ ] **Step 10: Rode a suíte inteira**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Esperado: `+320 -1`, com a falha sendo a de sempre, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Fecha o Grupo 5.

- [ ] **Step 11: Commit**

```bash
# agente de teste
git add test/source_pick_service_test.dart test/game_detail_screen_test.dart
git commit -m "test(crc): destaque, descarte e incerteza total na tela de detalhe"

# agente de producao
git add lib/services/source_pick_service.dart lib/screens/game_detail_screen.dart
git commit -m "feat(crc): destaque, descarte e incerteza total na tela de detalhe"
```

---

# Grupo 6: o app inteiro

Até aqui a fatia é uma pilha de peças testadas que ninguém liga. A grade de pack existe e nunca é desenhada, a tela de detalhe existe e nada empurra a rota dela, e a folha de lote só sabe somar arquivos de MODO FONTE. Este grupo liga os cabos e depois prova que ligar os cabos não estragou o app de hoje.

Três Tasks de código e uma de varredura. As três de código tocam `home_screen.dart`, que é o único arquivo desta fatia que não se testa em widget test (a nota de teste da Task 3 explica por quê), então as três empurram o máximo de lógica possível para fora dele, para dentro de função pura testável. É por isso que a Task 19 nasce com um teste de duas linhas em vez de nenhum, é por isso que a Task 20 começa quebrando um provider em dois, e é por isso que a Task 21 testa a barra de seleção da tela de detalhe em vez do callback que a `home_screen.dart` passa para ela. A Task 22 fecha a fatia com a varredura de regressão.

---

### Task 19: o roteamento de modo e o rótulo do funil

**Files:**
- Create: `test/header_filter_label_test.dart`
- Modify: `lib/widgets/header/header.dart`
- Modify: `lib/screens/home_screen.dart:90-94`

Duas fiações e uma limpeza:

1. O `HomeScreen` passa a escolher entre `PackGrid` e a grade de hoje pelo `gridModeProvider`.
2. `PackGrid.onOpenGame` passa a empurrar a rota da `GameDetailScreen`, e `GameDetailScreen.onDownload` passa a chamar `TaskQueueService.startDownloads`. Os dois callbacks existem desde a Task 12 e a Task 15 justamente para se encontrarem **aqui**, e em nenhum outro lugar.
3. O botão de funil do header ganha rótulo por modo, que é a "Quinta decisão travada".

**O que esta Task deliberadamente não faz: mexer no `FilterModal`.** A tabela de "Estrutura de arquivos" lista **três** arquivos de produção existentes modificados nesta fatia, e `lib/widgets/header/filter_modal.dart` não é um deles. Em MODO PACK os chips de revisão e de qualidade de dump continuam aparecendo na folha de filtro e continuam sem efeito nenhum sobre a grade, porque a grade de pack não tem versão para filtrar. Isso é buraco conhecido e aceito, e o rótulo novo do botão existe para não mentir sobre ele: em vez de prometer "Filters", ele promete só o que sobrevive.

**Por que o rótulo de MODO FONTE não muda nem uma letra.** `'Filters'` é a string de hoje. A Task 22 exige que o MODO FONTE seja o app de hoje, e "o texto do tooltip mudou" é regressão igual a qualquer outra. O rótulo novo só aparece quando há pacote.

**Nota de teste.** `HomeScreen` e `Header` não se montam em teste de widget, pelo motivo escrito na nota de teste da Task 3: os dois puxam providers que fazem IO de disco e de rede no construtor. O que dá para testar sem montar nada é a decisão de rótulo, porque ela vira uma função de topo em `header.dart`. É pouco e é honesto: são duas asserções que travam a "Quinta decisão travada" contra alguém que resolva "simplificar" sumindo com o botão. O roteamento em si é provado por `flutter analyze` limpo, pela suíte inteira verde e pela conferência à mão do Step 6.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/header_filter_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';

void main() {
  test('em MODO FONTE o rótulo é o de hoje, sem uma letra mudada', () {
    // MODO FONTE é o app de hoje. Mudar este texto é regressão, e a Task 22
    // trata regressão de MODO FONTE como falha da fatia.
    expect(filterButtonLabel(GridMode.source), 'Filters');
  });

  test('em MODO PACK o rótulo diz só o que o funil ainda faz', () {
    // Em MODO PACK a grade não passa pelo FilteringService, então revisão e
    // qualidade de dump não filtram nada. Região sobrevive porque alimenta a
    // escolha de versão em `planFromEntries`. Ver "Quinta decisão travada".
    expect(filterButtonLabel(GridMode.pack), 'Preferência de região');
  });
}
```

Isto é `test`, e não `testWidgets`, de propósito: nada aqui monta widget, então não há binding para inicializar. Importar `header.dart` num teste puro é seguro porque `final` de topo em Dart é preguiçoso, ou seja nenhum provider é construído só por causa do import.

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/header_filter_label_test.dart
```

Esperado: `Undefined name 'filterButtonLabel'`.

- [ ] **Step 3: Escreva a função e ligue no botão**

Em `lib/widgets/header/header.dart`, acrescente o import:

```dart
import 'package:roms_downloader/providers/pack_grid_provider.dart';
```

E escreva a função **fora da classe**, logo depois dos imports e antes de `class Header`:

```dart
/// O rótulo do botão de funil, que depende do modo de grade.
///
/// "Quinta decisão travada" do plano da fatia 3: em MODO PACK os chips de
/// região, revisão e qualidade de dump não filtram a grade, porque a grade de
/// pack não tem versão para filtrar. O que sobrevive daquela folha é a
/// região, que passa a alimentar a escolha de versão em `planFromEntries`
/// (Task 14). O rótulo diz isso em vez de prometer um filtro que não
/// acontece.
///
/// O botão **não some** em MODO PACK. Sumir com ele tiraria o único caminho
/// para a preferência de região, que é justamente o que ainda tem efeito.
String filterButtonLabel(GridMode mode) =>
    mode == GridMode.pack ? 'Preferência de região' : 'Filters';
```

Agora ligue. Em `_HeaderState.build`, junto das outras leituras do topo do método (hoje linhas 36 a 40):

```dart
    final gridMode = ref.watch(gridModeProvider);
```

`_buildActionWidgets` é chamado em **dois** lugares, o ramo `isMobile` (hoje linha 109) e o ramo `Row` (hoje linha 152). Nos dois, troque o argumento `canDownload: canDownload,` por:

```dart
                          gridMode: gridMode,
```

E na assinatura de `_buildActionWidgets`, troque `required bool canDownload,` por `required GridMode gridMode,`. Dentro dela, o primeiro item da lista passa a ser:

```dart
      _buildActionButton(
        context: context,
        icon: catalogState.filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: catalogState.filter.isActive,
        onPressed: () => FilterModal.show(context),
        tooltip: filterButtonLabel(gridMode),
      ),
```

- [ ] **Step 4: Limpe o que a Task 3 deixou para trás**

A Task 3 apagou o botão "Download Selected", mas `canDownload` sobreviveu, porque parâmetro de método sem uso **não** é apontado pelo `flutter analyze` com as regras deste repositório. O Step 3 acabou de tirar o último uso dele. Apague agora, nesta ordem:

1. Em `build`, a linha `final canDownload = !appState.loading && downloadNotifier.hasDownloadableSelectedGames();` (hoje a 47).
2. Em `build`, a linha `final downloadNotifier = ref.read(downloadProvider.notifier);` (hoje a 37), que existia só para alimentar a de cima.
3. O import `package:roms_downloader/providers/download_provider.dart` (hoje a linha 7).

Depois rode:

```bash
flutter analyze lib/widgets/header/header.dart
```

Esperado: `No issues found`. Se aparecer `unused_import` de mais alguma coisa, apague o que ele apontar e nada além disso. Se aparecer `undefined_identifier` para `downloadNotifier` ou `canDownload`, é porque algum outro botão ainda os usava: desfaça a exclusão daquele item e siga. **Rode antes de decidir; não adivinhe.**

- [ ] **Step 5: Rode o teste e veja passar**

```bash
flutter test test/header_filter_label_test.dart
```

Esperado: `+2`, zero falha.

- [ ] **Step 6: Ligue o roteamento no `HomeScreen`**

Em `lib/screens/home_screen.dart`, acrescente os imports que faltam:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
```

Dentro de `_HomeScreenState`, junto do `_confirmarLote` que a Task 6 escreveu, acrescente os dois métodos:

```dart
  /// Empurra a tela de detalhe.
  ///
  /// A grade não navega (Task 12) e a tela não conhece a fila (Task 15). Os
  /// dois cabos soltos se encontram aqui, e é o único lugar em que se
  /// encontram.
  void _abrirDetalhe(PackGridEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameDetailScreen(entry: entry, onDownload: _baixarUm)),
    );
  }

  /// Uma escolha só, vinda da tela de detalhe, vai direto para a fila.
  ///
  /// Sem folha de confirmação, e isso é decisão, não esquecimento: a tela de
  /// detalhe **é** a confirmação. Ela já mostra o arquivo escolhido, o
  /// tamanho, o motivo por extenso e o veredito do CRC. Abrir por cima disso
  /// uma folha de lote de um item só seria perguntar duas vezes a mesma
  /// coisa. A folha existe para o lote, onde o usuário não viu escolha
  /// nenhuma antes de apertar Baixar.
  Future<void> _baixarUm(SourcePick pick) async {
    await TaskQueueService.startDownloads(
      ref,
      context,
      [pick.game],
      ref.read(appStateProvider).selectedConsole?.id,
    );
  }
```

`SourcePick` e `TaskQueueService` já estão importados desde a Task 6.

Agora troque o `switch (appState.viewMode)` do corpo, hoje as linhas 90 a 94, por um `switch` de fora e o de hoje aninhado dentro:

```dart
                    : switch (ref.watch(gridModeProvider)) {
                        GridMode.pack => PackGrid(onOpenGame: _abrirDetalhe),
                        GridMode.source => switch (appState.viewMode) {
                            ViewMode.grid => GameGrid(),
                            ViewMode.coverflow => const GameCoverFlow(),
                            ViewMode.list => GameList(),
                          },
                      },
```

Três coisas sobre esse trecho:

1. **O `switch` de dentro fica intacto, palavra por palavra.** Ele é o app de hoje e continua sendo o app de hoje. Não aproveite a passagem para "melhorar" a grade, a lista ou o coverflow.
2. **O modo de visualização não vale em MODO PACK.** `PackGrid` é a única forma da grade de pack nesta fatia: lista e coverflow são de MODO FONTE e a seção 12 do spec de UI os deixa explicitamente fora de escopo. O botão de trocar visualização continua no header e continua funcionando; em MODO PACK ele muda um estado que ninguém lê, e vira visível de novo assim que o console volta a ser um sem pacote. É feio e é barato; esconder o botão custaria mais um rótulo por modo e mais um teste, para um ganho que ninguém pediu.
3. **`ref.watch(gridModeProvider)` fica no `build`, não em `initState`.** O modo muda quando o usuário troca de console, e é um `Provider` síncrono derivado do `metadataPackProvider`, então ele reavalia sozinho quando o pacote chega da rede. Guardar isso em campo de `State` congelaria a grade em MODO FONTE no primeiro carregamento.

- [ ] **Step 7: Confira à mão, porque nenhum teste cobre isto**

Este é o primeiro momento em que a fatia inteira aparece na tela, então vale mais que o de costume:

```bash
flutter run -d linux
```

1. Escolha um console **com** pacote (SNES). A grade tem que virar a de pack: um tile por jogo, capa do pacote, e o número de tiles bate com o número de jogos do pacote, não com o número de arquivos da listagem.
2. Toque um tile. A tela de detalhe abre como rota, com botão de voltar.
3. Aperte Baixar na tela de detalhe. O download tem que aparecer no rodapé, com o nome do arquivo destacado, e a tela continua aberta.
4. Volte e abra a folha de filtro. O tooltip do funil é "Preferência de região" e a folha abre normalmente.
5. Troque para um console **sem** pacote (qualquer um que não tenha DAT). A grade tem que voltar a ser exatamente a de hoje, e o tooltip do funil volta a ser "Filters".
6. Nesse console sem pacote, troque a visualização para lista e para coverflow. As duas continuam funcionando.

Se o passo 1 mostrar a grade de hoje num console com pacote, o culpado quase sempre é o `metadataPackProvider` ainda em `loading` no primeiro frame; espere o pacote terminar de carregar antes de concluir que quebrou.

- [ ] **Step 8: Prove que não quebrou nada**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Esperado: 22 findings e zero erro no analyze; `+322 -1` na suíte, sendo os 320 da Task 18 mais os 2 desta.

- [ ] **Step 9: Commit**

```bash
# agente de teste
git add test/header_filter_label_test.dart
git commit -m "test(grade): rotulo do funil por modo de grade"

# agente de producao
git add lib/widgets/header/header.dart lib/screens/home_screen.dart
git commit -m "feat(grade): roteamento de modo, rota de detalhe e rotulo do funil por modo"
```

---

### Task 20: o MODO PACK alimenta a folha de lote

**Files:**
- Modify: `lib/models/grid_entry_model.dart`
- Modify: `lib/services/pack_grid_filter.dart`
- Modify: `test/pack_grid_filter_test.dart`
- Modify: `lib/providers/pack_grid_provider.dart`
- Modify: `test/pack_grid_provider_test.dart`
- Modify: `lib/screens/home_screen.dart`

A Task 6 fez a barra roxa abrir a folha de confirmação com `planFromGames`, que só sabe somar arquivos de MODO FONTE. A Task 14 escreveu `planFromEntries`, a regra de verdade, e até agora só a tela de detalhe a usa, com uma entrada só. Esta Task faz o lote de MODO PACK passar por ela, e é o último pedaço de código da fatia.

São três problemas de verdade escondidos numa fiação que parece de duas linhas. Leia os três antes de escrever qualquer coisa.

**Problema 1: a busca não pode encolher o lote.** Hoje `packGridEntriesProvider` já sai filtrado pelo texto da caixa de busca. Se o lote ler de lá, então marcar três jogos, digitar qualquer coisa no header e apertar Baixar enfileira só os que sobraram na tela. A seleção não é a tela. O conserto é quebrar o provider em dois: um com tudo, que o lote lê, e um filtrado, que a grade desenha.

**Problema 2: as chaves dos dois modos convivem no mesmo `Set`.** A "Quarta decisão travada" garante que elas não colidem, e não colidem mesmo, mas conviver elas convivem, e existe uma janela real em que isso acontece com o mesmo console: o catálogo carrega do disco em milissegundos e o pacote chega da rede segundos depois. Nesse intervalo a grade é MODO FONTE, o usuário marca três arquivos, o pacote chega e a grade vira MODO PACK com aquelas três chaves ainda na seleção. Sem tratamento, a barra roxa diz "3 selecionados", o usuário aperta Baixar e **nada acontece, em silêncio**, porque nenhuma delas casa com uma entrada de pack. O conserto é a barra contar só o que o modo corrente sabe enfileirar.

Trocar de console não tem esse problema: `CatalogNotifier.loadCatalog` já zera `selectedGames` (`catalog_provider.dart:53`, e de novo em `:379`).

**Problema 3: uma seleção, dois caminhos, uma folha só.** O que muda entre os modos é só como o `BatchPlan` nasce. A folha, o `showModalBottomSheet`, o `withoutPick`, o enfileiramento e a limpeza da seleção são os mesmos, e têm que continuar sendo os mesmos: é isso que a Task 6 comprou ao escrever `planFromGames` em vez de um `map` inline.

- [ ] **Step 1: Escreva os testes de função pura que falham**

No fim de `main` em `test/pack_grid_filter_test.dart`, seis testes novos:

```dart
  test('a seleção devolve as entradas na ordem da lista, não na ordem em que foram marcadas', () {
    final entradas = [_e('Chrono Trigger'), _e('EarthBound'), _e('Super Metroid')];

    final saida = entriesForSelection(entradas, {entradas[2].selectionKey, entradas[0].selectionKey});

    expect(saida.map((e) => e.game.title), ['Chrono Trigger', 'Super Metroid']);
  });

  test('chave que não existe mais no pacote é ignorada, sem explodir', () {
    // Acontece quando o pacote é republicado com um slug diferente enquanto a
    // seleção do usuário ainda aponta para o antigo.
    expect(entriesForSelection([_e('Chrono Trigger')], {'pack:snes/jogo-que-sumiu'}), isEmpty);
  });

  test('chave de MODO FONTE não traz entrada de pack nenhuma', () {
    expect(entriesForSelection([_e('Chrono Trigger')], {'snes/Chrono Trigger (USA).zip'}), isEmpty);
  });

  test('em MODO PACK só as chaves com prefixo pack: contam', () {
    final saida = selectionKeysFor(
      {'pack:snes/chrono-trigger', 'snes/Chrono Trigger (USA).zip'},
      pack: true,
    );

    expect(saida, {'pack:snes/chrono-trigger'});
  });

  test('em MODO FONTE só as chaves sem prefixo contam', () {
    final saida = selectionKeysFor(
      {'pack:snes/chrono-trigger', 'snes/Chrono Trigger (USA).zip'},
      pack: false,
    );

    expect(saida, {'snes/Chrono Trigger (USA).zip'});
  });

  test('seleção vazia devolve conjunto vazio nos dois modos', () {
    expect(selectionKeysFor(const {}, pack: true), isEmpty);
    expect(selectionKeysFor(const {}, pack: false), isEmpty);
  });
```

O helper `_e` da Task 9 serve sem mudança: ele monta o `PackGame` com id `'snes/${title.toLowerCase()}'`, e por isso os testes acima pegam a chave de `entradas[i].selectionKey` em vez de escrevê-la à mão. Escrever `'pack:snes/chrono trigger'` no teste funcionaria e seria pior: passaria a testar o formato do helper.

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/pack_grid_filter_test.dart
```

Esperado: `Undefined name 'entriesForSelection'` e `Undefined name 'selectionKeysFor'`.

- [ ] **Step 3: Escreva as duas funções**

Primeiro, em `lib/models/grid_entry_model.dart`, o prefixo vira constante, porque a partir de agora ele é lido em dois arquivos e um literal duplicado em dois arquivos é um bug esperando data. Acrescente antes da classe:

```dart
/// O prefixo da chave de seleção de MODO PACK.
///
/// Ver "Quarta decisão travada" no plano da fatia 3: o `:` não pode sair de
/// `CatalogService._nameToId`, então uma chave com este prefixo nunca colide
/// com um `Game.gameId`.
const kPackSelectionPrefix = 'pack:';
```

E troque o getter para usá-la:

```dart
  String get selectionKey => '$kPackSelectionPrefix${game.id}';
```

O teste da Task 7 (`expect(entry.selectionKey, 'pack:snes/chrono-trigger')`) continua passando, e é bom que continue: ele agora prova que a constante vale o que valia o literal.

Agora, no fim de `lib/services/pack_grid_filter.dart`:

```dart
/// As entradas que o usuário marcou, na ordem em que [entries] veio.
///
/// A ordem é a da grade, e não a ordem em que o usuário tocou os tiles,
/// porque é a lista da grade que ele acabou de ver.
///
/// Ignora chave desconhecida em silêncio. É o comportamento certo aqui: as
/// duas causas reais, um pacote republicado com slug novo e uma chave do
/// outro modo, não são erro do usuário e não têm o que ser dito sobre elas.
List<PackGridEntry> entriesForSelection(List<PackGridEntry> entries, Set<String> keys) =>
    [for (final entry in entries) if (keys.contains(entry.selectionKey)) entry];

/// As chaves de seleção que pertencem ao modo corrente.
///
/// A seleção é um `Set<String>` único para os dois modos (ver "Quarta decisão
/// travada"), e existe uma janela real em que os dois convivem no mesmo
/// console: o catálogo carrega do disco em milissegundos e o pacote chega da
/// rede segundos depois. Quem marcou arquivos nesse intervalo vê a grade
/// virar MODO PACK com as chaves de MODO FONTE ainda lá dentro. Sem esta
/// função a barra roxa diria "3 selecionados" e o botão Baixar não faria
/// nada, em silêncio.
///
/// **Não** limpa a seleção do outro modo, de propósito: o console é o mesmo,
/// e se o pacote falhar e o modo cair de volta para FONTE a marcação do
/// usuário ainda está lá. Quem limpa de verdade é a troca de console, em
/// `CatalogNotifier.loadCatalog` (`catalog_provider.dart:53`).
Set<String> selectionKeysFor(Set<String> keys, {required bool pack}) =>
    {for (final key in keys) if (key.startsWith(kPackSelectionPrefix) == pack) key};
```

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/pack_grid_filter_test.dart
```

Esperado: `+13`, zero falha. São os 7 da Task 9 mais os 6 desta.

- [ ] **Step 5: Escreva os testes de provider que falham**

No fim de `main` em `test/pack_grid_provider_test.dart`:

```dart
  test('a busca do header não encolhe a lista que o lote lê', () async {
    // O bug que este teste tranca: marcar três jogos, digitar no header e
    // apertar Baixar enfileirando só os que sobraram na tela.
    final container = _container(jogos: [_game('Chrono Trigger (USA).zip')], busca: 'metroid');
    await _pronto(container);

    expect(container.read(packGridEntriesProvider).map((e) => e.game.id), ['snes/super-metroid']);
    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/chrono-trigger', 'snes/super-metroid'],
    );
  });

  test('a lista do lote sai ordenada por título, não na ordem do pacote', () async {
    final container = _container(
      pacote: Future.value(MetadataPack(
        pack: 'snes',
        system: 'Super Nintendo',
        built: '2026-01-01',
        games: [
          _pg('snes/super-metroid', 'Super Metroid (USA)'),
          _pg('snes/chrono-trigger', 'Chrono Trigger (USA)'),
        ],
      )),
    );
    await _pronto(container);

    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/chrono-trigger', 'snes/super-metroid'],
    );
  });
```

- [ ] **Step 6: Rode e veja falhar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `Undefined name 'allPackEntriesProvider'`.

- [ ] **Step 7: Quebre o provider em dois**

Em `lib/providers/pack_grid_provider.dart`, troque `packGridEntriesProvider` inteiro pelos dois abaixo:

```dart
/// Todos os jogos do pacote com as fontes casadas, ordenados, **sem** a busca
/// aplicada.
///
/// É daqui que o lote lê. A grade lê do filtrado logo abaixo. A separação não
/// é enfeite: a seleção não é a tela, e um lote que lesse da lista filtrada
/// perderia os jogos que o usuário marcou antes de digitar na busca.
///
/// Como não depende de `gridSearchQueryProvider`, este provider é construído
/// uma vez por carga de catálogo e não a cada tecla digitada. O filtro por
/// tecla passa a rodar sobre uma lista já ordenada, o que é mais barato que
/// a versão anterior, que remontava as entradas do zero a cada letra.
final allPackEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  // Busca vazia: `filterPackEntries` não filtra nada e serve só para ordenar.
  // A ordenação mora lá porque a grade e o lote têm que concordar sobre ela.
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], '');
});

/// O que a grade de MODO PACK desenha: o de cima, com a busca do header.
///
/// Em MODO FONTE ninguém lê este provider, e ele devolve lista vazia sem
/// custo, porque `metadataPackProvider` já resolveu para null.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  return filterPackEntries(
    ref.watch(allPackEntriesProvider),
    ref.watch(gridSearchQueryProvider),
  );
});
```

- [ ] **Step 8: Rode e veja passar**

```bash
flutter test test/pack_grid_provider_test.dart
```

Esperado: `+11`, zero falha. São os 7 da Task 10, os 2 da Task 15 e os 2 desta. Os sete antigos passam sem uma linha mudada, e isso é o ponto: `packGridEntriesProvider` mantém nome e semântica, só mudou de onde ele lê.

- [ ] **Step 9: Ligue o lote de MODO PACK no `HomeScreen`**

Em `lib/screens/home_screen.dart`, acrescente o import:

```dart
import 'package:roms_downloader/services/pack_grid_filter.dart';
```

No `build`, logo depois de `final errorMessage = ...`, hoiste o modo e filtre a seleção:

```dart
    final gridMode = ref.watch(gridModeProvider);
    final selecionadas = selectionKeysFor(
      ref.watch(catalogProvider.select((s) => s.selectedGames)),
      pack: gridMode == GridMode.pack,
    );
```

O `select` agora entrega o `Set` em vez do `length` que a Task 3 escreveu. Continua reconstruindo só quando a seleção muda: `CatalogNotifier` monta um `Set` novo a cada mexida (`catalog_provider.dart:229-237`) e devolve o mesmo objeto quando não mexe, e o `select` do Riverpod compara com `==`, que para `Set` é identidade.

A `SelectionBar` passa a contar a seleção filtrada e a mandar ela para o lote:

```dart
          SelectionBar(
            count: selecionadas.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmarLote(selecionadas),
          ),
```

E o `switch` do corpo passa a usar a variável hoisted, em vez de ler o provider uma segunda vez:

```dart
                    : switch (gridMode) {
```

- [ ] **Step 10: Faça o plano nascer pelo modo**

Ainda em `lib/screens/home_screen.dart`, troque o começo do `_confirmarLote` que a Task 6 escreveu, e acrescente o método que decide:

```dart
  /// Abre a folha da seção 6, e só enfileira o que voltar dela.
  Future<void> _confirmarLote(Set<String> selecionadas) async {
    var plano = _planoDaSelecao(selecionadas);
    // Um plano só de falhas **não** é vazio: a folha abre para dizer por que
    // nada vai ser baixado. Ver `BatchPlan.isEmpty`, na Task 4.
    if (plano.isEmpty) return;

    final confirmado = await showModalBottomSheet<BatchPlan>(
```

O resto do método, do `showModalBottomSheet` até o `clearSelection()`, fica **exatamente** como a Task 6 deixou. A única linha que sai é a antiga `if (selecionados.isEmpty) return;`, junto com o `final selecionados = ...` que a alimentava, porque quem calcula a seleção agora é o `build`.

E o método novo, logo acima dele:

```dart
  /// O plano do lote, pelo modo corrente.
  ///
  /// Os dois ramos devolvem o mesmo tipo e caem na mesma folha, no mesmo
  /// enfileiramento e na mesma limpeza de seleção. Se você se pegar
  /// escrevendo um segundo `showModalBottomSheet` aqui, parou no lugar
  /// errado: o que varia entre os modos é só como o `BatchPlan` nasce.
  BatchPlan _planoDaSelecao(Set<String> selecionadas) {
    if (ref.read(gridModeProvider) == GridMode.pack) {
      // A regra da seção 6, a mesma que escolhe o destaque da tela de
      // detalhe. `allPackEntriesProvider` e não `packGridEntriesProvider`:
      // ver o Problema 1 no topo desta Task.
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selecionadas),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
      );
    }
    // MODO FONTE: cada chave já é um arquivo, nada a escolher.
    final games = ref.read(catalogProvider).games;
    return planFromGames(games.where((game) => selecionadas.contains(game.gameId)).toList());
  }
```

Uma nota sobre o `clearSelection()` do fim de `_confirmarLote`: ele limpa a seleção **inteira**, inclusive as chaves do outro modo, que esta Task acabou de ensinar o app a ignorar. É o certo. O usuário acabou de mandar um lote para a fila; deixar acesa a marcação que ele fez antes de o pacote chegar seria guardar uma intenção que ele já não tem.

- [ ] **Step 11: Confira à mão, porque nenhum teste cobre a fiação**

```bash
flutter run -d linux
```

1. Num console com pacote, segure um tile para marcar, marque mais dois. A barra roxa diz "3 selecionados".
2. Digite no campo de busca até sobrar um tile na tela. A barra continua dizendo "3 selecionados".
3. Aperte Baixar. A folha abre com os **três**, cada um com nome de arquivo e motivo.
4. Tire um da folha e confirme. Dois entram na fila e a barra apaga.
5. Marque um jogo que a grade mostra sem fonte. A folha tem que abrir com ele embaixo de "Não vão para a fila", com o motivo, e com o botão Baixar desligado.
6. Num console **sem** pacote, repita os passos 1, 3 e 4. Tem que funcionar igualzinho a antes desta fatia.

- [ ] **Step 12: Prove que não quebrou nada**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Esperado: 22 findings e zero erro no analyze; `+330 -1` na suíte, sendo os 322 da Task 19 mais os 8 desta.

- [ ] **Step 13: Commit**

```bash
# agente de teste
git add test/pack_grid_filter_test.dart test/pack_grid_provider_test.dart
git commit -m "test(lote): selecao de MODO PACK sobrevive a busca e alimenta a folha"

# agente de producao
git add lib/models/grid_entry_model.dart lib/services/pack_grid_filter.dart lib/providers/pack_grid_provider.dart lib/screens/home_screen.dart
git commit -m "feat(lote): selecao de MODO PACK sobrevive a busca e alimenta a folha"
```

---

### Task 21: a barra de seleção na tela de detalhe

**Files:**
- Modify: `lib/screens/game_detail_screen.dart`
- Modify: `test/game_detail_screen_test.dart` (três testes novos no fim, mais o `_host`)
- Modify: `lib/screens/home_screen.dart`

A seção 5 do spec de UI termina com uma frase de sete palavras que é fácil de ler sem enxergar: *"A barra existe nas duas telas, grade e detalhe, na mesma posição."*

Ela não é enfeite, e dá para ver por quê olhando o que a Task 15 já construiu. A tela de detalhe tem um checkbox ao lado do coração, e a seção 4 explica que ele existe para quem abriu um jogo poder marcá-lo sem voltar para a grade. Sem a barra, esse checkbox é meia funcionalidade: o usuário marca, **nada acontece na tela**, não há contador e não há botão, e ele tem que voltar para a grade para descobrir que a marcação valeu. Checkbox sem barra é um interruptor sem lâmpada.

**A barra da tela de detalhe não é uma barra nova.** É a mesma `SelectionBar` da Task 2, no mesmo lugar visual, com a mesma contagem e o mesmo destino. O que muda é só quem paga o `Scaffold`.

**Ela não abre a folha sozinha**, pelo mesmo motivo que `onDownload` não enfileira sozinho: a tela de detalhe não conhece a fila nem a folha. Ela recebe mais um callback, `onBatchDownload`, e o `HomeScreen` liga esse callback no mesmo `_confirmarLote` da Task 20. Uma folha, um enfileiramento, dois botões que chegam nele.

**O `HomeScreen` não desempilha a rota antes de abrir a folha.** A folha sobe por cima da tela de detalhe, e é isso mesmo: `showModalBottomSheet` usa o `Navigator` mais próximo do contexto do `HomeScreen`, que é o mesmo que está mostrando o detalhe. Desempilhar primeiro faria a tela de detalhe piscar para fora no mesmo quadro em que a folha sobe, e ainda deixaria o usuário longe do jogo que ele estava olhando. Depois de confirmar, a seleção zera, a barra some das duas telas e o detalhe continua onde estava.

- [ ] **Step 1: Escreva os três testes que falham**

Primeiro, o `_host` da Task 18 precisa do callback novo. Em `test/game_detail_screen_test.dart`, na assinatura de `_host`, acrescente um parâmetro:

```dart
Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verificacao,
}) {
```

E no `MaterialApp` do fim dele:

```dart
    child: MaterialApp(
      home: GameDetailScreen(
        entry: entrada,
        onDownload: onDownload ?? (_) {},
        onBatchDownload: onBatchDownload ?? () {},
      ),
    ),
```

O import de `SelectionBar` no topo do arquivo de teste:

```dart
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

Agora os três testes, no fim de `main`:

```dart
  testWidgets('sem seleção a tela de detalhe não mostra barra', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    // A `SelectionBar` está sempre montada e se encolhe até zero quando a
    // seleção está vazia (Task 2). Por isso o teste mede a altura em vez de
    // procurar o widget.
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('marcar pelo checkbox faz a barra aparecer com a contagem', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.text('1 selecionado'), findsOneWidget);
    expect(tester.getSize(find.byType(SelectionBar)).height, greaterThan(0));
  });

  testWidgets('o Baixar da barra é o do lote, não o do destaque', (tester) async {
    // Os dois botões dizem "Baixar" e fazem coisas diferentes: o do card
    // enfileira este jogo, o da barra abre a folha do lote. Trocar um pelo
    // outro é o erro que este teste tranca.
    final chamados = <String>[];
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      onDownload: (_) => chamados.add('destaque'),
      onBatchDownload: () => chamados.add('lote'),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byType(SelectionBar),
      matching: find.text('Baixar'),
    ));
    await tester.pump();

    expect(chamados, ['lote']);
  });
```

- [ ] **Step 2: Rode e veja falhar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `No named parameter with the name 'onBatchDownload'`.

- [ ] **Step 3: Ponha a barra na tela**

Em `lib/screens/game_detail_screen.dart`, acrescente os imports:

```dart
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

Acrescente o campo, logo abaixo de `onDownload`:

```dart
  /// O que fazer quando o usuário aperta Baixar **na barra do rodapé**, que é
  /// o lote e não este jogo.
  ///
  /// Callback pelo mesmo motivo de [onDownload]: esta tela não conhece a fila
  /// nem a folha de confirmação. Quem liga é o `HomeScreen`.
  final VoidCallback onBatchDownload;
```

E no construtor:

```dart
  const GameDetailScreen({
    super.key,
    required this.entry,
    required this.onDownload,
    required this.onBatchDownload,
  });
```

No `build`, a linha que hoje calcula `selecionado` passa a guardar o conjunto inteiro, porque a barra precisa da contagem e o checkbox precisa da pertinência:

```dart
    final selecionadas = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final selecionado = selecionadas.contains(chave);
```

E o `Scaffold` da tela ganha a barra:

```dart
      bottomNavigationBar: SelectionBar(
        // `pack: true` literal, e não lido do `gridModeProvider`: esta tela
        // só existe em MODO PACK, porque só `PackGrid` a empurra. Ler o modo
        // aqui daria a impressão falsa de que ela abre em MODO FONTE.
        count: selectionKeysFor(selecionadas, pack: true).length,
        onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
        onDownload: onBatchDownload,
      ),
```

`bottomNavigationBar` e não um `Column` no corpo, de propósito: é ele que garante que a barra fique colada embaixo sem competir com o scroll do conteúdo, e que o teclado não a empurre para fora.

- [ ] **Step 4: Rode e veja passar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: `+31`, zero falha. São os 28 que as Tasks 15, 16 e 18 deixaram neste arquivo, mais os 3 desta.

- [ ] **Step 5: Ligue o callback no `HomeScreen`**

Em `lib/screens/home_screen.dart`, `_abrirDetalhe` ganha o terceiro argumento:

```dart
  void _abrirDetalhe(PackGridEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        entry: entry,
        onDownload: _baixarUm,
        onBatchDownload: () => _confirmarLote(_selecaoDoModo),
      ),
    ));
  }
```

E acrescente o getter que a linha acima usa, junto dos outros métodos privados:

```dart
  /// A seleção do modo corrente, lida na hora do toque.
  ///
  /// O `build` calcula a mesma coisa para a contagem da barra, mas o lote lê
  /// aqui, e não daquele valor, porque a folha pode ser aberta pela tela de
  /// detalhe, que fica **em cima** desta. Ler no momento do toque tira a
  /// pergunta "aquele valor ainda é o de agora" do caminho.
  Set<String> get _selecaoDoModo => selectionKeysFor(
        ref.read(catalogProvider).selectedGames,
        pack: ref.read(gridModeProvider) == GridMode.pack,
      );
```

E a `SelectionBar` do próprio `HomeScreen` passa a usar o mesmo getter, para não haver dois caminhos até o lote:

```dart
          SelectionBar(
            count: selecionadas.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmarLote(_selecaoDoModo),
          ),
```

A variável `selecionadas` do `build`, que a Task 20 criou, continua existindo e continua servindo **só** para a contagem.

- [ ] **Step 6: Confira à mão**

```bash
flutter run -d linux
```

1. Num console com pacote, abra um jogo pelo toque no tile. Não há barra roxa.
2. Marque o checkbox ao lado do coração. A barra roxa sobe no rodapé da tela de detalhe, dizendo "1 selecionado".
3. Volte para a grade. A barra continua lá, com a mesma contagem e na mesma posição.
4. Abra outro jogo, marque, e aperte Baixar **na barra**. A folha do lote sobe por cima da tela de detalhe, com os dois jogos.
5. Confirme. Os dois entram na fila, a barra some e a tela de detalhe continua aberta.
6. Aperte o Baixar **do card de destaque**. Só aquele jogo entra na fila, sem folha nenhuma.

- [ ] **Step 7: Prove que não quebrou nada**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Esperado: 22 findings e zero erro; `+333 -1` na suíte, sendo os 330 da Task 20 mais os 3 desta.

- [ ] **Step 8: Commit**

```bash
# agente de teste
git add test/game_detail_screen_test.dart
git commit -m "test(selecao): barra de selecao na tela de detalhe abre a folha do lote"

# agente de producao
git add lib/screens/game_detail_screen.dart lib/screens/home_screen.dart
git commit -m "feat(selecao): barra de selecao na tela de detalhe abre a folha do lote"
```

---

### Task 22: varredura de regressão e critério de aceitação

**Files:** nenhum, se tudo estiver certo. Esta Task não escreve código: ela confere. Se algum passo falhar, o conserto é feito aqui e vira commit; se nada falhar, ela fecha a fatia sem commit nenhum.

**A promessa desta fatia é dupla.** A metade fácil de provar é "a grade de pack funciona", e os 155 testes novos cuidam dela. A metade difícil é **"o MODO FONTE continua sendo o app de hoje"**, que nenhum teste novo prova, porque um teste que passa hoje e passaria igual com a grade quebrada não prova coisa alguma. Essa metade se prova por diff e a olho, e é isso que esta Task é.

**O commit de linha de base é `f9da109`** (`fix(rede): teto de tempo no httpFetch do MetadataPackService`), o `HEAD` do repositório no momento em que este plano foi escrito, antes do primeiro commit da fatia 3. Se você precisar confirmar por conta própria: é o último commit cuja árvore não contém `lib/widgets/footer/selection_bar.dart`.

- [ ] **Step 1: Prove que o intocado ficou intocado**

```bash
git diff --stat f9da109 -- \
  lib/widgets/game_grid/game_grid_item.dart \
  lib/widgets/game_grid/game_grid.dart \
  lib/widgets/game_grid/game_cover_flow.dart \
  lib/services/filtering_service.dart \
  lib/services/task_queue_service.dart \
  lib/widgets/footer/footer.dart \
  lib/widgets/game_list/
```

Esperado: **saída completamente vazia**, sem uma linha. Não "poucas linhas", não "só um import": zero.

Os três primeiros e o `filtering_service` são a "Terceira decisão travada", e o motivo está lá: `Game` sintético envenena `gameStateProvider` e os filtros. Os dois do meio estão na tabela de "Modificados" com a coluna dizendo "nenhuma", de propósito, porque em algum momento alguém vai querer um `startDownloadsFromPicks` de uma linha ou vai querer enfiar a barra de seleção dentro do `Footer`. `game_list/` é o que a seção 12 do spec de UI deixa fora de escopo.

Se aparecer qualquer coisa aqui, **o conserto é reverter aquele arquivo**, não justificar a mudança:

```bash
git checkout f9da109 -- <o arquivo>
flutter analyze && flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Se depois de reverter alguma coisa quebrar, então a fatia criou uma dependência que não devia existir, e isso é achado de QA, não detalhe de implementação. Escreva o que quebrou antes de mexer em mais alguma coisa.

- [ ] **Step 2: Prove que nada mais de produção antigo foi tocado**

```bash
git diff --name-only f9da109 -- lib/ | sort
```

A saída tem que ser exatamente estas dezoito linhas, nem uma a mais:

```
lib/models/grid_entry_model.dart
lib/models/source_pick_model.dart
lib/models/source_verification_model.dart
lib/providers/catalog_provider.dart
lib/providers/owned_games_provider.dart
lib/providers/pack_grid_provider.dart
lib/providers/source_verification_provider.dart
lib/screens/game_detail_screen.dart
lib/screens/home_screen.dart
lib/services/pack_grid_filter.dart
lib/services/source_index.dart
lib/services/source_pick_service.dart
lib/services/source_verification_service.dart
lib/widgets/footer/selection_bar.dart
lib/widgets/game_grid/batch_confirm_sheet.dart
lib/widgets/game_grid/pack_grid.dart
lib/widgets/game_grid/pack_grid_item.dart
lib/widgets/header/header.dart
```

São os quinze arquivos novos da tabela de "Estrutura de arquivos" mais os três antigos modificados: `catalog_provider.dart` (Task 1), `header.dart` (Tasks 3 e 19) e `home_screen.dart` (Tasks 3, 6, 19 e 20).

Qualquer linha extra é um arquivo de produção que a fatia tocou sem estar no plano. Não é automaticamente errado, mas é automaticamente **não planejado**, e tem que ser explicado por escrito no relatório do QA, com o motivo e o commit em que entrou.

- [ ] **Step 3: Prove que os testes novos são os previstos**

```bash
git diff --name-only f9da109 -- test/ | sort
```

Esperado, dezesseis linhas:

```
test/batch_confirm_sheet_test.dart
test/catalog_selection_test.dart
test/game_detail_screen_test.dart
test/grid_entry_model_test.dart
test/header_filter_label_test.dart
test/owned_games_provider_test.dart
test/pack_grid_filter_test.dart
test/pack_grid_item_test.dart
test/pack_grid_provider_test.dart
test/pack_grid_test.dart
test/selection_bar_test.dart
test/source_index_test.dart
test/source_pick_model_test.dart
test/source_pick_service_test.dart
test/source_verification_provider_test.dart
test/source_verification_service_test.dart
```

Nenhum arquivo de teste **antigo** pode aparecer nessa lista. Se aparecer, alguém consertou um teste velho para acomodar a fatia, e isso é exatamente a regressão que o Step 1 procura, só que disfarçada de teste verde.

- [ ] **Step 4: Analise**

```bash
flutter analyze 2>&1 | tail -30
```

Esperado: `22 issues found.` e zero `error`. Confira a quebra contra a tabela de "Antes de começar": 11 `avoid_print` em `tool/verify_matcher.dart`, 1 em `tool/probe_zip_cd.dart`, 6 `deprecated_member_use` em `network_address_setting.dart`, 2 `use_build_context_synchronously` em `fbi_server_screen.dart`, 1 `unnecessary_non_null_assertion` em `webdav_server_test.dart`, 1 `dangling_library_doc_comments` em `rom_search.dart`.

O critério é **22, e nenhum finding em arquivo tocado por esta fatia**. Para conferir a segunda metade sem ler as 22 linhas uma a uma:

```bash
flutter analyze 2>&1 | grep -E 'grid_entry|source_pick|source_index|pack_grid|source_verification|selection_bar|batch_confirm|game_detail|home_screen|header\.dart|catalog_provider|owned_games'
```

Esperado: **saída vazia**. Se sair alguma coisa, conserte, mesmo que o total continue 22, porque "trocamos um finding antigo por um novo" não é o critério.

O suspeito mais provável é `use_build_context_synchronously` em `home_screen.dart`, vindo de um `await` sem `if (!mounted) return;` depois. A Task 6 explica onde eles vão e por que `mounted` e não `context.mounted` num `State`.

- [ ] **Step 5: Rode a suíte inteira**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Esperado: `+333 -1`. A única falha é `test/rar_decompress_screen_test.dart`, no caso `renders with extract disabled until a file and folder are picked`, a mesma de antes da fatia 1. **Se houver duas falhas, a fatia não está pronta**, mesmo que a segunda pareça sem relação.

A conta dos 330, para o caso de o número não bater e você precisar saber onde procurar:

| Task | Novos | Acumulado |
| --- | --- | --- |
| linha de base | — | 178 |
| 1, `clearSelection` | 2 | 180 |
| 2, `SelectionBar` | 4 | 184 |
| 3, fiação | 0 | 184 |
| 4, `BatchPlan` | 6 | 190 |
| 5, folha de lote | 8 | 198 |
| 6, `planFromGames` | 4 | 202 |
| 7, `PackGridEntry` | 4 | 206 |
| 8, `SourceIndex` | 7 | 213 |
| 9, `filterPackEntries` | 7 | 220 |
| 10, providers | 7 | 227 |
| 11, `PackGridItem` | 11 | 238 |
| 12, `PackGrid` | 7 | 245 |
| 13, jogos no disco | 10 | 255 |
| 14, `planFromEntries` | 11 | 266 |
| 15, tela de detalhe | 9 | 275 |
| 16, sem fonte e outras fontes | 11 | 286 |
| 17, verificação por CRC | 16 | 302 |
| 18, CRC na tela de detalhe | 18 | 320 |
| 19, roteamento de modo | 2 | 322 |
| 20, lote de MODO PACK | 8 | 330 |
| 21, barra na tela de detalhe | 3 | 333 |

- [ ] **Step 6: Regressão de MODO FONTE, à mão**

```bash
flutter run -d linux
```

Escolha um console **sem** metadata pack e faça o roteiro do app de hoje. Nada aqui pode estar diferente de antes da fatia 1, com a **única** exceção anotada:

1. A grade desenha os arquivos da listagem, com capa, tags e barra de progresso como sempre.
2. O botão de trocar visualização alterna grade, lista e coverflow, e os três desenham.
3. A caixa de busca filtra.
4. A folha de filtro abre pelo funil, os chips de região, revisão e qualidade de dump filtram a grade, e o funil fica aceso quando há filtro ativo. O tooltip dele é `Filters`.
5. Marcar um jogo e baixar funciona, o download aparece no rodapé, a barra de progresso anda, o arquivo chega ao disco.
6. **A exceção:** o botão de download do header não existe mais, e no lugar dele há a barra roxa no rodapé, que abre uma folha de confirmação antes de enfileirar. É a Task 3 mais a Task 6, é a seção 5 do spec de UI, e é a única mudança visível de MODO FONTE nesta fatia inteira.

- [ ] **Step 7: Cobertura do spec, seção a seção**

Abra `docs/stremio-de-jogos-ui.md` e confira que cada seção do escopo desta fatia tem onde apontar:

| Seção do spec de UI | Onde foi feita |
| --- | --- |
| 3.1, o tile marca só a exceção | Task 11, e a "Armadilha de leitura" no topo deste plano |
| 3.2, faixa de estado vazio | Task 12 |
| 4, borda de "já baixado" | Task 13 |
| 4, seleção: gestos e checkbox | Tasks 11 e 12 na grade, Task 15 na tela de detalhe. O hover do desktop é divergência anotada na Task 11 |
| 5, barra de seleção | Tasks 1, 2, 3 e 21 |
| 6, folha de confirmação de lote | Tasks 4, 5, 6, 14, 20 e 21 |
| 7, tela de detalhe | Tasks 15 e 16 |
| 8, verificação por CRC | Tasks 17 e 18 |
| 11, tabela de arquivos | "Estrutura de arquivos" no topo, com as três divergências deliberadas anotadas lá |
| 12, fora de escopo | Steps 1, 2 e 3 desta Task |

As seções 9 e 10 são das fatias 4 e 6. Se você chegou aqui e alguma linha da tabela acima não tem para onde apontar, o buraco é da fatia, não do relatório.

- [ ] **Step 8: Feche**

Se os sete passos acima passaram, não há o que commitar: a fatia já está toda em commits das Tasks 1 a 21. Escreva o relatório com a saída **inteira** de cada comando dos Steps 1 a 5, colada, não resumida.

Se algum passo exigiu conserto, o commit é um só e leva o escopo do que foi consertado:

```bash
git add <só os arquivos consertados>
git commit -m "fix(<escopo>): <o que a varredura de regressão pegou>"
```

E rode os Steps 4 e 5 de novo depois do conserto. Um conserto que não foi reanalisado e retestado não conta.
