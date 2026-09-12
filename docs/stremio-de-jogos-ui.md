# Stremio de Jogos: UI

Data: 2026-09-10
Status: proposta, aguardando revisão
Complementa: `docs/stremio-de-jogos-design.md`

## 1. Escopo

Este documento define a interface. A arquitetura está no spec irmão e não é repetida aqui.

Quase tudo abaixo vale para o **MODO PACK** (seção 7 do spec de arquitetura). No **MODO
FONTE**, que hoje é só o Switch, a grade continua exatamente como está: listagem crua, botão
de download por tile, nenhuma mudança. Console sem pack não é afetado por este documento.

Duas coisas valem para os dois modos, porque não dependem de pack: a barra de seleção no
rodapé (seção 5) e a folha de confirmação de lote (seção 6). A seleção múltipla já existe
hoje, com o botão "Download Selected" no header, e essas duas seções melhoram o que já está lá.
Da seção 4, o toque curto é MODO PACK, porque só ali existe tela de detalhe para abrir. O resto
da seção 4 vale para os dois.

## 2. Decisões travadas

| Decisão | Motivo |
| --- | --- |
| **Toque curto sempre abre a tela de detalhe** | O significado do toque nunca muda. Isso elimina "modo de seleção" e, junto com ele, a barra contextual que substituiria o header. |
| **Seleção é estado que sobrevive à navegação** | O usuário seleciona, abre um jogo, lê a sinopse, volta e continua selecionando. Já é assim no estado (`catalogProvider.selectedGames`), passa a ser assim na UI. |
| **Contador de seleção mora numa barra fixa no rodapé** | Mesma posição na grade e no detalhe, impossível não ver. O `×` à esquerda limpa a seleção. |
| **A barra de seleção empilha em cima do rodapé de tarefas** | As duas coisas ficam ativas ao mesmo tempo e nenhuma esconde a outra. |
| **Lote é regra mais confirmação** | O app escolhe a versão por regra determinística e mostra o resultado antes de enfileirar, com override por item. |
| **O detalhe destaca a melhor escolha e colapsa o resto** | Um toque no caso comum, expansão para quem quer escolher. |
| **O tile marca só a exceção** | 96,98% dos jogos têm fonte. Marcar quem tem fonte é ruído em 97% das capas. |
| **Confiança de match não aparece no tile** | Confiança é propriedade da fonte, e fonte só aparece no detalhe. O jogo existe, o que é incerto é uma das fontes dele. |
| **Match incerto é resolvido por CRC ao abrir o detalhe** | 2 requisições `Range`, 326 bytes. Melhor do que pedir para o usuário adivinhar por nome de arquivo. |
| **Addon tem tela de detalhe própria** | Cobertura, conta, prioridade e remoção num lugar só. Accounts continua sendo o cofre único e vira a visão consolidada. |
| **Prioridade entre fontes é manual, por arrasto** | O app não tem como calcular "melhor fonte": não sabe qual servidor é mais rápido nem qual dump é mais confiável. |
| **Debrid resolve dentro da tarefa, não bloqueando a tela** | É a única opção que funciona em lote, e a fila já é onde coisa demorada mora no app. |

## 3. A grade

### 3.1 O tile

O tile passa a representar um **jogo**, não um arquivo. Três consequências em
`game_grid_item.dart`:

1. As tags de disco, revisão e região (`:123-186`) saem do tile. Elas descrevem uma versão, e
   a versão agora é escolhida na tela de detalhe.
2. O `GameActionButtons` no canto superior direito (`:210-230`) sai. O tile não sabe mais qual
   arquivo baixar, então não pode ter botão de baixar.
3. O tile ganha `onTap`, que abre o detalhe, e `onLongPress`, que seleciona.

O que o tile mostra: capa, título sobreposto, a marca de "sem fonte" quando for o caso, o
checkbox de seleção quando houver seleção ativa, a borda de estado que já existe (`:34-46`) e
a barra de progresso que já existe (`:187-205`).

**Marca de "sem fonte"**: capa dessaturada mais um ícone (`Icons.cloud_off_rounded`) no canto
superior direito. Dois sinais redundantes de propósito, porque cinza sozinho é ambíguo com
"carregando" e várias capas de época já são quase monocromáticas. Quem tem fonte não ganha
marca nenhuma.

Contagem de fontes **não** aparece no tile. Ela aparece no detalhe, como "outras N fontes".

**A borda de "já baixado" muda de significado.** Hoje ela reflete um arquivo:
`library_snapshot_provider.dart` indexa o diretório por nome exato e base name, e o nome na
grade é o nome no disco. Em MODO PACK o tile é um jogo, então a borda passa a significar
"você tem alguma versão deste jogo". Isso exige mapear arquivo local de volta para jogo
canônico, com a regra de nome primeiro e CRC só na dúvida da seção 5.7 do spec de arquitetura.
Enquanto o scan roda, o tile não mostra borda nenhuma, nunca uma borda errada.

### 3.2 Estados vazios

O argumento de "marcar só a exceção" depende de a maioria ter fonte, e isso depende do addon
instalado. Com nenhum addon instalado, 100% dos jogos seriam exceção, o que é absurdo.

Regra: se **nenhum addon está instalado**, a grade não marca tile nenhum. Ela mostra uma faixa
no topo, "nenhuma fonte instalada", com atalho para a tela de addons. Isso é estado vazio da
grade, não estado do tile.

Se há addon instalado mas ele não cobre o console atual, a faixa é a mesma com texto diferente:
"nenhum addon instalado cobre este console".

## 4. Seleção

Não existe modo de seleção. A seleção é um estado, ela sobrevive à navegação e o toque curto
nunca muda de significado.

| Gesto | Efeito |
| --- | --- |
| Toque curto no tile | Abre a tela de detalhe. Só em MODO PACK: em MODO FONTE o tile não tem toque curto hoje e continua sem |
| Toque longo no tile | Alterna a seleção daquele jogo |
| Clique no checkbox | Alterna a seleção daquele jogo |
| `×` na barra do rodapé | Limpa a seleção inteira |

**Visibilidade do checkbox.** Hoje o checkbox aparece sempre que o jogo é interagível
(`game_grid_item.dart:69`). Passa a aparecer só quando a seleção não está vazia, em **todos**
os tiles, até a seleção zerar. Capa limpa enquanto ninguém selecionou nada, descoberta óbvia
depois do primeiro toque longo. No desktop ele também aparece no hover do tile, com seleção
vazia ou não.

**Entrar na seleção a partir do detalhe.** A tela de detalhe tem um checkbox ao lado do
coração de favorito, no mesmo canto. Sem ele, o usuário que abriu um jogo teria que voltar
para a grade só para selecionar.

## 5. A barra de seleção e o rodapé

O rodapé de tarefas já existe e já é ocupado (`footer.dart`): à esquerda "Downloading N,
Extracting M" e a contagem de jogos, à direita a barra de progresso e o diretório, no meio a
seta que abre o `TaskPanelModal`.

A barra de seleção senta **em cima** dele, como uma segunda faixa, em roxo sólido. Ela aparece
quando há seleção e some quando zera. As duas podem estar ativas ao mesmo tempo, porque
selecionar 3 jogos enquanto outros 2 baixam é o caso normal.

```
+-----------------------------------------------+
|  ×  3 selecionados              [ Baixar ]    |  <- roxo, some quando zera
+-----------------------------------------------+
|  Downloading 2, Extracting 1   ====  /roms    |  <- footer.dart, intacto
+-----------------------------------------------+
```

Custo aceito: com seleção ativa, some com uma fileira de capas no celular.

A barra existe nas duas telas, grade e detalhe, na mesma posição.

**Consequência no header**: o botão "Download Selected" (`header.dart:186-194`) sai. A barra do
rodapé faz a mesma coisa, em lugar mais visível e com o contador junto. Dois botões para a
mesma ação é pior do que um.

## 6. Lote: regra mais confirmação

Ao tocar em Baixar com N jogos selecionados, o app escolhe uma versão por jogo com esta regra,
nesta ordem:

1. **Região preferida**, lida do filtro que já existe (`catalog_filter_model.dart`, `regions`,
   padrão `{'USA'}`).
2. **Maior revisão**.
3. **Maior confiança de match**.
4. **Prioridade do addon**, a ordem manual da seção 9.

Antes de enfileirar, uma folha de confirmação: "40 jogos, 1.2 GB", a lista do que foi escolhido
e override por item. Jogos sem fonte e jogos onde a regra não achou candidato aparecem
separados, com o motivo, e não entram na fila.

A regra é a mesma que escolhe o destaque da tela de detalhe. Uma regra só, dois lugares.

**O lote não verifica CRC antes de enfileirar.** A verificação da seção 8 custa 2 requisições
por arquivo incerto, e em 40 jogos isso vira uma rajada de 80 requisições antes de o download
começar. Em vez disso, a folha de confirmação marca os itens incertos com o mesmo selo do
detalhe, e a rede de segurança é a verificação de CRC32 que o pipeline já faz **depois** do
download. Quem quiser certeza antes abre o jogo, que é exatamente o gatilho da seção 8.

## 7. A tela de detalhe

Nova tela, `lib/screens/game_detail_screen.dart`. Não é bottom sheet e não é expansão inline.

**Topo**, igual em todos os estados: capa, título, metadados (console, ano, publisher, gênero),
sinopse, coração de favorito e o checkbox de seleção.

**Corpo**, no caso comum: um card de destaque com a versão que o app escolheria, o motivo
escrito por extenso, e o botão Baixar. O resto colapsa atrás de "outras N fontes".

```
+---------------------------------------------+
| <-  Chrono Trigger              (heart) [ ] |
+---------------------------------------------+
| [capa]  Chrono Trigger                      |
|         SNES, 1995, Square, RPG             |
|         sinopse...                          |
+---------------------------------------------+
| Chrono Trigger (USA)                  HTTP  |
| 4.0 MB, Myrient                             |
| escolhido pela sua região preferida         |
| [            Baixar             ]           |
+---------------------------------------------+
| v outras 5 fontes                           |
+---------------------------------------------+
```

O motivo é obrigatório, não decorativo. Ele é a única coisa que separa "o app escolheu por
você" de "o app escolheu ao acaso".

Expandido, cada linha mostra: nome do arquivo, tamanho, addon de origem, tipo de fonte (HTTP,
SEED, RD) e o estado de confiança.

**Estado "sem fonte"**, os 3% da seção 3.1: a tela é completa e funcional. Capa, sinopse,
metadados e favorito funcionam. No lugar do card de destaque, uma faixa "nenhum addon
instalado tem este jogo" com atalho para a tela de addons. O jogo continua existindo e continua
favoritável, ele só não tem de onde vir hoje.

## 8. Confiança do match

Em torno de 10% dos matches por nome estão errados em fontes não canônicas. Destacar um
palpite com a mesma cara de uma certeza é mentira, e o app tem como não mentir.

**Ao abrir o detalhe**, para cada fonte cujo match não é confiável, o app dispara a leitura do
CRC32 pelo cabeçalho ZIP via HTTP `Range`: 2 requisições, 326 bytes por arquivo. Enquanto roda,
a fonte mostra o rótulo "verificando" e o botão diz "Baixar mesmo assim".

Ao terminar, cada fonte cai em um de três estados:

| Estado | O que aparece |
| --- | --- |
| CRC bate com o pack | Selo "CRC ok" e o motivo vira "confirmado pelo CRC, é exatamente este dump" |
| CRC não bate com nada | A fonte é descartada do destaque e desce para a lista, marcada. O contador vira "outras N fontes, 1 descartada" |
| Verificação impossível | Cai no comportamento descrito dois parágrafos abaixo |

O destaque **pode trocar de arquivo** depois da verificação. Isso é o ponto: o app corrige a
própria escolha antes de o usuário gastar banda.

**Quando a verificação é impossível** (servidor sem suporte a `Range`, arquivo que não é ZIP,
fonte de debrid ainda não resolvida), o app não destaca nada. O card vira "não tenho certeza de
nenhuma" e a lista abre expandida, com botão Baixar por linha e o selo de incerteza em cada
uma. Nunca finge certeza.

O resultado da verificação é cacheado por (fonte, arquivo), então a segunda abertura do mesmo
jogo é instantânea.

Isso é a "confiança na UI" da fatia 2 do spec de arquitetura.

## 9. Addons e contas

O app não vem com fonte nenhuma, então **instalar addon é a primeira coisa que o usuário faz**.
O encanamento de instalar por URL já existe (`setCatalogFromUrl`,
`add_catalog_source_screen.dart`), e o `consoles.json` de hoje entra como addon nº 1, no topo
da ordem. Quem já usa o app não vê diferença no dia seguinte.

**Tela de addons**, lista enxuta. Cada linha: ícone, nome, cobertura resumida ("25 consoles"),
chip de "conta" quando exige credencial, alça de arrasto e seta. No fim, "+ Instalar de URL".

**A tool "New Catalog Source" continua em Tools, onde está.** Os dois caminhos coexistem
porque servem públicos diferentes: a tool monta um console à mão, pedindo nome, pasta de ROMs,
formatos e comportamento de unzip; o "+ Instalar de URL" instala um catálogo que já vem
pronto. Custo aceito: dois caminhos que terminam no mesmo lugar. O que o console montado à mão
ganha é aparecer na lista de addons como qualquer outro, com prioridade arrastável e conta se
precisar.

O **Retro Tools Server** aparece na lista de addons de quem instalar a URL dele, e não muda
nada na tela do servidor em si. Ele é o produtor do mesmo formato, e o vínculo está na seção
6.4 do spec de arquitetura.

**Tela de detalhe do addon**, uma por addon:

- Identificação: nome e URL de origem
- **Conta**: o formulário de credencial, no formato que o addon declarar (usuário e senha,
  chave de API, chaves S3)
- **Cobertura**: quais consoles ele atende e quantos itens em cada
- **Prioridade**: a posição atual, com a instrução de arrastar na lista
- **Remover**

**Accounts** (`accounts_setting.dart`) continua sendo o cofre único e vira a visão consolidada:
todas as contas em um lugar, de addon ou não, com o estado de conexão. A mesma credencial é
editável pelos dois caminhos, e isso é o custo aceito da decisão.

**Real-Debrid não é addon, é conta.** Ele aparece em Accounts e nunca na lista de addons. Quem
produz o magnet é o addon de torrent, quem resolve o magnet em link direto é a conta. Isso
importa porque a mesma conta serve vários addons de torrent ao mesmo tempo.

**Prioridade é manual, por arrasto.** A ordem da lista é o desempate da seção 6 e do destaque
da seção 7.

Credenciais vão para `flutter_secure_storage`, nunca para o JSON compartilhável do addon nem
para `shared_preferences`. Isso é a fatia 4 do spec de arquitetura e está detalhado lá.

## 10. Debrid: a espera mora na fila

Baixar de fonte HTTP é imediato: tem URL, enfileira, pronto. Via Real-Debrid não. O app manda o
magnet, seleciona os arquivos e espera o RD baixar o torrent dos peers antes de pedir o link
direto. Em cache são segundos, fora do cache podem ser minutos ou nunca. E não dá para saber
antes: o `instantAvailability` responde `error_code 37` desde que o Real-Debrid o desligou.

**O toque em Baixar é sempre instantâneo.** A tarefa nasce na fila
(`task_queue_service.dart`) com um estado novo, "resolvendo", e vira "baixando" sozinha quando
o link sai. A tela não bloqueia e nada de modal.

Isso é obrigatório por causa do lote: selecionar 40 jogos onde alguns são RD não pode virar 40
esperas nem 40 folhas de progresso.

No rodapé, o contador ganha o estado: "Resolvendo 1, Downloading 2". A barra de progresso fica
indeterminada enquanto só há tarefa resolvendo, porque nessa fase não existe porcentagem
verdadeira do lado do app.

No `TaskPanelModal`, a linha da tarefa mostra o jogo, o addon, o tamanho e o estado.

**Falha aqui é caso comum, não exceção**: torrent sem seeds, conta sem tráfego, magnet
inválido. A tarefa falhada fica no painel com o motivo em uma linha e um botão "tentar outra
fonte", que reabre o detalhe do jogo já com a fonte que falhou riscada. Nada de sumir sozinha.

## 11. O que muda no código existente

| Arquivo | Mudança |
| --- | --- |
| `widgets/game_grid/game_grid_item.dart` | Duas variantes por modo. Em MODO PACK: sai o bloco de tags (`:123-186`), sai o `GameActionButtons` (`:210-230`), entra `onTap` e `onLongPress`, entra a marca de "sem fonte", o checkbox (`:69-84`) passa a ser condicional à seleção não vazia. Em MODO FONTE: intacto |
| `widgets/game_grid/game_grid.dart` | Faixa de estado vazio no topo quando não há addon ou o addon não cobre o console |
| `widgets/footer/footer.dart` | Barra de seleção empilhada acima, contador e `×`, estado "Resolvendo N" |
| `widgets/footer/task_list_view.dart` | Estado "resolvendo" e linha de falha com motivo e "tentar outra fonte" |
| `widgets/header/header.dart` | Sai o botão "Download Selected" (`:186-194`) |
| `widgets/settings/accounts_setting.dart` | Vira a visão consolidada de contas, incluindo debrid |
| `services/task_queue_service.dart` | Estado "resolvendo" antes de "baixando" |
| `models/catalog_filter_model.dart` | `regions` passa a alimentar a regra do lote, além do filtro |
| `providers/library_snapshot_provider.dart` | Em MODO PACK, mapeia arquivo local para jogo canônico: nome primeiro, CRC na dúvida, cache por caminho, tamanho e mtime |
| `screens/add_catalog_source_screen.dart` | Nenhuma mudança de fluxo. O console que ela cria passa a aparecer na lista de addons |
| `screens/rts_server_screen.dart` | Nenhuma mudança de tela. Só precisa emitir as extensões do formato quando elas existirem, seção 6.4 do spec de arquitetura |
| **novo** `screens/game_detail_screen.dart` | Seções 7 e 8 |
| **novo** `screens/addons_screen.dart` | Lista de addons, seção 9 |
| **novo** `screens/addon_detail_screen.dart` | Detalhe do addon, seção 9 |
| **novo** widget de folha de confirmação de lote | Seção 6 |

## 12. Fora de escopo

- **Onde comprar.** Já estava fora no spec de arquitetura, continua fora.
- **Barra contextual de seleção.** Morreu junto com o modo de seleção.
- **Badge de "cacheado no debrid".** Impossível de dar honestamente enquanto o
  `instantAvailability` estiver morto.
- **Coverflow e lista.** `ViewMode.coverflow` e `ViewMode.list` continuam existindo e
  continuam como estão. Este documento só trata da grade. Adaptá-los ao MODO PACK é trabalho
  separado.
- **Redesenho do tema.** Material 3, seed `#7C4DEF` e ChakraPetch ficam como estão.
- **Tinfoil, JDKV, FBI, SMB e FTP.** Servem arquivo para outro aparelho, não catálogo para o
  app. Intocados.
- **As tools de arquivo local.** NSZ, RAR, CHD, CIA, M3U, Collection Clean, Steam Shortcuts e
  Sports continuam como estão. Vale registrar que em MODO PACK elas ganham algo que nunca
  tiveram, um nome canônico e um CRC por jogo, mas aproveitar isso é trabalho separado.

## 13. Ordem de implementação

Este documento não vira um plano só. Ele se distribui pelas fatias do spec de arquitetura:

| Seção deste documento | Fatia |
| --- | --- |
| 8, confiança do match | Fatia 2, Identidade |
| 3.1, borda de "já baixado" | Fatia 2, Identidade |
| 3, 4, 5, 6, 7, grade, seleção, lote e detalhe | Fatia 3, Grade e modos |
| 9, addons e contas | Fatia 4, Addon e Accounts |
| 10, debrid na fila | Fatia 6, Debrid |

As seções 5 e 6, mais a parte da seção 4 que não é o toque curto, são a exceção útil: não
dependem de pack, de matcher nem de addon. Dão para ser feitas antes de tudo, isoladas, e já
melhoram o app de hoje.
