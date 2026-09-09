# Stremio de Jogos: design

Data: 2026-09-09
Status: proposta, aguardando revisão

## 1. Problema

Hoje o `retro_toolbox` é um downloader. A grade mostra **o que a fonte tem**: uma listagem
de arquivos crus, com nomes de dump, sem capa confiável, sem sinopse, sem noção de "jogo".
Se a fonte cai ou muda, a grade some.

O objetivo é inverter isso. A grade passa a mostrar **o catálogo do console**, todos os jogos,
com capa e sinopse, e a fonte vira um detalhe: um badge de disponibilidade e um botão de
download. Jogo sem fonte continua na grade, apenas sem o botão.

É o modelo do Stremio: catálogo estável no centro, addons plugados em volta.

## 2. Decisões travadas

Estas decisões foram tomadas durante o brainstorm e são premissas do resto do documento.

| Decisão | Motivo |
| --- | --- |
| **Sem login em lugar nenhum** | IGDB e afins exigem chave de API e servidor. Packs estáticos por console, gerados por GitHub Action, publicados em GitHub Releases. O app fica offline e sem backend. |
| **Grade mostra tudo, com badge de disponibilidade** | Jogo sem fonte aparece com capa e sinopse. O catálogo é do console, não da fonte. |
| **O app não pode shipar com origem de jogos** | Fonte é addon instalado pelo usuário. Nenhuma URL de ROM no binário nem nos assets. |
| **O addon é burro** | Devolve listagem crua e não declara identidade. Quem adivinha qual jogo é cada arquivo é o app. |
| **O `consoles.json` de hoje tem que virar addon** | Compatibilidade retroativa é requisito, não cortesia. |
| **"Onde comprar" está fora de escopo** | Não existe fonte viável de disponibilidade comercial para retro. |
| **OpenVGDB entra mesmo sem licença** | Decisão explícita do usuário. Mitigação na seção 9. |

## 3. Arquitetura

```
   GitHub Action (mensal)                        GitHub Release
   libretro-database (DAT)      ---->            pack por console
   libretro-thumbnails (URL)                     snes.json.gz
   OpenVGDB (sinopse via CRC)                    megadrive.json.gz
                                                 ...
                                                       |
                                                       | download, cache local
                                                       v
   +---------------------------------------------------------------+
   |                            APP                                 |
   |                                                                |
   |   Metadata Pack  ----> GRADE  <---- badge de disponibilidade    |
   |   (2415 jogos)          |                    ^                 |
   |                         |                    |                 |
   |                         |              Matcher (nome, tiers)    |
   |                         |                    ^                 |
   |                         v                    |                 |
   |                  tela do jogo          listagem crua            |
   |                         |                    ^                 |
   |                         |                    |                 |
   |                   SourceResolver             |                 |
   |                   "me dá uma URL HTTPS"      |                 |
   |                    /      |      \           |                 |
   |              Http    WebSeed    Debrid       |                 |
   |                    \      |      /           |                 |
   |                         v                    |                 |
   |            background_downloader             |                 |
   |            unzip / nsz / cia / CRC32         |                 |
   +---------------------------------------------------------------+
                              ^                    ^
                              |                    |
                        Accounts             Addon instalado
                   (secure storage)          (consoles.json)
```

Quatro subsistemas independentes, cada um com um spec e um plano próprios:

1. **Metadata Pack**: como o pack é construído e consumido.
2. **Identidade**: como um arquivo da fonte vira um jogo do pack.
3. **Addon e Accounts**: formato do addon, instalação, credenciais.
4. **SourceResolver**: como um item da listagem vira uma URL baixável.

## 4. Subsistema 1: Metadata Pack

### 4.1 Fontes

| Fonte | O que dá | Licença |
| --- | --- | --- |
| libretro-database, pasta `metadat` | esqueleto (nome canônico, CRC32, MD5, SHA1, serial), gênero, developer, publisher, ano, franquia, ESRB | CC BY-SA 4.0 |
| libretro-thumbnails | URL de capa em `raw.githubusercontent.com` | sem licença declarada |
| OpenVGDB v29.0 | sinopse, capa alternativa | sem licença declarada |

### 4.2 Cobertura medida

Medido sobre SNES (`Nintendo - Super Nintendo Entertainment System`, DAT v2026.08.01):

| Campo | Cobertura |
| --- | --- |
| Esqueleto (nome, hashes) | 100% |
| Gênero, developer, publisher | ~90% |
| Capa, libretro-thumbnails | 86.8% |
| Capa, OpenVGDB | 75.6% |
| Capa, união das duas | **89.6%** |
| Sinopse, OpenVGDB via join por CRC32 | **75.3%** (90.9% dos que dão join) |

Alternativa testada e descartada: Wikipedia/Wikidata via SPARQL, licença limpa CC BY-SA,
mas só **31.1%** de cobertura com join fuzzy por nome. Não substitui.

### 4.3 Cobertura por console

**24 dos 25 consoles** do catálogo do usuário têm DAT no libretro-database.
O Wii U vem de `metadat/no-intro/Nintendo - Wii U (Digital).dat` (3373 jogos), caminho
não óbvio. **Só o Nintendo Switch não tem pack**, e é tratado pela degradação da seção 7.

### 4.4 Formato e distribuição

Um arquivo por console, `<console_id>.json.gz`, publicado em GitHub Release com tag por data.
O app baixa sob demanda no primeiro acesso ao console e cacheia localmente.

O pack guarda **URL de capa, nunca o binário da imagem**. Isso é o que resolve o problema de
licença da seção 9: o app faz hotlink, exatamente como o navegador faria.

Campo por jogo:

```json
{
  "id": "snes/chrono-trigger",
  "title": "Chrono Trigger",
  "dumps": [
    { "name": "Chrono Trigger (USA)", "crc": "2D206BF7", "sha1": "...", "serial": null }
  ],
  "cover": "https://raw.githubusercontent.com/libretro-thumbnails/...",
  "synopsis": "...",
  "genre": "Role-Playing",
  "developer": "Square",
  "publisher": "Square",
  "year": 1995
}
```

O `id` é o namespace público compartilhado, o análogo do `tt` do IMDb no Stremio. É ele que
acopla pack, grade, favoritos e biblioteca local.

## 5. Subsistema 2: Identidade

Este é o subsistema de maior risco e foi validado por prova de conceito antes do desenho.

### 5.1 Dois eixos, não um

- **Nome normalizado** casa catálogo com fonte remota. É o que dá para fazer **antes** de baixar.
- **Checksum** casa catálogo com arquivo local. É o que dá para fazer **depois** de baixar.

Confundir os dois foi o primeiro erro da PoC e vale registrar. A primeira medição contou
variantes regionais (USA, Europe, Rev 1, Beta 2) como falhas de ambiguidade e chegou a 90.83%.
Medindo no eixo certo, o de **jogo canônico**, o número real é outro.

### 5.2 Resultado da PoC no eixo correto

SNES, DAT com 4268 dumps que colapsam em **2415 jogos canônicos**, contra uma listagem real
de archive.org com 4122 arquivos:

| Tier | Arquivos | % |
| --- | --- | --- |
| 1, nome exato (rom ou game) | 3685 | 89.4% |
| 2, nome canônico | 343 | 8.3% |
| 3, fuzzy >= 0.90 | 26 | 0.6% |
| 4, sem match | 68 | 1.6% |

- **Cobertura de arquivo**: 4054 / 4122 = **98.35%**
- **Cobertura de jogo**: 2342 / 2415 = **96.98%**, ou seja, 73 jogos ficam sem badge

### 5.3 O piso de erro silencioso

A medição acima é o melhor caso: fonte que é espelho do No-Intro. Contra fontes não canônicas,
degradando 800 jogos sorteados (seed 20260909):

| Degradação | Acerto | **Errado** | Perdido |
| --- | --- | --- | --- |
| GoodTools `(U) [!]` | 100% | 0% | 0% |
| Sem tag de região | 100% | 0% | 0% |
| Underscore no lugar de espaço | 100% | 0% | 0% |
| Artigo movido para a frente | 78.8% | **6.1%** | 15.2% |
| Subtítulo cortado | 77.4% | **9.2%** | 13.4% |
| Subtítulo invertido | 71.9% | **12.1%** | 16.1% |

A coluna do meio é o problema. Um match errado é pior que match nenhum: o usuário baixa
outro jogo e o app afirma com confiança que está certo. **Existe um piso de erro silencioso
de cerca de 10% contra fontes não canônicas, e nenhuma heurística de nome remove isso.**

Consequência de desenho: o tier de token set foi **removido**. Rendia +0.6% de cobertura e
errava 12% do que resolvia. Trade ruim.

### 5.4 O que resolve: CRC32 por HTTP Range

Um ZIP tem o CRC32 de cada arquivo interno no diretório central, no fim do arquivo. Dá para
ler sem baixar o ZIP:

1. `Range: bytes=-256` na cauda, acha o EOCD (`PK\x05\x06`), lê offset e tamanho do diretório central.
2. `Range` no diretório central, lê as entradas (`PK\x01\x02`): CRC32 em `+16`, tamanho do nome em `+28`.

Custo medido: **duas requisições, 326 bytes, num ZIP de 3 MB.**

Testado nos 12 piores casos da PoC, aqueles que nenhum tier de nome resolveu: **12 de 12
resolvidos, 4060 bytes no total.** Exemplos:

| Nome do arquivo na fonte | Jogo real, descoberto pelo CRC |
| --- | --- |
| `Aryol (Japan).zip` | `Ugoku E Ver. 2.0 - Aryol (Japan) (En,Ja).sfc` |
| `Kaite Tsukutte Asoberu Dezaemon (Japan).zip` | `Dezaemon (Japan).sfc` |
| `Masters - Harukanaru Augusta 2 (Japan).zip` | `Harukanaru Augusta 2 - Masters (Japan).sfc` |
| `Kikou Keisatsu Metal Jack (Japan).zip` | `Armored Police - Metal Jack (Japan).sfc` |

### 5.5 Desenho final

- Tier de nome resolve a maioria e é grátis.
- Cada match carrega uma **confiança derivada do tier**. Tier 3 nunca é apresentado como certeza.
- Onde a fonte serve ZIP, o CRC32 por Range confirma ou corrige antes do download.
- Depois do download, o CRC32 do arquivo baixado é verificado contra o pack de qualquer forma.

### 5.6 Limitação conhecida: consoles de disco

Cerca de 11 dos 25 consoles servem `.iso`, `.bin`, `.rvz`, sem diretório central de ZIP.
Para esses o truque do Range não existe e o match cai nos tiers de nome, com o piso de erro
da seção 5.3. A chave correta para esses sistemas é o **serial**, que já vem no
libretro-database. Fica registrado como trabalho futuro, não faz parte da fatia 1.

## 6. Subsistema 3: Addon e Accounts

### 6.1 O addon é o `consoles.json` de hoje

Nenhum campo do `Console` muda. `Console.fromJson` fica intacto. O que existe hoje já é
quase o protocolo:

| Já existe | Onde | Análogo Stremio |
| --- | --- | --- |
| Instalação por URL | `catalog_service.dart`, `setCatalogFromUrl` | instalar addon |
| Detecção de dois formatos (List e Map) | `catalog_service.dart`, `_parseConsoles` | tolerância de versão |
| `list_systems` | `console_model.dart` | `addon_catalog` |
| `should_unzip`, `should_decompress_nsz`, `convert_3ds_to_cia`, `extract_contents` | `console_model.dart` | `behaviorHints` |
| `file_format`, `ignore_extension_filtering` | `console_model.dart` | `idPrefixes` |
| `regex`, `download_url`, `roms_folder` | `console_model.dart` | roteamento do addon |

O pós-processamento é propriedade **da fonte**, não do jogo. Isso é exatamente o papel do
`behaviorHints` no Stremio e é por isso que ele sobrevive à mudança sem alteração.

### 6.2 Accounts

O addon declara a **forma** da autenticação. Nunca o valor.

```
addon JSON                        Settings > Accounts            secure storage
------------------------          --------------------           --------------
auth: {                    -->    [ UltraNX          ]    -->    addon:<id>/ultranx
  cookies: true                     usuario  ______
  cookie_name: auth_token           senha    ______
  auth_message: "..."               [ Entrar ]
  signin: { url, params }
}
type: ia_s3                -->    [ Internet Archive ]    -->    ia/cookies
(não vem de addon)         -->    [ Real-Debrid      ]    -->    debrid/realdebrid
```

O app varre todos os addons instalados, junta todo console com `auth != null` e monta a tela.
`signinForToken` em `utils/network.dart` já implementa o fluxo de login, então o botão Entrar
do UltraNX é o que já roda hoje, só que num lugar só.

### 6.3 Correção de segurança obrigatória

Hoje o token pode morar **dentro do JSON**, que é o arquivo que o usuário compartilha.
A cadeia de fallback em `task_queue_service.dart` é:

```dart
settings.consoleSettings[console.id]?.authToken ?? console.auth?['token'] as String? ?? ''
```

É a mesma falha do Torrentio de colocar a chave na URL, só que num arquivo. No catálogo real
do usuário o campo está vazio, então nada vazou, mas o formato permite.

Duas mudanças fecham o buraco:

- `utils/network.dart`, `buildConsoleAuthHeaders`: `tokenOverride ?? auth['token']` vira só
  `tokenOverride`. O valor deixa de poder vir do arquivo.
- `task_queue_service.dart`: a cadeia perde o termo do meio.

Na instalação, se o JSON vier com `auth.token` preenchido, o app move para o
`flutter_secure_storage` e zera no arquivo salvo. Na exportação, remove.

Estado atual a corrigir: o app guarda tokens e credenciais S3 do Internet Archive em
`shared_preferences` em texto puro, sem `flutter_secure_storage`. Isso precisa ser resolvido
**antes** de introduzir chave de debrid.

## 7. Modos de grade

O addon não declara modo. O app olha se existe pack para aquele console e escolhe:

```
                    tem metadata pack para esse console?
                              /            \
                            sim            nao
                             |              |
                    MODO PACK           MODO FONTE
        grade = jogos do pack        grade = listagem do addon
        capa/sinopse = pack          capa = console.boxarts
        badge = match do subsist. 2  badge = sempre disponível
        addon só resolve download    (comportamento de hoje, intacto)
```

O MODO FONTE é a degradação graciosa. **O Switch cai nele e funciona exatamente como hoje.**
Nenhuma regressão para o único console sem pack.

## 8. Subsistema 4: SourceResolver

Uma interface, três implementações. Nada acima dela sabe o que é um torrent.

```
                        SourceResolver
                   "me dá uma URL HTTPS"
                    /        |         \
        HttpResolver   DebridResolver   WebSeedResolver
             \             |             /
              \            |            /
               download_provider.dart, ponto do resolveRedirects
                        |
        background_downloader -> unzip -> nsz -> cia -> CRC32
```

O ponto de inserção já existe: `download_provider.dart` hoje resolve redirecionamentos antes
de enfileirar, porque o downloader perde headers de auth em redirect entre hosts. É exatamente
ali que a resolução de fonte entra.

### 8.1 Item de listagem: uma forma, três backends

```json
{ "name": "Chrono Trigger (USA).zip", "url": "https://..." }
{ "name": "Chrono Trigger (USA).zip", "infohash": "a1b2...", "file_index": 1234, "size": 4194304 }
```

Só troca `url` por `infohash` mais `file_index`. **O matcher não muda uma linha.**

Isso importa porque torrent de retro não é um jogo por torrent, é o set inteiro: um magnet com
4000 ROMs. O addon publica o índice de arquivos, que ele já tem porque veio do `.torrent`,
e a grade some com a distinção.

### 8.2 HttpResolver

O que existe hoje. Cobre os 25 consoles do catálogo real do usuário: 24 apontam para
archive.org e 1, o Switch, para `api.ultranx.ru`. É o único resolver da fase 1 que já está
escrito, e a extração da interface é refatoração pura, sem mudança de comportamento.

### 8.3 DebridResolver

O que o Torrentio faz e que **não** precisamos: ele é servidor, então carrega endpoint
`/resolve`, redirect 302 em vez de proxy, blacklist de token e circuit breaker. Somos o
cliente e falamos com o Real-Debrid direto. Some tudo isso. Fica a boa ideia: a abstração de
provider e a resolução preguiçosa, nada de tocar no debrid enquanto o usuário só navega.

```
POST /torrents/addMagnet                        -> id
POST /torrents/selectFiles/{id}  { files: "1234" }   <- 4 MB de um torrent de 12 GB
GET  /torrents/info/{id}         poll até status=downloaded
POST /unrestrict/link                           -> https://xxx.download.real-debrid.com/...
```

Depois da `unrestrict/link` **não existe mais torrent, existe um link HTTPS direto**, e o
pipeline inteiro que já está escrito consome ele sem saber a diferença. Todos os flags de
pós-processamento continuam valendo, e a verificação de CRC32 contra o pack também.

O `selectFiles` por índice é o motivo de valer a pena: pegar um arquivo de um set sem baixar
o set e sem semear nada.

**Limitação conhecida**: o endpoint `/torrents/instantAvailability` do Real-Debrid está morto
(`error_code 37`). Não dá para mostrar badge confiável de "cacheado" antes de tentar. O
Torrentio contorna com cache colaborativo porque renderiza centenas de streams por título.
Nós renderizamos um jogo por vez, então a saída honesta é tentar e reportar o estado:

```
[ Baixar ]  ->  resolvendo...  ->  RD preparando 34%  ->  baixando 78%
```

Fase 1 implementa a interface `DebridClient` e só o Real-Debrid. AllDebrid, TorBox e
Premiumize ficam para depois, com a interface pronta.

### 8.4 WebSeedResolver

Torrent de arquivo carrega web seed. Verificado abrindo o bencode de um `.torrent` real do
archive.org:

```
url-list : [ https://archive.org/download/
             http://ia902907.us.archive.org/7/items/
             http://ia802907.us.archive.org/7/items/ ]
```

Isso é o BEP 19. A chave fica **fora** do bloco `info`, então não afeta o infohash. O spec
define o servidor HTTP como um seed permanentemente unchoked: com zero peers conectados dá
para satisfazer 100% das peças por `Range` request, com verificação SHA-1 por peça de graça.

Custo: algumas centenas de linhas, nenhuma dependência nativa.

Observação importante: para o archive.org, `url-list` resolve para a mesma URL que o app já
baixa hoje. Ou seja, **torrent de fonte arquivística não adiciona nada**, e o addon deveria
simplesmente apontar para a URL HTTP. O `WebSeedResolver` só ganha valor em torrents de
outras origens que tragam `url-list`.

### 8.5 P2P nativo fica fora da fase 1

Levantamento do ecossistema em 2026-09-09:

| Opção | Veredito |
| --- | --- |
| `dtorrent_task` 0.4.1, 31 stars | **não serve.** Sem download seletivo por índice, sem web seed, e não parseia URI magnet, só infohash hex. Nosso modelo inteiro é "um arquivo de um set" |
| `dtorrent_task_v2` 0.5.4 | tem as duas coisas implementadas de verdade, mas 6 stars, um autor, zero pacotes publicados dependem dele, e lista 30+ BEPs de forma implausível para um fork de 10 meses |
| `libtorrent_flutter`, `better_libtorrent_flutter`, `libtorrent_dart` | os três nasceram em 2026, todos sem adoção. Baixam de 10 a 80 MB de binário nativo pré-compilado, não assinado, de um GitHub Release pessoal, na hora do build |
| `libtorrent4j` | maduro e vivo, é o que o LibreTorrent usa, mas Java/Android. Mata o multiplataforma |

Bloqueios que **não** existem: a política da Play Store não menciona torrent (LibreTorrent,
uTorrent e Flud estão publicados). A rejeição de facto da Apple não afeta o projeto, que tem
`android/`, `linux/`, `macos/` e `windows/` e **não tem iOS**.

O bloqueio que existe e não é técnico: torrent significa que o usuário sobe. Debrid significa
que não.

Resumo da resposta a "torrent sem debrid": funciona quando o torrent tem web seed, e nesse
caso é a mesma coisa que HTTP. Sem web seed e sem debrid, o badge honesto é
"requer Real-Debrid". A interface acima permite trocar isso depois sem mexer na grade, no
matcher nem no pipeline.

## 9. Licenciamento

| Fonte | Situação | Tratamento |
| --- | --- | --- |
| libretro-database | CC BY-SA 4.0, copyleft | O pack herda a licença e carrega atribuição. Publicado como CC BY-SA 4.0. |
| libretro-thumbnails | **Sem licença declarada.** O README diz que a arte pertence aos publishers e credita MobyGames e Fandom | O pack guarda **só a URL**. O app faz hotlink. Nenhuma imagem é redistribuída. |
| OpenVGDB | **Sem licença declarada.** Congelado na v29.0, 2021-11-11 | Decisão explícita do usuário de usar assim mesmo. Mitigação: o app baixa direto do Release do próprio OpenVGDB, em vez de o pack redistribuir o conteúdo. |

O risco de OpenVGDB e libretro-thumbnails é assumido conscientemente. Está documentado aqui
para que a decisão seja rastreável, não para ser rediscutida.

## 10. Fora de escopo

- **Onde comprar.** Não existe fonte de disponibilidade comercial para retro. Confirmado com o usuário.
- **Login IGDB.** Substituído por packs estáticos.
- **Cliente BitTorrent embutido.** Seção 8.5.
- **Match por serial em consoles de disco.** Seção 5.6.
- **AllDebrid, TorBox, Premiumize.** Interface pronta, implementação depois.

## 11. Riscos

| Risco | Probabilidade | Mitigação |
| --- | --- | --- |
| Match errado silencioso em fonte não canônica | Alta, ~10% medido | CRC32 por Range onde há ZIP, confiança por tier na UI, tier de token set removido |
| Consoles de disco sem CRC por Range | Certa, ~11 de 25 | Aceito na fase 1, serial como trabalho futuro |
| libretro-thumbnails ou OpenVGDB saem do ar | Média | Capa por hotlink degrada para placeholder, pack continua funcionando |
| Real-Debrid muda a API de novo | Média, já aconteceu com `instantAvailability` | `DebridClient` como interface, normalização de erro |
| Credencial vaza em catálogo compartilhado | Já possível hoje | Seção 6.3, obrigatória antes de qualquer credencial de debrid |

## 12. Decomposição

Cada fatia é um spec e um plano próprios, na ordem:

1. **Metadata Pack**: GitHub Action, formato, publicação, download e cache no app.
2. **Identidade**: matcher por tiers, CRC32 por Range, confiança na UI.
3. **Grade e modos**: MODO PACK e MODO FONTE, badge de disponibilidade, tela do jogo.
4. **Addon e Accounts**: tela de contas, migração de token para secure storage, correção da seção 6.3.
5. **SourceResolver**: extração da interface, `HttpResolver` a partir do código atual.
6. **Debrid**: `DebridClient`, Real-Debrid, item de listagem com `infohash`.

A fatia 4, na parte da seção 6.3, é pré-requisito da fatia 6.

## Apêndice: artefatos da PoC

Scripts em `/tmp/match-poc/`, fora do repositório:

- `match.py`: primeira medição, no eixo errado (dump individual). 90.83%.
- `match2.py`: medição no eixo de jogo canônico. 98.35% de arquivo, 96.98% de jogo.
- `match3.py`: robustez contra fontes não canônicas, seis degradações, seed 20260909.
