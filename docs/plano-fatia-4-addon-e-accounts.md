# Fatia 4, Addon e Accounts: plano de implementação

> **Para quem executa:** SUB-SKILL OBRIGATÓRIA: use `superpowers:subagent-driven-development` (recomendado) ou `superpowers:executing-plans` para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Goal:** tirar todo segredo de dentro do arquivo que o usuário compartilha, e trocar a fonte de catálogo única de hoje por uma lista ordenada de addons, cuja ordem é o desempate que a fatia 3 já sabe consumir.

**Architecture:** duas metades que se encontram no fim. A primeira é o cofre: uma interface `SecretVault` de duas implementações, a de sistema e a de reserva, com uma migração que roda uma vez e esvazia os segredos do `shared_preferences`. A segunda é o addon: um `Addon` com id próprio, uma lista ordenada que substitui o `catalogSourceUrl` único, e um `CatalogService` que funde N addons num `Map<String, Console>` somando URLs por console em vez de brigar por id. As duas se encontram porque a credencial é chaveada por `addon:<id>/<console>`, e é isso que faz dois addons servindo o mesmo console não dividirem o mesmo token.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod: ^2.6.1`), `flutter_test` sem mockito, injeção por construtor. **Uma dependência nova:** `flutter_secure_storage`. É a única de toda a fatia.

**Commit de base:** `ef5ee57`. A Task final mede a fatia inteira contra esse hash, então ele é imutável enquanto a fatia estiver aberta: nada de rebase, amend ou filter-branch que o alcance.

**Baseline medido em `ef5ee57`:** `flutter test` dá `+340`, zero falha. `flutter analyze` dá `22 issues found`, sendo 21 `info` e **um `warning`** (`unnecessary_non_null_assertion`, `test/webdav_server_test.dart:69:100`), zero erro. Os 22 são todos pré-existentes. **Não existe mais "a falha de sempre":** o `-1` que as fatias 1, 2 e 3 carregaram foi consertado em `5d21b14`. Qualquer falha, em qualquer Task, é regressão sua.

---

## Duas decisões travadas pelo usuário

Estas duas não são minhas nem suas. Foram decididas em 2026-09-11 e valem para a fatia inteira.

### Primeira: o escopo é segurança **mais** multi-addon

O item 4 da decomposição (`docs/stremio-de-jogos-design.md:600`) lista só "tela de contas, migração de token para secure storage, correção da seção 6.3, e manter o RTS emitindo o formato estendido". A seção 9 do spec de UI descreve muito mais: lista de addons, detalhe por addon, cobertura, Accounts consolidado, e prioridade arrastável. O escopo travado é **o conjunto dos dois**. Se você achar que uma Task está fora do item 4 da decomposição, ela provavelmente está, e ainda assim é sua.

Dois parágrafos da seção 9 **não** entram, e é melhor dizer agora do que descobrir na revisão:

| O que a seção 9 diz | Onde fica |
| --- | --- |
| "**Real-Debrid não é addon, é conta.** Ele aparece em Accounts e nunca na lista de addons" | fatia 6. O que esta fatia deixa pronto é a chave `SecretRef.debrid(provedor)`, com teste, e nada mais. Não existe addon de torrent para o debrid resolver, então uma linha de Real-Debrid em Accounts hoje seria um formulário que não alimenta ninguém. |
| "**Cobertura**: quais consoles ele atende **e quantos itens em cada**" | fica de fora sem data. A contagem custa uma requisição de listagem por console, e o motivo está escrito na abertura do Grupo 5 e na Task 22. |

Todo o resto da seção 9 é desta fatia.

### Segunda: sem chaveiro, o cofre cai para texto puro, avisando

`flutter_secure_storage` no Linux exige `gnome-keyring` ou KWallet vivo no D-Bus. Num Linux de servidor isso não existe, e a leitura levanta. A decisão é **manter o comportamento de hoje nesse caso**, com aviso na tela, em vez de desabilitar o campo ou cifrar em arquivo.

**A consequência dessa decisão tem que estar visível no código e nos testes, senão a fatia vira maquiagem.** A seção 6.3 do spec tem dois objetivos, e só um sobrevive incondicionalmente:

| Objetivo da 6.3 | Vale sempre? | Por quê |
| --- | --- | --- |
| Tirar o segredo do **JSON compartilhável** (`auth.token`) | **Sim, em toda plataforma** | é o arquivo que o usuário manda para outra pessoa, e nada o cifra |
| Cifrar o segredo **em repouso** | Não, é melhor esforço | sem chaveiro, o cofre de reserva grava em texto puro |

Nunca escreva, em commit, relatório ou comentário, que "a 6.3 está corrigida" sem separar essas duas metades. A primeira é a que fecha o vazamento de verdade; a segunda é defesa em profundidade que às vezes não está lá.

---

## Antes de começar: o que já existe, medido

Tudo nesta seção foi conferido rodando `grep` e lendo o arquivo em `ef5ee57`, não deduzido. Os números de linha são pista, não verdade: se um não bater, o arquivo andou, e quem manda é o conteúdo.

### O inventário de segredos de hoje

Todo segredo do app mora numa **única chave** do `shared_preferences`, `app_settings`, como JSON em texto puro (`lib/services/settings_service.dart:8` e `:33`).

| Segredo | Campo | Serializado em | Digitado em |
| --- | --- | --- | --- |
| Token por console | `BaseSettings.authToken` | `settings_model.dart:158` | `console_auth_setting.dart` |
| Chave de acesso S3 do IA | `AppSettings.iaAccessKey` | `settings_model.dart:86` | `ia_credentials_setting.dart` |
| Chave secreta S3 do IA | `AppSettings.iaSecretKey` | `settings_model.dart:87` | `ia_credentials_setting.dart` |
| Cookies do IA | `AppSettings.iaCookies` | `settings_model.dart:88` | `ia_credentials_setting.dart` |

São **quatro**, não dois. O `iaCookies` é fácil de esquecer porque o spec não o cita: ele é o par "logged-in-user / logged-in-sig" que destrava download restrito, e é credencial tanto quanto as outras.

### Os quatro sítios que leem o token de dentro do arquivo

A seção 6.3 do spec diz que "duas mudanças fecham o buraco". São quatro:

| # | Arquivo | O que faz |
| --- | --- | --- |
| 1 | `lib/utils/network.dart:41` | `final token = tokenOverride ?? auth['token'] as String?;` |
| 2 | `lib/services/task_queue_service.dart:20` | a cadeia inteira, literal como o spec cita |
| 3 | `lib/screens/tinfoil_server_screen.dart:91` | decide se o console "tem auth" |
| 4 | `lib/screens/setup_wizard_screen.dart:392` | idem, mesma expressão |

Os dois últimos **não montam header**: eles só decidem se a UI mostra o console como autenticado. Passam despercebidos num `grep` por `buildConsoleAuthHeaders`, que acha só quatro chamadores e nenhum deles. O `grep` que acha os quatro é:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

O `-E` é obrigatório. Sem ele o `grep` é BRE, o `\?` vira quantificador e o segundo `?` vira literal, e aí o padrão passa a exigir uma `?` depois de `auth`: acha os três que escrevem `auth?[` e deixa passar justamente o `network.dart:41`, que escreve `auth['token']` sem `?` e é o sítio que a 6.3 lista. Medido com os quatro ainda no lugar: BRE achou três, `-E` achou quatro.

Se você consertar só os dois primeiros, o app continua dizendo "este console tem auth configurada" com base num campo que ninguém mais lê para autenticar. Não é vazamento, é mentira de interface, e é pior de achar depois.

**E a terceira frase da 6.3 é vazia hoje, medido.** O spec diz "Na instalação, se o JSON vier com `auth.token` preenchido, o app move para o `flutter_secure_storage` e zera no arquivo salvo. **Na exportação, remove**". A metade da instalação é a Task 8. A da exportação não tem onde morar: **o app não exporta catálogo**. O único `FilePicker.platform.saveFile` de `lib/` grava `webdav.json` do servidor JDKV (`jdkv_server_screen.dart:181`), que é outro arquivo e outra tela. Não escreva Task para isso, e não reporte a exportação como feita nem como pendente: reporte que não existe caminho de exportação de catálogo em `ef5ee57`, e que quem criar um depois herda a obrigação.

### A fonte de catálogo de hoje é **uma só**

Isso é o fato que dá o tamanho da fatia.

- `CatalogService.setCatalogFromJson` (`catalog_service.dart:109-118`) **sobrescreve** `config/consoles.json`. Instalar um catálogo apaga o anterior.
- `AppSettings.catalogSourceUrl` (`settings_model.dart:24`) é um `String?`, uma URL, não uma lista.
- `getConsoles` (`catalog_service.dart:20-48`) lê exatamente um arquivo, com precedência config do usuário, depois asset embutido, depois nada.

Não existe hoje **nenhuma** noção de lista ordenada de fontes, prioridade ou arrasto, em lugar nenhum de `lib/`.

### O id do console vem do nome, e por isso colide

`_nameToId` (`catalog_service.dart:61-63`) deriva o id do **nome** do console. Com um addon só isso nunca importou. Com N, dois addons que sirvam "Nintendo 64" produzem o mesmo id `nintendo_64` e um sobrescreve o outro no `Map<String, Console>`.

**A saída não é inventar namespace de id.** O spec já decidiu, em `design.md:420-422`: "Alguém instala a URL do seu RTS como addon e, se tiver o pack daquele console, sua pasta local aparece como fonte na grade dele". "Na grade **dele**" quer dizer: o console continua sendo um só, e os addons são fontes daquele console. É o mesmo "um jogo, várias fontes" da fatia 3, um nível acima.

Isso cai bem porque `Console.urls` **já é** `List<String>` (`console_model.dart:4`), e `Console.url` é só o primeiro (`console_model.dart:51`). Fundir dois consoles de mesmo id é concatenar `urls`, não inventar tipo.

O que **não** pode ser fundido é a credencial, e é por isso que a chave do cofre é `addon:<id>/<console>` e não `console:<id>`: dois addons servindo Nintendo 64, cada um com login próprio, continuam com tokens separados. A seção 6.2 do spec já escreve a chave nesse formato.

### O soquete que a fatia 3 deixou pronto

Não reimplemente isto, **ligue**:

- `planFromEntries` (`lib/services/source_pick_service.dart:50-55`) já recebe `List<String> sourcePriority = const []`, e `_priorityRank` (`:156-159`) já usa. **Ninguém passa nada hoje**, então o eixo existe e está sempre vazio.
- `MatchedSource.sourceId` e `SourcePick.sourceId` já são campos, não enums (`source_pick_model.dart:35-38`).
- Hoje o valor é sempre `kBuiltinSourceId`, a constante `'listagem'` (`source_pick_model.dart:17`), preenchido num lugar só: `pack_grid_provider.dart:75`.

A prioridade arrastável da seção 9 é exatamente o que preenche `sourcePriority`. O comentário em `source_pick_model.dart:35` já diz "nesta fatia é sempre `kBuiltinSourceId` e na fatia 4...". Essa fatia é esta.

### O RTS é o produtor do mesmo formato

`RtsServerService.consoleJson` (`lib/services/rts_server_service.dart:13-20`) monta o objeto de console que o `Console.fromJson` do mesmo binário consome. Produtor e consumidor são o mesmo app, então divergir é um bug com nome (`design.md:416-419`). Ele **não** emite `auth`, e está certo: servidor local não pede credencial. A Task de contrato existe para que isso continue verdade, não para mudar.

### Comandos deste repositório

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test 2>&1 | tr '\r' '\n' | tail -5
flutter analyze
```

O `tr '\r' '\n'` não é enfeite: a saída do `flutter test` usa retorno de carro e some no pipe sem ele.

**Nunca rode `dart format`.** O repositório não é limpo sob o formatador tall-style atual: 106 de 217 arquivos mudariam. Rodar cria ruído de diff que enterra a sua mudança.

**Não existe um único `export` em `lib/`.** Confira: `grep -rln "^export " lib/` volta vazio. Import transitivo nunca resolve, então todo arquivo novo importa explicitamente tudo que usa. Esse é o defeito mais repetido das três fatias anteriores.

### Regras de commit

- `git add` sempre por caminho explícito. **Nunca `git add -A`, nunca `git add .`, nunca `git commit -a`**: o `pubspec.lock` fica permanentemente sujo porque o Flutter 3.35.7 local resolve versões transitivas mais velhas.
- Cada Task traz **duas** mensagens, `test(<escopo>):` e `feat(<escopo>):`, com o mesmo texto descritivo. Nunca uma só.
- Um commit toca **ou** só `lib/` **ou** só `test/`. Nunca os dois.
- Sem emoji, sem travessão, sem co-autoria.

---

## Estrutura de arquivos

Arquivos **novos**:

| Arquivo | Responsabilidade | Dart puro? |
| --- | --- | --- |
| `lib/models/secret_ref.dart` | as chaves do cofre, num lugar só | sim |
| `lib/services/secret_vault.dart` | a interface do cofre, mais a implementação em memória | sim |
| `lib/services/prefs_vault.dart` | o cofre de reserva, em `shared_preferences` | não, usa plugin |
| `lib/services/secure_storage_vault.dart` | o cofre de sistema, mais a sonda de disponibilidade | não, usa plugin |
| `lib/services/secret_migration.dart` | a mudança única do `app_settings` para o cofre | sim |
| `lib/providers/vault_provider.dart` | qual cofre o app usa, e o aviso quando é o de reserva | não |
| `lib/models/addon_model.dart` | `Addon` e a lista ordenada | sim |
| `lib/services/addon_store.dart` | persistir, instalar, remover e reordenar addons | não |
| `lib/services/console_merge.dart` | fundir N catálogos num `Map<String, Console>` | sim |
| `lib/providers/addon_provider.dart` | os addons, a prioridade derivada, o fundido, as contas e o fetcher | não |
| `lib/services/addon_install.dart` | baixar uma url, colher os tokens e instalar o addon | não, usa `dart:io` |
| `lib/utils/console_auth.dart` | as perguntas de auth que as telas fazem, fora delas | sim |
| `lib/screens/addons_screen.dart` | a lista de addons, com arrasto | não |
| `lib/screens/addon_detail_screen.dart` | um addon: conta, cobertura, prioridade, remover | não |
| `lib/widgets/settings/vault_warning.dart` | o aviso de que este aparelho não cifra | não |

Quinze arquivos novos em `lib/`.

Arquivos **modificados** em `lib/`, vinte e quatro:

| Arquivo | O que muda |
| --- | --- |
| `lib/utils/network.dart` | `buildConsoleAuthHeaders` perde o termo do arquivo |
| `lib/services/task_queue_service.dart` | a cadeia perde o termo do meio |
| `lib/screens/tinfoil_server_screen.dart` | o predicado de "tem auth" para de ler o arquivo |
| `lib/screens/setup_wizard_screen.dart` | idem |
| `lib/services/catalog_service.dart` | instala limpando `auth.token`, lê N addons, e `_parseConsoles` vira público |
| `lib/services/settings_service.dart` | a chave vira pública, e o token do console vira token do par |
| `lib/models/settings_model.dart` | os quatro segredos saem do `toJson` |
| `lib/models/console_model.dart` | `hasTokenAuth` passa a enxergar `requires_token`, e ganha `withUrls` |
| `lib/models/game_model.dart` | o jogo passa a saber de qual addon veio |
| `lib/models/source_pick_model.dart` | perde o `kBuiltinSourceId`, que era a fonte única |
| `lib/services/source_pick_service.dart` | a prioridade passa a vir da ordem dos addons |
| `lib/providers/settings_provider.dart` | escrita e leitura de segredo passam pelo cofre |
| `lib/providers/pack_grid_provider.dart` | a fonte deixa de ser sempre `kBuiltinSourceId` |
| `lib/providers/catalog_provider.dart` | busca por fonte, cada uma com a auth dela |
| `lib/providers/download_provider.dart` | o header sai da auth do par (addon, console) |
| `lib/providers/tinfoil_server_provider.dart` | perde o parâmetro de token que virou consulta ao cofre |
| `lib/providers/fbi_server_provider.dart` | idem |
| `lib/screens/home_screen.dart` | passa a prioridade do usuário para a escolha de fonte |
| `lib/screens/game_detail_screen.dart` | idem, e mostra o nome do addon em vez do id |
| `lib/screens/menu_screen.dart` | as tiles de Tools viram função de topo e ganham "Addons" |
| `lib/widgets/settings/accounts_setting.dart` | vira a visão consolidada, com uma linha por par (addon, console) e o aviso do cofre |
| `lib/widgets/settings/catalog_source_setting.dart` | vira a porta para a tela de addons |
| `lib/widgets/settings/console_auth_setting.dart` | o formulário passa a ser do par (addon, console), e avisa quando grava |
| `lib/widgets/settings/settings_content.dart` | passa o addon ao formulário |

Fora de `lib/`: `pubspec.yaml` ganha `flutter_secure_storage`, e `pubspec.lock` muda junto.

Em `test/`, trinta e dois arquivos, dos quais **cinco são antigos e só são modificados**: `test/game_detail_screen_test.dart`, `test/menu_grid_test.dart`, `test/pack_grid_provider_test.dart`, `test/pack_grid_test.dart` e `test/source_pick_service_test.dart`. Dois dos novos não terminam em `_test.dart` de propósito, porque são ajuda compartilhada sem `main`: `test/vault_contract.dart` e `test/support/fake_addon_store.dart`.

O `lib/services/rts_server_service.dart` **não muda**. Ele ganha teste de contrato, não alteração.

---

## Grupo 1: o cofre

Cinco Tasks. A ordem existe para que o plugin novo chegue o mais tarde possível: as Tasks 1, 2 e 5 são Dart puro e testáveis sem plataforma nenhuma, a Task 3 usa só o `shared_preferences` que já está no projeto, e só a Task 4 encosta em `flutter_secure_storage`.

O cofre entra por uma interface de quatro métodos, com três implementações: memória (testes), `shared_preferences` (a reserva em texto puro da decisão travada) e chaveiro do sistema. As três passam pelo **mesmo arquivo de contrato**, `test/vault_contract.dart`, porque o ponto da decisão travada é que a reserva se comporta igual ao cofre de verdade em tudo, menos em estar cifrada.

### Task 1: `SecretRef`, as chaves do cofre

**Files:**
- Create: `lib/models/secret_ref.dart`
- Test: `test/secret_ref_test.dart`

Parece pequeno demais para uma Task própria, e é de propósito. A chave é a única coisa da fatia que **não pode mudar depois**: ela vai parar no chaveiro do sistema operacional do usuário, fora do controle do app. Um erro de formato aqui vira credencial órfã na máquina de quem atualizar, e não tem migração que conserte sem adivinhar.

O formato vem da seção 6.2 do spec de arquitetura, que já o escreve: `addon:<id>/ultranx`, `ia/cookies`, `debrid/realdebrid`.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/secret_ref_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';

void main() {
  test('a chave de token carrega o addon e o console, nessa ordem', () {
    expect(SecretRef.addonToken('ultranx', 'nintendo_64'), 'addon:ultranx/nintendo_64');
  });

  test('dois addons servindo o mesmo console não dividem a chave', () {
    // Este é o caso que justifica a chave inteira. O id do console vem do
    // NOME dele (`catalog_service.dart:_nameToId`), então dois addons que
    // sirvam "Nintendo 64" produzem `nintendo_64` os dois. Se a chave fosse
    // só do console, o login do segundo apagaria o do primeiro em silêncio.
    expect(
      SecretRef.addonToken('ultranx', 'nintendo_64'),
      isNot(SecretRef.addonToken('meu_rts', 'nintendo_64')),
    );
  });

  test('as chaves do Internet Archive são as três da seção 6.2', () {
    expect(SecretRef.iaAccessKey, 'ia/accessKey');
    expect(SecretRef.iaSecretKey, 'ia/secretKey');
    expect(SecretRef.iaCookies, 'ia/cookies');
  });

  test('debrid é chaveado por provedor, porque vai ter mais de um', () {
    expect(SecretRef.debrid('realdebrid'), 'debrid/realdebrid');
  });

  test('o prefixo de um addon casa com as chaves dele e com mais nenhuma', () {
    final prefixo = SecretRef.addonPrefix('ultranx');

    expect(SecretRef.addonToken('ultranx', 'nintendo_64').startsWith(prefixo), isTrue);
    expect(SecretRef.addonToken('ultranx', 'snes').startsWith(prefixo), isTrue);
    expect(SecretRef.addonToken('ultranx_2', 'snes').startsWith(prefixo), isFalse);
    expect(SecretRef.iaAccessKey.startsWith(prefixo), isFalse);
  });

  test('um id com barra ou dois-pontos não consegue forjar a chave de outro', () {
    // Sem sanear, o addon de id `a/b` mais o console `c` daria
    // `addon:a/b/c`, que é a mesma coisa que o addon `a` mais o console
    // `b/c`. Os ids de hoje são slugs e isso não acontece, mas a chave é
    // permanente e o gerador de id não é: o saneamento mora aqui, no lado
    // que não pode mudar depois.
    expect(
      SecretRef.addonToken('a/b', 'c'),
      isNot(SecretRef.addonToken('a', 'b/c')),
    );
  });

  test('sanear não colapsa ids que só diferem em pontuação', () {
    expect(SecretRef.addonToken('meu-rts', 'snes'), isNot(SecretRef.addonToken('meu_rts', 'snes')));
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_ref_test.dart
```

Esperado: `Error: Couldn't resolve the package 'roms_downloader' ... secret_ref.dart` ou `Undefined name 'SecretRef'`. Se passar, você criou o arquivo antes do teste.

- [ ] **Step 3: Implemente**

Crie `lib/models/secret_ref.dart`:

```dart
/// As chaves do cofre, num lugar só.
///
/// São `String` e não enum porque duas delas dependem de dado de execução: o
/// id do addon e o do console. O formato é o da seção 6.2 do spec de
/// arquitetura.
///
/// **Este arquivo é o mais difícil de mudar da fatia.** A chave vai parar no
/// chaveiro do sistema operacional do usuário, fora do alcance do app. Mudar
/// o formato depois deixa credencial órfã na máquina de quem atualizar, sem
/// como achar de volta. Por isso o saneamento mora aqui e não em quem gera id.
class SecretRef {
  /// O token de um console servido por um addon.
  ///
  /// Carrega o **addon**, e não só o console, porque o id do console vem do
  /// nome dele: dois addons que sirvam "Nintendo 64" produzem `nintendo_64`
  /// os dois, e têm logins diferentes.
  static String addonToken(String addonId, String consoleId) =>
      '${addonPrefix(addonId)}${_sane(consoleId)}';

  /// Tudo que pertence a um addon. Usado para apagar as credenciais dele
  /// quando o usuário o remove.
  ///
  /// Termina em `/` de propósito: sem isso, o prefixo de `ultranx` casaria
  /// com as chaves de `ultranx_2`.
  static String addonPrefix(String addonId) => 'addon:${_sane(addonId)}/';

  static const iaAccessKey = 'ia/accessKey';
  static const iaSecretKey = 'ia/secretKey';
  static const iaCookies = 'ia/cookies';

  /// Por provedor, porque Real-Debrid não vai ser o único.
  static String debrid(String provider) => 'debrid/${_sane(provider)}';

  /// Troca o que estrutura a chave por `_`, para que nenhum id consiga forjar
  /// a chave de outro. Só `:` e `/` são estruturais, então trocar os dois basta.
  ///
  /// A troca **não** é injetiva: `a:b`, `a/b` e `a_b` saem todos como `a_b`.
  /// Não se perde nada com isso, porque `_nameToId`
  /// (`catalog_service.dart:61`) já colapsa todo não alfanumérico em `_`, e
  /// então os ids reais nunca distinguem esses três. Trocar mais, tipo
  /// `[^a-z0-9]`, aí sim perderia: `meu-rts` e `meu_rts` são dois addons e
  /// virariam a mesma chave.
  ///
  /// Parte vazia sai sem guarda, de propósito. `_nameToId` devolve `''` para
  /// um nome só de pontuação, e aí `addonToken('x', '')` é igual a
  /// `addonPrefix('x')`. É inofensivo: o prefixo só serve para apagar em lote
  /// e nunca é chave de nada, e dois consoles de id vazio já são **um**
  /// console, porque `_parseConsoles` (`catalog_service.dart:91`) grava os
  /// dois na mesma entrada do mapa. Levantar aqui derrubaria a migração da
  /// Task 5, que itera chaves já gravadas, para defender contra uma colisão
  /// que o catálogo colapsou antes.
  static String _sane(String part) => part.replaceAll(RegExp(r'[:/]'), '_');
}
```

- [ ] **Step 4: Rode para ver passar**

```bash
flutter test test/secret_ref_test.dart
```

Esperado: `+7`, zero falha.

**Tropeço provável:** o último teste, "sanear não colapsa ids que só diferem em pontuação", falha se você trocar a expressão por algo mais largo, tipo `[^a-z0-9]`. Aí `meu-rts` e `meu_rts` viram a mesma chave e dois addons diferentes dividem credencial, que é exatamente o que a chave existe para impedir. Saneie **só** o que estrutura a chave.

- [ ] **Step 5: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, os mesmos de sempre, nenhum nos arquivos novos.

- [ ] **Step 6: Commit**

```bash
git add test/secret_ref_test.dart
git commit -m "test(cofre): chaves do cofre por addon, console e provedor"
git add lib/models/secret_ref.dart
git commit -m "feat(cofre): chaves do cofre por addon, console e provedor"
```

---

### Task 2: `SecretVault`, a interface, e o contrato que toda implementação cumpre

**Files:**
- Create: `lib/services/secret_vault.dart`
- Create: `test/vault_contract.dart`
- Test: `test/secret_vault_test.dart`

Esta Task entrega duas coisas que valem mais juntas do que separadas: a interface com a implementação em memória, e o **arquivo de contrato** que as outras duas implementações vão reusar sem copiar teste.

O contrato tem uma decisão dentro dele que merece ser lida antes de escrever o código: **escrever string vazia apaga a chave**. A alternativa seria guardar `''`, e aí `read` devolveria `''` em vez de `null`, e todo chamador precisaria lembrar de tratar os dois como "não tem". Hoje o app já faz isso certo num lugar (`settings_provider.dart:125`, `token.isEmpty ? clearAuthToken : ...`) e o cofre não pode desfazer essa decisão. Um cofre que devolve `''` num lugar e `null` no outro vira `if (t != null && t.isNotEmpty)` espalhado por quatro telas.

- [ ] **Step 1: Escreva o contrato**

Crie `test/vault_contract.dart`. Repare no nome: **não** termina em `_test.dart`, de propósito, porque ele não roda sozinho, ele é chamado por três arquivos de teste diferentes.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// O contrato que TODA implementação de [SecretVault] cumpre.
///
/// Existe como função e não como arquivo de teste porque três implementações
/// precisam passar exatamente por ele: memória (Task 2), `shared_preferences`
/// (Task 3) e chaveiro do sistema (Task 4). Copiar os casos daria três cópias
/// que divergem na primeira correção.
///
/// [build] devolve um cofre **vazio** a cada chamada. É `Future` porque a
/// implementação de `shared_preferences` precisa de `await` para nascer.
void runVaultContract(String nome, Future<SecretVault> Function() build) {
  group('contrato de cofre: $nome', () {
    test('lê de volta o que escreveu', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');

      expect(await vault.read('ia/accessKey'), 'ABCDEF');
    });

    test('chave que nunca foi escrita devolve null', () async {
      final vault = await build();

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('escrever por cima substitui', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'velho');
      await vault.write('ia/accessKey', 'novo');

      expect(await vault.read('ia/accessKey'), 'novo');
    });

    test('apagar apaga', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.delete('ia/accessKey');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('escrever vazio apaga, em vez de guardar vazio', () async {
      // Sem isto, `read` devolve `''` num cofre e `null` no outro, e todo
      // chamador vira `if (t != null && t.isNotEmpty)`. A ausência tem uma
      // representação só, e é `null`.
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.write('ia/accessKey', '');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('apagar por prefixo leva só quem casa', () async {
      final vault = await build();
      await vault.write('addon:ultranx/snes', 'a');
      await vault.write('addon:ultranx/n64', 'b');
      await vault.write('addon:ultranx_2/snes', 'c');
      await vault.write('ia/accessKey', 'd');

      await vault.deleteWithPrefix('addon:ultranx/');

      expect(await vault.read('addon:ultranx/snes'), isNull);
      expect(await vault.read('addon:ultranx/n64'), isNull);
      expect(await vault.read('addon:ultranx_2/snes'), 'c');
      expect(await vault.read('ia/accessKey'), 'd');
    });

    test('apagar o que não existe não explode', () async {
      // Chamado na remoção de addon, que roda mesmo para addon que nunca
      // pediu login. Se lançar, remover addon vira erro de tela.
      final vault = await build();

      await vault.delete('addon:nunca/existiu');
      await vault.deleteWithPrefix('addon:nunca/');

      expect(await vault.read('addon:nunca/existiu'), isNull);
    });
  });
}
```

- [ ] **Step 2: Escreva o teste do cofre em memória**

Crie `test/secret_vault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'vault_contract.dart';

void main() {
  runVaultContract('MemoryVault', () async => MemoryVault());

  test('dois cofres em memória não dividem estado', () {
    // Este é o motivo de o `MemoryVault` existir: cada teste que usa cofre
    // precisa do seu. Um `static` compartilhado aqui faria um teste enxergar
    // o segredo escrito por outro, e a suíte passaria a depender de ordem.
    final a = MemoryVault();
    final b = MemoryVault();

    return expectLater(
      a.write('ia/accessKey', 'ABCDEF').then((_) => b.read('ia/accessKey')),
      completion(isNull),
    );
  });
}
```

- [ ] **Step 3: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_vault_test.dart
```

Esperado: erro de compilação, `Couldn't resolve the package` ou `Undefined name 'MemoryVault'`.

- [ ] **Step 4: Implemente**

Crie `lib/services/secret_vault.dart`:

```dart
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
```

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/secret_vault_test.dart
```

Esperado: `+8`, zero falha. São os sete do contrato mais o caso de isolamento.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+355`, zero falha. São 340 da linha de base, mais 7 da Task 1, mais 8 desta.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, nenhum nos arquivos novos.

**Tropeço provável:** `flutter analyze` reclamando de `test/vault_contract.dart` por não ter `main()`. Não reclama, porque ele é uma biblioteca Dart comum; o que **não** pode acontecer é o arquivo se chamar `vault_contract_test.dart`, aí o `flutter test` tentaria rodá-lo sozinho e falharia com `Could not find a file named "main"`.

- [ ] **Step 8: Commit**

```bash
git add test/vault_contract.dart test/secret_vault_test.dart
git commit -m "test(cofre): contrato de cofre reusavel e o cofre em memoria"
git add lib/services/secret_vault.dart
git commit -m "feat(cofre): contrato de cofre reusavel e o cofre em memoria"
```

---

### Task 3: `PrefsVault`, a reserva em texto puro

**Files:**
- Create: `lib/services/prefs_vault.dart`
- Test: `test/prefs_vault_test.dart`

Esta é a metade desconfortável da decisão travada: num Linux sem chaveiro, o segredo continua em texto puro. O que esta Task **ganha** mesmo assim, e não é pouco, é que o segredo sai de dentro do `app_settings`, que é o JSON que o app serializa inteiro e **cujo erro de leitura imprime o próprio JSON de volta**. Medido, não deduzido: a `FormatException` do `jsonDecode` embute o trecho da fonte na mensagem, e o `debugPrint('Error loading settings: $e')` do caminho de erro (`settings_service.dart:21`) manda isso para o log com o segredo dentro. Um `app_settings` corrompido por qualquer motivo vaza `iaSecretKey` no log. Chave separada é chave que não vaza de carona.

O prefixo `secret:` existe para que a Task 5 possa afirmar que a migração não deixou nada para trás, e para que um `getKeys()` futuro consiga listar só segredo.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/prefs_vault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/prefs_vault.dart';

import 'vault_contract.dart';

Future<SharedPreferences> _prefsVazio() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runVaultContract('PrefsVault', () async => PrefsVault(await _prefsVazio()));

  test('o segredo não encosta na chave que guarda as settings', () async {
    // O ganho real desta implementação não é cifrar, porque ela não cifra. É
    // tirar o segredo de dentro do `app_settings`, cujo erro de leitura
    // imprime o próprio JSON de volta: a `FormatException` do `jsonDecode`
    // embute o trecho da fonte, e o `debugPrint` do caminho de erro
    // (`settings_service.dart:21`) manda isso para o log com o segredo dentro.
    SharedPreferences.setMockInitialValues({'app_settings': '{"nszDecompressEnabled":true}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);

    await vault.write('ia/accessKey', 'ABCDEF');

    expect(prefs.getString('app_settings'), '{"nszDecompressEnabled":true}');
    expect(prefs.getString('secret:ia/accessKey'), 'ABCDEF');
  });

  test('o segredo sobrevive a uma instância nova sobre o mesmo prefs', () async {
    // `MemoryVault` passaria o contrato inteiro e perderia tudo no
    // fechamento do app. O contrato não distingue os dois, este caso sim.
    final prefs = await _prefsVazio();
    await PrefsVault(prefs).write('ia/accessKey', 'ABCDEF');

    expect(await PrefsVault(prefs).read('ia/accessKey'), 'ABCDEF');
  });

  test('apagar um addon inteiro não encosta em quem não é segredo', () async {
    // A única propriedade que **só** esta implementação tem. O contrato
    // compartilhado exercita a fronteira entre dois addons, mas roda igual
    // para `MemoryVault`, que não divide store com ninguém. Este cofre divide:
    // ele varre o mesmo `shared_preferences` onde mora o `app_settings`.
    SharedPreferences.setMockInitialValues({'app_settings': '{"downloadDir":"/casa/roms"}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'AAA');
    await vault.write(SecretRef.addonToken('ultranx_2', 'snes'), 'BBB');

    await vault.deleteWithPrefix(SecretRef.addonPrefix('ultranx'));

    expect(prefs.getString('app_settings'), '{"downloadDir":"/casa/roms"}');
    expect(await vault.read(SecretRef.addonToken('ultranx_2', 'snes')), 'BBB');
    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
  });

  test('`open()` abre sobre o prefs de verdade, que é o caminho da produção', () async {
    // Os outros casos constroem pelo construtor, e `vault_provider.dart:39`
    // liga `PrefsVault.open` como reserva. Sem este caso, o único caminho que
    // a produção percorre é o único sem teste.
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final vault = await PrefsVault.open();
    await vault.write(SecretRef.iaAccessKey, 'ABCDEF');

    expect(await vault.read(SecretRef.iaAccessKey), 'ABCDEF');
  });
}
```

Os dois últimos casos são a razão de este arquivo existir além do contrato compartilhado, e valem o parágrafo:

O de apagar prova a única propriedade que **só** esta implementação tem. O contrato já exercita a fronteira entre `addon:ultranx/` e `addon:ultranx_2/`, mas ele roda igual para o `MemoryVault`, que tem store próprio. Este cofre não tem: ele varre o mesmo `shared_preferences` onde mora o `app_settings`. O caso monta as chaves com `SecretRef`, e não com string na mão, de propósito, porque é a barra final de `addonPrefix` que separa `ultranx` de `ultranx_2`, e um chamador que montasse `'addon:ultranx'` sem ela derrubaria o login do addon vizinho.

O de `open()` cobre o único caminho que a produção percorre: `vault_provider.dart` liga `PrefsVault.open` como reserva, e todos os outros casos constroem pelo construtor. Custa quatro linhas porque `setMockInitialValues({})` já basta, sem override de provider e sem falso.

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/prefs_vault_test.dart
```

Esperado: `Undefined name 'PrefsVault'`.

- [ ] **Step 3: Implemente**

Crie `lib/services/prefs_vault.dart`:

```dart
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
```

- [ ] **Step 4: Rode para ver passar**

```bash
flutter test test/prefs_vault_test.dart
```

Esperado: `+11`, zero falha. São os sete do contrato mais os quatro deste arquivo.

**Tropeço provável:** o contrato falhar em "chave que nunca foi escrita devolve null" a partir do segundo caso, porque `SharedPreferences.getInstance()` guarda um singleton interno e cada `build()` do contrato pede uma instância nova.

Quem zera o singleton, medido no `shared_preferences-2.5.3`, é o **`setMockInitialValues`**: ele mesmo faz `_completer = null` (`lib/src/shared_preferences_legacy.dart:290`, comentário "If the singleton instance has been initialized already, it is nullified"). O `resetStatic()` logo depois é redundante nesta versão: tirá-lo de `_prefsVazio` deixa os casos do contrato passando igual, conferido. Mantenha os dois assim mesmo, porque é defesa barata contra `setPrefix` e contra troca de versão do plugin, mas **não escreva em lugar nenhum que é o `resetStatic()` que limpa o singleton**: se a Task 4 acreditar nisso ao decidir entre os dois cofres, vai defender a fronteira errada.

- [ ] **Step 5: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+366`, zero falha.

- [ ] **Step 6: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/prefs_vault_test.dart
git commit -m "test(cofre): cofre de reserva em shared_preferences, com chave separada"
git add lib/services/prefs_vault.dart
git commit -m "feat(cofre): cofre de reserva em shared_preferences, com chave separada"
```

---

### Task 4: `SecureStorageVault`, a sonda, e a escolha do cofre

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/secure_storage_vault.dart`
- Create: `lib/providers/vault_provider.dart`
- Test: `test/secure_storage_vault_test.dart`
- Test: `test/vault_provider_test.dart`

Esta é a única Task da fatia que traz dependência nova, e a única que precisa decidir o que fazer quando a plataforma não colabora.

Três coisas que valem saber antes:

1. **`flutter_secure_storage` não é testável direto.** Ele fala com o plugin por canal de plataforma, que num `flutter test` não existe. Por isso entra uma interface fina, `SecureStorageBackend`, com os quatro métodos que este app usa. O `SecureStorageVault` conversa com a interface, os testes injetam um falso, e a implementação real é três linhas de delegação que nenhum teste cobre e nem precisa.
2. **A sonda escreve, lê de volta e apaga.** "A escrita não lançou" **não** é prova de que o chaveiro funciona: existe backend que aceita a escrita e não guarda. Só a leitura de volta prova.
3. **A versão é a 10.x, e isso não é conservadorismo, é a única que resolve.** A 11.x não entra neste `pubspec`, e a tentativa custou uma Task travada: `flutter_secure_storage >=11.0.0-beta.1` puxa `flutter_secure_storage_windows ^4.2.2`, que exige `win32 ^6.0.1`, enquanto o `package_info_plus: ^9.0.0` já pinado aqui (`pubspec.yaml:29`) exige `win32 ^5.5.3`. As duas restrições se excluem e o solver recusa. Saída literal:

   ```
   Because package_info_plus >=8.0.3 <10.0.0 depends on win32 ^5.5.3 and flutter_secure_storage_windows >=4.2.0 depends on win32 ^6.0.1, package_info_plus >=8.0.3 <10.0.0 is incompatible with flutter_secure_storage_windows >=4.2.0.
   So, because roms_downloader depends on both package_info_plus ^9.0.0 and flutter_secure_storage ^11.1.0, version solving failed.
   ```

   A saída seria subir o `package_info_plus` para `^10`, e **não é para fazer isso**: ele é usado em dois arquivos de produção (`about_screen.dart` e `zerox0_service.dart`), o `win32` saltaria de 5 para 6 numa dependência que esta fatia não tem motivo nenhum para tocar, e o risco cairia na tela Sobre e no user agent. Fatia de segurança não arrasta dependência alheia junto. Se alguém "atualizar" isto para a 11.x depois, o `pub get` quebra de novo, e o motivo está escrito aqui.

   Medido na 10.3.3, e o código desta Task não muda uma vírgula por causa disso: `read(key:)`, `write(key:, value:)`, `delete(key:)`, `readAll()` e o construtor `const FlutterSecureStorage()` existem iguais (`flutter_secure_storage-10.3.3/lib/flutter_secure_storage.dart:35`, `:134`, `:185`, `:249`, `:293`).
4. **O plugin exige minSdk 23 no Android** (`flutter_secure_storage-10.3.3/android/build.gradle:46`). Este projeto usa `minSdk = flutter.minSdkVersion` (`android/app/build.gradle.kts:43`), que no Flutter 3.35 é 24. Sobra folga, e nada precisa mudar. No Linux, ele exige `libsecret-1-dev` em tempo de compilação, que já está instalado nesta VM (`pkg-config --modversion libsecret-1` dá `0.21.4`).

- [ ] **Step 1: Some a dependência**

Em `pubspec.yaml`, na última linha da lista `dependencies:`, depois de `ftp_server: ^2.3.2`:

```yaml
  flutter_secure_storage: ^10.3.3
```

Depois:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter pub get
```

Esperado: `Changed 6 dependencies!`, medido. Se vier `version solving failed` falando de `win32`, você escreveu `^11` em vez de `^10.3.3`: leia o item 3 acima. O `pubspec.lock` vai mudar. **Não o adicione ao commit**: ele já vive sujo neste repositório porque o Flutter local resolve versões transitivas mais velhas, e commitá-lo mistura ruído com a mudança.

- [ ] **Step 2: Escreva o teste do cofre de sistema**

Crie `test/secure_storage_vault_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

import 'vault_contract.dart';

/// O plugin de verdade não existe dentro de `flutter test`: ele fala por canal
/// de plataforma. Este falso é o que torna o cofre de sistema testável.
class _BackendFalso implements SecureStorageBackend {
  _BackendFalso({this.lancaAoEscrever = false, this.engoleEscrita = false});

  /// Um Linux sem Secret Service: a escrita levanta `PlatformException`.
  final bool lancaAoEscrever;

  /// Pior que levantar: aceita a escrita e não guarda. É por isso que a sonda
  /// lê de volta em vez de só olhar se a escrita lançou.
  final bool engoleEscrita;

  final Map<String, String> valores = {};

  @override
  Future<String?> read(String key) async => valores[key];

  @override
  Future<void> write(String key, String value) async {
    if (lancaAoEscrever) throw PlatformException(code: 'Libsecret error');
    if (engoleEscrita) return;
    valores[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    valores.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(valores);
}

void main() {
  runVaultContract('SecureStorageVault', () async => SecureStorageVault(_BackendFalso()));

  group('sonda de disponibilidade', () {
    test('aprova o chaveiro que devolve o que escreveu', () async {
      expect(await probeSecureStorage(_BackendFalso()), isTrue);
    });

    test('reprova o chaveiro que levanta', () async {
      // Este é o Linux de servidor da decisão travada: sem `gnome-keyring` nem
      // KWallet no D-Bus, o plugin levanta `PlatformException`. Se a sonda
      // deixasse a exceção subir, o app quebraria no boot em vez de cair para
      // a reserva.
      expect(await probeSecureStorage(_BackendFalso(lancaAoEscrever: true)), isFalse);
    });

    test('reprova o chaveiro que engole a escrita em silêncio', () async {
      // O caso que justifica ler de volta. Se a sonda parasse em "escreveu sem
      // lançar", este backend passaria, o app anunciaria "cifrado em repouso"
      // e o token do usuário sumiria a cada reinício, sem erro nenhum.
      expect(await probeSecureStorage(_BackendFalso(engoleEscrita: true)), isFalse);
    });

    test('não deixa o canário para trás', () async {
      // A sonda roda no boot. Uma chave por boot acumulando no chaveiro do
      // sistema do usuário é lixo que o app não tem como limpar depois.
      final backend = _BackendFalso();

      await probeSecureStorage(backend);

      expect(backend.valores, isEmpty);
    });
  });
}
```

- [ ] **Step 3: Escreva o teste da escolha**

Crie `test/vault_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

class _BackendBom implements SecureStorageBackend {
  final Map<String, String> valores = {};

  @override
  Future<String?> read(String key) async => valores[key];

  @override
  Future<void> write(String key, String value) async {
    valores[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    valores.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(valores);
}

class _BackendMorto implements SecureStorageBackend {
  @override
  Future<String?> read(String key) async => throw StateError('sem chaveiro');

  @override
  Future<void> write(String key, String value) async => throw StateError('sem chaveiro');

  @override
  Future<void> delete(String key) async => throw StateError('sem chaveiro');

  @override
  Future<Map<String, String>> readAll() async => throw StateError('sem chaveiro');
}

void main() {
  test('com chaveiro vivo, usa o de sistema e diz que está cifrado', () async {
    final escolha = await chooseVault(backend: _BackendBom(), buildFallback: () async => MemoryVault());

    expect(escolha.vault, isA<SecureStorageVault>());
    expect(escolha.encryptedAtRest, isTrue);
  });

  test('sem chaveiro, cai para a reserva e diz que NÃO está cifrado', () async {
    // As duas afirmações são a decisão travada inteira. Cair para a reserva
    // sem carregar o `false` junto é o que transforma a fatia em maquiagem: a
    // tela anunciaria "guardado com segurança" sobre texto puro.
    final escolha = await chooseVault(backend: _BackendMorto(), buildFallback: () async => MemoryVault());

    expect(escolha.vault, isA<MemoryVault>());
    expect(escolha.encryptedAtRest, isFalse);
  });

  test('com chaveiro vivo, a reserva nem chega a ser construída', () async {
    // `PrefsVault.open()` abre o `shared_preferences`. Construir a reserva
    // sempre, para descartá-la em seguida, é trabalho de boot desperdiçado em
    // todo aparelho que tem chaveiro, que é a maioria.
    var construcoes = 0;

    await chooseVault(
      backend: _BackendBom(),
      buildFallback: () async {
        construcoes++;
        return MemoryVault();
      },
    );

    expect(construcoes, 0);
  });
}
```

- [ ] **Step 4: Rode para ver falhar**

```bash
flutter test test/secure_storage_vault_test.dart test/vault_provider_test.dart
```

Esperado: erro de compilação, `Undefined name 'SecureStorageVault'`.

- [ ] **Step 5: Implemente o cofre de sistema**

Crie `lib/services/secure_storage_vault.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// O pedaço de `flutter_secure_storage` que este app usa.
///
/// Existe porque o plugin fala por canal de plataforma, que não existe dentro
/// de `flutter test`. Sem esta interface, o cofre de sistema seria a única
/// implementação de [SecretVault] sem teste nenhum, justo a que guarda os
/// segredos de verdade.
abstract class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// A implementação de verdade. Três linhas de delegação por método e nenhuma
/// decisão: tudo que é decisão mora no [SecureStorageVault], que é testado.
class PluginSecureStorage implements SecureStorageBackend {
  final FlutterSecureStorage _storage;

  const PluginSecureStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// O cofre cifrado pelo sistema operacional: Keychain no Apple, Keystore no
/// Android, DPAPI no Windows, libsecret no Linux.
class SecureStorageVault implements SecretVault {
  final SecureStorageBackend _backend;

  const SecureStorageVault(this._backend);

  @override
  Future<String?> read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _backend.write(key, value);
  }

  @override
  Future<void> delete(String key) => _backend.delete(key);

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final todas = await _backend.readAll();
    // `toList()` antes de apagar: `keys` é a visão viva do mapa devolvido, e
    // uma implementação que devolva o mapa interno em vez de cópia lançaria
    // `ConcurrentModificationError` no meio da remoção de um addon.
    for (final chave in todas.keys.where((chave) => chave.startsWith(prefix)).toList()) {
      await _backend.delete(chave);
    }
  }
}

/// Escreve, lê de volta e apaga uma chave-canário.
///
/// **Ler de volta é o ponto.** No Linux sem Secret Service o plugin levanta, e
/// isso o `try` pega; mas existe também backend que aceita a escrita e não
/// guarda nada, e esse só aparece na leitura. Um app que anuncia "cifrado em
/// repouso" por cima de um desses perde o token do usuário a cada reinício sem
/// emitir um erro sequer.
Future<bool> probeSecureStorage(SecureStorageBackend backend) async {
  const chave = 'probe/canary';
  const valor = 'ok';
  try {
    await backend.write(chave, valor);
    final volta = await backend.read(chave);
    await backend.delete(chave);
    return volta == valor;
  } catch (_) {
    // Engolir é o comportamento certo aqui, e só aqui: a sonda existe
    // justamente para transformar "levantou" em `false`. Quem chama decide o
    // que fazer, e o que ele faz é cair para a reserva.
    return false;
  }
}
```

- [ ] **Step 6: Implemente a escolha**

Crie `lib/providers/vault_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/services/prefs_vault.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

/// Qual cofre o app conseguiu abrir, e se ele cifra.
///
/// Os dois campos andam juntos de propósito. A tela de contas precisa avisar
/// quando o segredo está em texto puro (decisão travada), e um `SecretVault`
/// sozinho não conta essa história: `PrefsVault` e `SecureStorageVault`
/// cumprem exatamente o mesmo contrato.
class VaultChoice {
  final SecretVault vault;

  /// `false` quer dizer texto puro. Na prática, Linux sem `gnome-keyring` nem
  /// KWallet no D-Bus.
  final bool encryptedAtRest;

  const VaultChoice(this.vault, {required this.encryptedAtRest});
}

/// Tenta o chaveiro do sistema; se ele não responder, cai para [buildFallback].
///
/// [buildFallback] é função e não valor para não abrir o `shared_preferences`
/// em todo boot de aparelho que tem chaveiro, que é a maioria.
Future<VaultChoice> chooseVault({
  required SecureStorageBackend backend,
  required Future<SecretVault> Function() buildFallback,
}) async {
  if (await probeSecureStorage(backend)) {
    return VaultChoice(SecureStorageVault(backend), encryptedAtRest: true);
  }
  return VaultChoice(await buildFallback(), encryptedAtRest: false);
}

final vaultProvider = FutureProvider<VaultChoice>((ref) {
  return chooseVault(
    backend: const PluginSecureStorage(),
    buildFallback: PrefsVault.open,
  );
});
```

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/secure_storage_vault_test.dart test/vault_provider_test.dart
```

Esperado: `+14`, zero falha. São sete do contrato, quatro da sonda e três da escolha.

**Tropeço provável:** `PrefsVault.open` no `buildFallback` do provider dá erro de tipo se você tiver declarado `open()` devolvendo `Future<PrefsVault>` e o parâmetro pedir `Future<SecretVault> Function()`. Em Dart isso **compila**, porque `Future<PrefsVault>` é subtipo de `Future<SecretVault>` e funções são covariantes no retorno. Se der erro, o que está errado é outra coisa, provavelmente `open()` sem `static`.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+380`, zero falha.

- [ ] **Step 9: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found` e `Built build/linux/x64/debug/bundle/roms_downloader`.

O `build` não é decoração nesta Task: é a única prova disponível nesta VM de que a dependência nova **liga** de verdade. Um plugin com nativo faltando passa em `flutter test` inteiro e quebra só na compilação. Se falhar com `libsecret-1.pc not found`, o pacote de desenvolvimento sumiu; conserte com `sudo apt-get update -qq && sudo apt-get install -y libsecret-1-dev`.

- [ ] **Step 10: Commit**

```bash
git add test/secure_storage_vault_test.dart test/vault_provider_test.dart
git commit -m "test(cofre): cofre do sistema, sonda de disponibilidade e escolha com reserva"
git add pubspec.yaml lib/services/secure_storage_vault.dart lib/providers/vault_provider.dart
git commit -m "feat(cofre): cofre do sistema, sonda de disponibilidade e escolha com reserva"
git add linux/flutter/generated_plugin_registrant.cc linux/flutter/generated_plugins.cmake \
        macos/Flutter/GeneratedPluginRegistrant.swift \
        windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
git commit -m "chore(cofre): registra o plugin do cofre nos tres alvos de desktop"
```

O terceiro commit é o único da fatia inteira, porque é a única Task que traz dependência com código nativo. Esses cinco arquivos são gerados, mas são **versionados** neste repositório (`git log -- linux/flutter/generated_plugin_registrant.cc` mostra que todo bump de plugin os carrega junto), e o `pub get` do Step 1 os reescreveu para registrar o `flutter_secure_storage`. Deixá-los de fora não quebra build nenhum, porque qualquer `pub get` os regenera, mas deixa cinco arquivos sujos no `git status` de todas as 23 Tasks seguintes, e aí um deslize de verdade passa despercebido no meio do ruído. O `pubspec.lock` continua fora, e ele sim fica sujo até o fim: a sujeira dele é anterior a esta fatia.

---

### Task 5: a migração que esvazia o `app_settings`

**Files:**
- Create: `lib/services/secret_migration.dart`
- Test: `test/secret_migration_test.dart`

Cofre novo não serve de nada enquanto o segredo velho continuar no lugar velho. Esta Task escreve a mudança única que tira os quatro segredos de dentro do JSON do `app_settings` e os põe no cofre.

Ela opera sobre o **mapa cru**, não sobre `AppSettings`, e devolve o mapa limpo em vez de salvar. Duas razões:

1. `AppSettings.fromJson` já **descarta** campo desconhecido em silêncio. Se a migração rodasse depois da desserialização, ela dependeria do modelo continuar carregando os campos que a Grupo 2 vai justamente tirar dele, e a ordem das duas Tasks viraria armadilha.
2. Devolver em vez de salvar mantém esta Task Dart puro, sem `shared_preferences` e sem `await` de plataforma. Quem salva é a Grupo 2.

**Não existe flag de "já migrei".** Depois da primeira passada o campo não está mais no mapa, então a segunda passada é naturalmente inócua. Se o salvamento falhar no meio, a próxima abertura tenta de novo, e é para esse caso que existe a regra "o cofre já preenchido ganha do arquivo": a cópia do arquivo é a velha, por definição.

O `builtinAddonId` entra por parâmetro porque a constante canônica (`kBuiltinAddonId`) só nasce na Grupo 3, e esta Task não pode depender dela. Quem preenche o parâmetro é a Task 6, com o `SettingsService.builtinAddonId` provisório; quem substitui o provisório pelo canônico é a Task 9.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/secret_migration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Conta escritas, para provar que um mapa sem segredo não encosta no cofre.
class _VaultEspiao extends MemoryVault {
  int escritas = 0;

  @override
  Future<void> write(String key, String value) {
    escritas++;
    return super.write(key, value);
  }
}

Map<String, dynamic> _settings({
  String? iaAccessKey,
  String? iaSecretKey,
  String? iaCookies,
  Map<String, dynamic>? consoleSettings,
}) {
  return {
    'consoleSettings': consoleSettings ?? <String, dynamic>{},
    'generalSettings': {'downloadDir': '/home/joao/roms', 'autoExtract': true},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
    if (iaCookies != null) 'iaCookies': iaCookies,
    'nszDecompressEnabled': true,
  };
}

void main() {
  test('as três credenciais do Internet Archive vão para o cofre', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz'));

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(SecretRef.iaSecretKey), 'SK');
    expect(await vault.read(SecretRef.iaCookies), 'logged-in-sig=xyz');
  });

  test('o token de cada console vai chaveado pelo addon, não só pelo console', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(consoleSettings: {
      'nintendo_64': {'downloadDir': '/roms/n64', 'authToken': 'tok-n64'},
      'snes': {'authToken': 'tok-snes'},
    }));

    expect(await vault.read(SecretRef.addonToken('builtin', 'nintendo_64')), 'tok-n64');
    expect(await vault.read(SecretRef.addonToken('builtin', 'snes')), 'tok-snes');
  });

  test('o mapa devolvido não tem mais nenhum dos quatro segredos', () async {
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(
      iaAccessKey: 'AK',
      iaSecretKey: 'SK',
      iaCookies: 'logged-in-sig=xyz',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    ));

    expect(limpo.containsKey('iaAccessKey'), isFalse);
    expect(limpo.containsKey('iaSecretKey'), isFalse);
    expect(limpo.containsKey('iaCookies'), isFalse);
    expect((limpo['consoleSettings'] as Map)['snes'], isNot(contains('authToken')));
  });

  test('o que não é segredo continua onde estava', () async {
    // Uma migração que limpa demais apaga a pasta de download do usuário.
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'downloadDir': '/roms/snes', 'authToken': 'tok-snes'},
      },
    ));

    expect(limpo['nszDecompressEnabled'], isTrue);
    expect((limpo['generalSettings'] as Map)['downloadDir'], '/home/joao/roms');
    expect((limpo['consoleSettings'] as Map)['snes'], containsPair('downloadDir', '/roms/snes'));
  });

  test('o cofre já preenchido ganha do arquivo, mas o texto puro sai mesmo assim', () async {
    // Acontece quando a primeira passada gravou no cofre e o salvamento do
    // arquivo limpo não chegou a acontecer. A cópia do arquivo é, por
    // definição, a velha: sobrescrever com ela devolveria ao usuário um token
    // que ele já trocou. Mas o texto puro tem que sair de qualquer jeito,
    // senão a migração nunca termina e o segredo mora nos dois lugares.
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'novo');
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(iaAccessKey: 'velho'));

    expect(await vault.read(SecretRef.iaAccessKey), 'novo');
    expect(limpo.containsKey('iaAccessKey'), isFalse);
  });

  test('valor vazio não vira chave no cofre', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(iaAccessKey: ''));

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
  });

  test('um consoleSettings malformado não derruba a migração', () async {
    // O arquivo vem do disco de um usuário que pode ter editado à mão, e a
    // migração roda na abertura do app. Um `as Map` otimista aqui vira app que
    // não abre, e o usuário não tem como consertar sem achar o arquivo.
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final limpo = await migracao.drain({
      'consoleSettings': {
        'snes': 'isto deveria ser um mapa',
        'n64': {'authToken': 'tok-n64'},
      },
      'nszDecompressEnabled': true,
    });

    expect(await vault.read(SecretRef.addonToken('builtin', 'n64')), 'tok-n64');
    expect((limpo['consoleSettings'] as Map)['snes'], 'isto deveria ser um mapa');
  });

  test('não muta o mapa que recebeu', () async {
    // O chamador da Grupo 2 tem o mapa que acabou de desserializar em mãos. Se
    // a migração mexer nele por dentro, o `consoleSettings` aninhado é o mesmo
    // objeto, e o token some do mapa do chamador antes de qualquer coisa ter
    // sido salva. Um `Map.from` raso não basta, e é esse o erro que este caso
    // pega.
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');
    final original = _settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    );

    await migracao.drain(original);

    expect(original['iaAccessKey'], 'AK');
    expect((original['consoleSettings'] as Map)['snes'], containsPair('authToken', 'tok-snes'));
  });

  test('um mapa sem segredo nenhum não escreve nada no cofre', () async {
    // A migração roda em toda abertura do app. No Linux com chaveiro, cada
    // escrita é uma ida ao D-Bus; no aparelho de quem nunca fez login, o número
    // certo de idas é zero.
    final vault = _VaultEspiao();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(consoleSettings: {
      'snes': {'downloadDir': '/roms/snes'},
    }));

    expect(vault.escritas, 0);
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_migration_test.dart
```

Esperado: `Undefined name 'SecretMigration'`.

- [ ] **Step 3: Implemente**

Crie `lib/services/secret_migration.dart`:

```dart
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
```

- [ ] **Step 4: Rode para ver passar**

```bash
flutter test test/secret_migration_test.dart
```

Esperado: `+11`, zero falha.

**Tropeço provável:** o caso "não muta o mapa que recebeu" falha se você escrever `final limpo = Map<String, dynamic>.from(raw)` e mexer direto em `consoles`. O `Map.from` é raso: o `consoleSettings` da cópia é **o mesmo objeto** do original. Copiar cada mapa de console é o que fecha isso, e é por isso que o laço monta um `novos` em vez de editar no lugar.

- [ ] **Step 5: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+389`, zero falha.

- [ ] **Step 6: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/secret_migration_test.dart
git commit -m "test(cofre): migracao unica que esvazia os segredos do app_settings"
git add lib/services/secret_migration.dart
git commit -m "feat(cofre): migracao unica que esvazia os segredos do app_settings"
```

**Fim da Grupo 1.** O cofre existe, sabe qual implementação usar, sabe dizer se cifra, e sabe esvaziar o lugar velho. Nada disso está ligado ao app ainda: `flutter run` neste ponto se comporta exatamente como antes. Quem liga é a Grupo 2.

| Task | Novos | Acumulado |
| --- | --- | --- |
| linha de base | 0 | 340 |
| 1, `SecretRef` | 7 | 347 |
| 2, `SecretVault` e contrato | 8 | 355 |
| 3, `PrefsVault` | 11 | 366 |
| 4, `SecureStorageVault` e escolha | 14 | 380 |
| 5, migração | 9 | 389 |

---

## Grupo 2: a correção da 6.3

Três Tasks. A Grupo 1 construiu o cofre sem ligar fio nenhum; aqui os fios são ligados, e é aqui que a seção 6.3 do spec é cumprida.

A ordem importa e não é negociável: **o segredo só sai do arquivo depois de já estar no cofre**. Por isso a Task 6 faz as duas metades no mesmo commit, em vez de "primeiro para de escrever, depois passa a guardar". Entre esses dois commits existiria uma janela em que o token do usuário não estaria em lugar nenhum.

### Task 6: os segredos passam a morar no cofre

**Files:**
- Modify: `lib/models/settings_model.dart:82-96` e `:151-160`
- Modify: `lib/services/settings_service.dart`
- Modify: `lib/providers/settings_provider.dart`
- Test: `test/settings_model_secrets_test.dart`
- Test: `test/settings_service_test.dart`

Uma assimetria de propósito, que é a única coisa sutil desta Task: **`toJson` para de escrever os segredos, e `fromJson` continua sabendo lê-los.** Não é descuido. O arquivo do usuário que ainda não migrou tem os campos lá, e quem os tira é a migração da Task 5, que roda sobre o mapa cru. Tirar a leitura junto não ganharia nada e transformaria qualquer caminho que pule a migração em perda silenciosa.

A outra decisão que merece ser lida antes de codar: **salvar nunca apaga segredo.** `saveSettings` grava o que existe e ignora o que está `null`. Apagar é operação explícita, com método próprio. A razão é uma corrida real: `SettingsNotifier` já salva a partir de ações do usuário enquanto `_loadSettings` ainda está no ar, e um `saveSettings` que apagasse tudo que está `null` transformaria um clique apressado no boot em perda de todas as credenciais. Ninguém perceberia até o próximo download falhar.

- [ ] **Step 1: Escreva o teste do modelo**

Crie `test/settings_model_secrets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';

void main() {
  test('o JSON salvo não leva as três credenciais do Internet Archive', () {
    const settings = AppSettings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz');

    final json = settings.toJson();

    expect(json.containsKey('iaAccessKey'), isFalse);
    expect(json.containsKey('iaSecretKey'), isFalse);
    expect(json.containsKey('iaCookies'), isFalse);
  });

  test('o JSON salvo não leva o token de console', () {
    const console = BaseSettings(downloadDir: '/roms/snes', authToken: 'tok-snes');

    final json = console.toJson();

    expect(json.containsKey('authToken'), isFalse);
    expect(json['downloadDir'], '/roms/snes');
  });

  test('ler o formato legado continua funcionando', () {
    // Assimetria deliberada: escreve sem, lê com. O arquivo de quem ainda não
    // migrou tem os campos lá, e quem os tira é a migração da Task 5, que roda
    // sobre o mapa cru. Tirar a leitura junto não fecharia buraco nenhum e
    // faria qualquer caminho que pule a migração perder o token em silêncio.
    final settings = AppSettings.fromJson({
      'iaAccessKey': 'AK',
      'consoleSettings': {
        'snes': {'authToken': 'tok-snes'},
      },
    });

    expect(settings.iaAccessKey, 'AK');
    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
  });

  test('o que não é segredo continua sendo salvo', () {
    const settings = AppSettings(nszDecompressEnabled: false, catalogSourceUrl: 'https://exemplo/consoles.json');

    final json = settings.toJson();

    expect(json['nszDecompressEnabled'], isFalse);
    expect(json['catalogSourceUrl'], 'https://exemplo/consoles.json');
  });
}
```

- [ ] **Step 2: Escreva o teste do serviço**

Crie `test/settings_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

Future<SharedPreferences> _prefsCom(Map<String, Object> valores) async {
  SharedPreferences.setMockInitialValues(valores);
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

String _appSettings({String? iaAccessKey, String? authTokenSnes}) {
  return jsonEncode({
    'consoleSettings': {
      'snes': {
        'downloadDir': '/roms/snes',
        if (authTokenSnes != null) 'authToken': authTokenSnes,
      },
    },
    'generalSettings': {'downloadDir': '/home/joao/roms'},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    'nszDecompressEnabled': true,
  });
}

String _chaveDoSnes() => SecretRef.addonToken(SettingsService.builtinAddonId, 'snes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carregar tira o segredo do arquivo e o põe no cofre', () async {
    await _prefsCom({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});
    final vault = MemoryVault();

    await SettingsService().loadSettings(vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('carregar devolve as settings com o segredo, lido do cofre', () async {
    // O app inteiro lê `settings.consoleSettings[id].authToken`. Se a carga
    // drenasse sem reidratar, a migração apagaria o login de todo mundo na
    // primeira abertura depois da atualização.
    await _prefsCom({'app_settings': _appSettings(authTokenSnes: 'tok-snes')});

    final settings = await SettingsService().loadSettings(MemoryVault());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('carregar reescreve o app_settings sem o segredo', () async {
    final prefs = await _prefsCom({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});

    await SettingsService().loadSettings(MemoryVault());

    final salvo = prefs.getString('app_settings')!;
    expect(salvo, isNot(contains('AK')));
    expect(salvo, isNot(contains('tok-snes')));
    expect(salvo, contains('/roms/snes'));
  });

  test('carregar não reescreve o app_settings quando não havia segredo', () async {
    // A carga roda em toda abertura. Reescrever sempre é escrita em disco por
    // nada, e some com a pista de quando a migração de fato aconteceu.
    final semSegredo = _appSettings();
    final prefs = await _prefsCom({'app_settings': semSegredo});

    await SettingsService().loadSettings(MemoryVault());

    expect(prefs.getString('app_settings'), semSegredo);
  });

  test('salvar grava o segredo no cofre', () async {
    await _prefsCom({'app_settings': _appSettings()});
    final vault = MemoryVault();
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('salvar não escreve segredo dentro do app_settings', () async {
    final prefs = await _prefsCom({'app_settings': _appSettings()});
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, MemoryVault());

    expect(prefs.getString('app_settings'), isNot(contains('AK')));
    expect(prefs.getString('app_settings'), isNot(contains('tok-snes')));
  });

  test('salvar NÃO apaga do cofre o que está null nas settings', () async {
    // A corrida real: `SettingsNotifier` salva a partir de ação do usuário
    // enquanto a carga ainda está no ar, e nesse instante o estado é
    // `const AppSettings()`, tudo null. Se salvar apagasse o que está null, um
    // clique apressado no boot levaria todas as credenciais junto, sem erro
    // nenhum na tela. Apagar é operação explícita, e tem método próprio.
    await _prefsCom({'app_settings': _appSettings()});
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(_chaveDoSnes(), 'tok-snes');

    await SettingsService().saveSettings(const AppSettings(), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('apagar as credenciais do IA leva as três', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(SecretRef.iaSecretKey, 'SK');
    await vault.write(SecretRef.iaCookies, 'logged-in-sig=xyz');

    await SettingsService().clearIaSecrets(vault);

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
    expect(await vault.read(SecretRef.iaSecretKey), isNull);
    expect(await vault.read(SecretRef.iaCookies), isNull);
  });

  test('apagar o token de um console não leva o do vizinho', () async {
    final vault = MemoryVault();
    await vault.write(_chaveDoSnes(), 'tok-snes');
    await vault.write(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64'), 'tok-n64');

    await SettingsService().clearConsoleToken('snes', vault);

    expect(await vault.read(_chaveDoSnes()), isNull);
    expect(await vault.read(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64')), 'tok-n64');
  });
}
```

- [ ] **Step 3: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/settings_model_secrets_test.dart test/settings_service_test.dart
```

Esperado: os do modelo falham em asserção (`Expected: false, Actual: true`, porque hoje o `toJson` escreve mesmo), e os do serviço falham em compilação (`loadSettings` não aceita argumento).

- [ ] **Step 4: Tire os segredos do `toJson`**

Em `lib/models/settings_model.dart`, no `AppSettings.toJson` (linhas 82-96), **apague** as três linhas:

```dart
      if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
      if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
      if (iaCookies != null) 'iaCookies': iaCookies,
```

e, no `BaseSettings.toJson` (linhas 151-160), **apague**:

```dart
      if (authToken != null) 'authToken': authToken,
```

**Não toque nos `fromJson`.** A assimetria é o ponto.

- [ ] **Step 5: Ligue o cofre no `SettingsService`**

Reescreva `lib/services/settings_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';

  /// O addon a que pertencem os consoles do catálogo de hoje.
  ///
  /// Enquanto existe uma fonte só, este id é constante. Quando houver N
  /// addons, este espelho continua sendo só do embutido, e o token dos outros
  /// passa a ser lido sob demanda no cofre (Task 19). Ele vive aqui, e não em
  /// [SecretRef], porque é fato sobre a instalação e não sobre o formato da
  /// chave.
  static const String builtinAddonId = 'builtin';

  final DirectoryService _directoryService = DirectoryService();

  Future<AppSettings> loadSettings(SecretVault vault) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);

      if (settingsJson != null) {
        final cru = jsonDecode(settingsJson) as Map<String, dynamic>;
        final limpo = await SecretMigration(vault: vault, builtinAddonId: builtinAddonId).drain(cru);

        // Só reescreve se a migração de fato tirou alguma coisa. A carga roda
        // em toda abertura do app; reescrever sempre é escrita em disco por
        // nada. A comparação é segura porque `drain` não mexe no mapa que
        // recebeu.
        final limpoJson = jsonEncode(limpo);
        if (limpoJson != jsonEncode(cru)) {
          await prefs.setString(_settingsKey, limpoJson);
        }

        final hidratado = await _hydrate(AppSettings.fromJson(limpo), vault);
        return hidratado;
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    final defaultDownloadDir = await _directoryService.getDownloadDir();
    return AppSettings(
      generalSettings: BaseSettings(downloadDir: defaultDownloadDir, autoExtract: true),
    );
  }

  /// Devolve as settings com os segredos postos de volta, vindos do cofre.
  ///
  /// Sem isto, a migração seria perda de dados: o app inteiro lê
  /// `settings.consoleSettings[id].authToken`, e ele acabou de sair do arquivo.
  Future<AppSettings> _hydrate(AppSettings settings, SecretVault vault) async {
    final consoles = <String, BaseSettings>{};
    for (final entrada in settings.consoleSettings.entries) {
      final token = await vault.read(SecretRef.addonToken(builtinAddonId, entrada.key));
      consoles[entrada.key] = token == null ? entrada.value : entrada.value.copyWith(authToken: token);
    }

    return settings.copyWith(
      consoleSettings: consoles,
      iaAccessKey: await vault.read(SecretRef.iaAccessKey),
      iaSecretKey: await vault.read(SecretRef.iaSecretKey),
      iaCookies: await vault.read(SecretRef.iaCookies),
    );
  }

  Future<void> saveSettings(AppSettings settings, SecretVault vault) async {
    try {
      await _writeSecrets(settings, vault);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Grava o que existe e **não apaga o que está `null`**.
  ///
  /// Apagar aqui seria tentador e é errado: `SettingsNotifier` salva a partir
  /// de ação do usuário enquanto a carga ainda está no ar, e nesse instante o
  /// estado é `const AppSettings()`, tudo `null`. Salvar apagando transformaria
  /// um clique apressado no boot em perda de todas as credenciais, sem erro na
  /// tela. Quem apaga são [clearIaSecrets] e [clearConsoleToken], chamados de
  /// propósito.
  Future<void> _writeSecrets(AppSettings settings, SecretVault vault) async {
    await _writeIfPresent(vault, SecretRef.iaAccessKey, settings.iaAccessKey);
    await _writeIfPresent(vault, SecretRef.iaSecretKey, settings.iaSecretKey);
    await _writeIfPresent(vault, SecretRef.iaCookies, settings.iaCookies);
    for (final entrada in settings.consoleSettings.entries) {
      await _writeIfPresent(vault, SecretRef.addonToken(builtinAddonId, entrada.key), entrada.value.authToken);
    }
  }

  Future<void> _writeIfPresent(SecretVault vault, String chave, String? valor) async {
    if (valor == null || valor.isEmpty) return;
    await vault.write(chave, valor);
  }

  Future<void> clearIaSecrets(SecretVault vault) async {
    await vault.delete(SecretRef.iaAccessKey);
    await vault.delete(SecretRef.iaSecretKey);
    await vault.delete(SecretRef.iaCookies);
  }

  Future<void> clearConsoleToken(String consoleId, SecretVault vault) async {
    await vault.delete(SecretRef.addonToken(builtinAddonId, consoleId));
  }

  T? getGeneralSetting<T>(AppSettings settings, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.generalSettings.getSetting<T>(key);
  }

  T? getConsoleSetting<T>(AppSettings settings, String consoleId, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.consoleSettings[consoleId]?.getSetting<T>(key);
  }

  T? getSetting<T>(AppSettings settings, String key, [String? consoleId]) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    if (consoleId != null) {
      final consoleValue = getConsoleSetting<T>(settings, consoleId, key);
      if (consoleValue != null) return consoleValue;
    }
    return getGeneralSetting<T>(settings, key);
  }

  Future<String?> selectDownloadDirectory() async {
    return await _directoryService.selectDownloadDirectory();
  }
}
```

- [ ] **Step 6: Passe o cofre pelo provider**

Em `lib/providers/settings_provider.dart`, o provider ganha o cofre:

```dart
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(vaultProvider.future).then((escolha) => escolha.vault));
});
```

com os imports novos:

```dart
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
```

No `SettingsNotifier`, o topo da classe:

```dart
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _settingsService = SettingsService();
  final Future<SecretVault> _vault;

  SettingsNotifier(this._vault) : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings(await _vault);
    state = settings;
  }

  /// Troca o estado e salva. Existe porque onze métodos faziam as duas linhas
  /// na mão, e agora cada um deles precisaria também esperar o cofre.
  Future<void> _persist(AppSettings novo) async {
    state = novo;
    await _settingsService.saveSettings(novo, await _vault);
  }
```

Agora troque, nos **onze** sítios, o par

```dart
    state = newState;
    await _settingsService.saveSettings(newState);
```

por

```dart
    await _persist(newState);
```

Confira que sobraram zero:

```bash
grep -c "saveSettings(newState)" lib/providers/settings_provider.dart
```

Esperado: `0`.

Por fim, os dois métodos que apagam credencial passam a apagar de verdade:

```dart
  Future<void> setConsoleAuthToken(String consoleId, String token) async {
    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    final updated = token.isEmpty
        ? current.copyWith(clearAuthToken: true)
        : current.copyWith(authToken: token);
    if (token.isEmpty) {
      // `saveSettings` de propósito não apaga o que está null. Sair da conta
      // tem que apagar, e é aqui que isso é dito.
      await _settingsService.clearConsoleToken(consoleId, await _vault);
    }
    await _persist(state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    ));
  }

  Future<void> clearIaCredentials() async {
    await _settingsService.clearIaSecrets(await _vault);
    await _persist(state.copyWith(clearIaCredentials: true));
  }
```

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/settings_model_secrets_test.dart test/settings_service_test.dart
```

Esperado: `+13`, zero falha.

**Tropeço provável:** o caso "carregar não reescreve o app_settings quando não havia segredo" falha por diferença de formatação, e não de conteúdo, se o `_appSettings()` do teste tiver sido escrito à mão em vez de por `jsonEncode`. A comparação é entre duas saídas de `jsonEncode` sobre o mesmo mapa, que são idênticas caractere a caractere; texto digitado à mão com espaço depois dos dois-pontos não é.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+402`, zero falha.

Se algum teste **antigo** quebrar aqui, leia antes de consertar: pode ser teste que afirmava que o token ia no JSON, e aí ele estava certo ontem e está errado hoje. Conserte o teste dizendo por quê no commit. Se for teste que não fala de segredo, é regressão sua.

- [ ] **Step 9: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found` e build ok.

- [ ] **Step 10: Commit**

```bash
git add test/settings_model_secrets_test.dart test/settings_service_test.dart
git commit -m "test(cofre): segredo sai do app_settings e passa a morar no cofre"
git add lib/models/settings_model.dart lib/services/settings_service.dart lib/providers/settings_provider.dart
git commit -m "feat(cofre): segredo sai do app_settings e passa a morar no cofre"
```

---

### Task 7: o token para de vir do arquivo, nos quatro sítios

**Files:**
- Create: `lib/utils/console_auth.dart`
- Modify: `lib/utils/network.dart:41`
- Modify: `lib/services/task_queue_service.dart:20`
- Modify: `lib/screens/tinfoil_server_screen.dart:91`
- Modify: `lib/screens/setup_wizard_screen.dart:392`
- Test: `test/console_auth_test.dart`

Esta é a Task que fecha o vazamento de verdade, e é a metade da 6.3 que vale em toda plataforma, com chaveiro ou sem.

O spec lista dois sítios. São **quatro**. Os dois que ele não lista não montam header: eles decidem se a tela mostra o console como conectado, com a mesma expressão copiada nos dois arquivos. Se ficarem, o app passa a dizer "este console tem auth configurada" com base num campo que ninguém mais lê para autenticar. Não é vazamento, é mentira de interface, e some do radar de qualquer `grep` por `buildConsoleAuthHeaders`.

Os dois viram uma função só, em arquivo novo, porque expressão duplicada em duas telas foi exatamente o que fez o spec contar dois em vez de quatro.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/console_auth_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/utils/console_auth.dart';
import 'package:roms_downloader/utils/network.dart';

void main() {
  group('buildConsoleAuthHeaders', () {
    test('o token que está no catálogo é ignorado', () {
      // A falha da seção 6.3, literal. O catálogo é o arquivo que o usuário
      // manda para outra pessoa; nada o cifra e nada avisa que tem segredo
      // dentro. Depois desta Task ele pode até conter o campo, que não
      // autentica ninguém.
      final headers = buildConsoleAuthHeaders({'token': 'tok-do-arquivo'});

      expect(headers, isEmpty);
    });

    test('o token de quem chama monta Bearer', () {
      final headers = buildConsoleAuthHeaders({}, tokenOverride: 'tok-do-cofre');

      expect(headers, {'Authorization': 'Bearer tok-do-cofre'});
    });

    test('com cookies, monta Cookie com o nome do catálogo', () {
      final headers = buildConsoleAuthHeaders(
        {'cookies': true, 'cookie_name': 'ultranx_session'},
        tokenOverride: 'tok-do-cofre',
      );

      expect(headers, {'Cookie': 'ultranx_session=tok-do-cofre'});
    });

    test('sem cookie_name, o nome padrão é auth_token', () {
      final headers = buildConsoleAuthHeaders({'cookies': true}, tokenOverride: 'tok-do-cofre');

      expect(headers, {'Cookie': 'auth_token=tok-do-cofre'});
    });

    test('ia_s3 não monta header nem com token de quem chama', () {
      // O Internet Archive assina de outro jeito, e um Bearer aqui quebraria
      // o download em vez de autenticar.
      final headers = buildConsoleAuthHeaders({'type': 'ia_s3'}, tokenOverride: 'tok-do-cofre');

      expect(headers, isEmpty);
    });

    test('console sem auth não monta header', () {
      expect(buildConsoleAuthHeaders(null, tokenOverride: 'tok-do-cofre'), isEmpty);
    });
  });

  group('consoleHasToken', () {
    test('o token do catálogo não conta como conectado', () {
      // Este é o caso que o spec não lista. Sem ele, a tela do Tinfoil e o
      // assistente mostram "conectado" lendo um campo que a Task inteira
      // acabou de tirar do caminho de autenticação.
      const settings = AppSettings();

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });

    test('o token das settings conta', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: 'tok-do-cofre')});

      expect(consoleHasToken(settings, 'ultranx'), isTrue);
    });

    test('token vazio não conta', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: '')});

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/console_auth_test.dart
```

Esperado: erro de compilação em `console_auth.dart`. Depois de criar o arquivo, o primeiro caso de `buildConsoleAuthHeaders` falha com `Expected: empty, Actual: {'Authorization': 'Bearer tok-do-arquivo'}`, que é a 6.3 em uma linha.

- [ ] **Step 3: Corte o termo do arquivo em `network.dart`**

Em `lib/utils/network.dart`, linha 41, troque

```dart
  final token = tokenOverride ?? auth['token'] as String?;
```

por

```dart
  // Só de quem chama, que leu do cofre. Antes havia `?? auth['token']`, isto
  // é, o catálogo, que é o arquivo que o usuário compartilha com outra pessoa
  // (seção 6.3 do spec). O campo pode continuar existindo no JSON de terceiro:
  // ele simplesmente não autentica mais ninguém.
  final token = tokenOverride;
```

- [ ] **Step 4: Corte o termo do meio em `task_queue_service.dart`**

Linha 20, troque

```dart
      final token = settings.consoleSettings[console.id]?.authToken ?? console.auth?['token'] as String? ?? '';
```

por

```dart
      final token = settings.consoleSettings[console.id]?.authToken ?? '';
```

- [ ] **Step 5: Crie o predicado compartilhado**

Crie `lib/utils/console_auth.dart`:

```dart
import 'package:roms_downloader/models/settings_model.dart';

/// Se o app tem token para este console.
///
/// Serve para a UI decidir se mostra o console como conectado. Lê **só** as
/// settings, que desde a Task 6 vêm do cofre.
///
/// Existe como função em vez de expressão inline porque a expressão estava
/// copiada em duas telas, e foi essa duplicação que fez a seção 6.3 do spec
/// contar dois sítios quando são quatro: um `grep` por
/// `buildConsoleAuthHeaders` não acha nenhuma das duas.
bool consoleHasToken(AppSettings settings, String consoleId) => settings.consoleSettings[consoleId]?.authToken?.isNotEmpty ?? false;
```

- [ ] **Step 6: Troque as duas telas**

Em `lib/screens/tinfoil_server_screen.dart`, linha 91, apague o `bool authed(Console c) => ...` inteiro e troque os usos de `authed(c)` por `consoleHasToken(settings, c.id)`. Mesma coisa em `lib/screens/setup_wizard_screen.dart`, linha 392. Os dois arquivos ganham:

```dart
import 'package:roms_downloader/utils/console_auth.dart';
```

Confira que nenhum dos quatro sobrou:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

Esperado: **exatamente uma linha**, o comentário que o Step 3 acabou de escrever em `lib/utils/network.dart:41`, que cita `` `?? auth['token']` `` entre crases para registrar o que havia ali. É texto, não leitura. Confira olhando a linha, não só contando. Qualquer segunda linha é sítio vivo que sobrou.

Se aparecer alguma em `console_model.dart`, leia antes de consertar. O `toJson`/`fromJson` do modelo continua sabendo carregar o campo, e isso é certo. Mas `Console.hasTokenAuth` (`console_model.dart:55-59`) também lê `auth!.containsKey('token')`, e esse **não** é sítio desta Task: ele não pergunta "qual é o token", pergunta "este console aceita token", que é capacidade declarada pelo catálogo e não segredo. Quem mexe nele é a Task 8, que troca a pergunta por `requires_token`. Não antecipe aqui.

**O `-E` é obrigatório, não é estilo.** Sem ele o `grep` é BRE, e aí `\?` vira quantificador sobre o `h` de `auth` enquanto o segundo `?` vira literal: o padrão passa a exigir uma `?` depois de `auth`, e **os únicos três sítios que casam são os que têm `auth?[`**. O quarto, `network.dart:41`, escreve `auth['token']` sem `?` e escapa. Medido antes da Task rodar, com os quatro ainda no lugar: o BRE achou três, o `-E` achou quatro. Quer dizer que a checagem em BRE daria "nenhuma linha" mesmo para quem esquecesse o Step 3, que é justamente o sítio que a seção 6.3 lista.

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/console_auth_test.dart
```

Esperado: `+9`, zero falha. São os seis casos de `buildConsoleAuthHeaders` mais os três de `consoleHasToken`, que é o que o bloco do Step 1 tem. Este número já esteve escrito como `+11` e estava errado: quem fecha a conta é o Step 8, e `402 + 9 = 411` bate, enquanto `402 + 11` daria 413. Corrigido depois de medir `+9: All tests passed!` no arquivo isolado.

**Tropeço provável:** `flutter analyze` acusando `unused_local_variable` para o `settings` do `setup_wizard_screen.dart`, se as duas telas usavam `settings` só dentro do `authed`. Se acontecer, `consoleHasToken(settings, c.id)` continua precisando dele, então o aviso quer dizer que você trocou por outra coisa.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+411`, zero falha.

- [ ] **Step 9: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/console_auth_test.dart
git commit -m "test(seguranca): token de autenticacao para de vir do catalogo compartilhado"
git add lib/utils/console_auth.dart lib/utils/network.dart lib/services/task_queue_service.dart lib/screens/tinfoil_server_screen.dart lib/screens/setup_wizard_screen.dart
git commit -m "feat(seguranca): token de autenticacao para de vir do catalogo compartilhado"
```

---

### Task 8: instalar catálogo colhe o token e limpa o arquivo

**Files:**
- Modify: `lib/services/catalog_service.dart:109-135`
- Modify: `lib/models/console_model.dart:55-59`
- Modify: `lib/screens/setup_wizard_screen.dart:94` e `:108`
- Modify: `lib/widgets/settings/catalog_source_setting.dart:74` e `:82`
- Test: `test/catalog_auth_token_test.dart`

A Task 7 fez o token do arquivo parar de autenticar. Esta faz ele parar de **existir** no arquivo salvo. O spec escreve as duas metades: "Na instalação, se o JSON vier com `auth.token` preenchido, o app move para o `flutter_secure_storage` e zera no arquivo salvo. Na exportação, remove."

Três notas de escopo, medidas:

- **Não existe exportação de catálogo hoje.** `grep -rni "export" lib/ --include=*.dart` só acha as favoritas, que são outra coisa. A metade "na exportação, remove" não tem sítio nesta fatia. A Grupo 6 fecha isso por outro lado, com o teste de contrato do RTS, que é o único produtor deste formato no app.
- **`addConsole` não pode carregar token hoje.** Ele passa o `Console.toJson()` adiante, e a tela que constrói esse console (`add_catalog_source_screen.dart`) não tem campo de `auth`: `grep -n "auth" lib/screens/add_catalog_source_screen.dart` não devolve nada. Se um dia tiver, a colheita tem que passar por ali também.
- **Tirar a chave `token` apaga a tela de login, e por isso a colheita deixa uma marca no lugar.** Isto não é detalhe: é o efeito colateral que transformaria esta Task numa regressão silenciosa. `Console.hasTokenAuth` (`console_model.dart:55-59`) responde `auth!.containsKey('token') || auth!.containsKey('auth_message')`, e esse getter tem três leitores (`grep -rn "hasTokenAuth" lib/`): ele decide se a seção "Authentication" aparece nas settings (`settings_content.dart:152`), se o `task_queue_service` bloqueia download sem token (`task_queue_service.dart:18`) e quais consoles a tela do Tinfoil lista como precisando de login (`tinfoil_server_screen.dart:86`). Um catálogo privado cujo bloco de auth seja só `{'token': 'x'}`, que é o caso exato para o qual a fatia 4 existe, ficaria depois da colheita com `auth` vazio: sumia a tela onde o usuário digita o token, e sumia o bloqueio que avisa que falta token. O usuário perderia a auth e o app não diria nada. Por isso a colheita grava `requires_token: true` sempre que retira a chave, e o getter passa a aceitar essa marca. A marca **não é segredo**: ela diz que o console pede token, não qual é. Pode ir para o arquivo compartilhado à vontade, e é justamente onde ela precisa estar, porque é o arquivo que descreve o console.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/catalog_auth_token_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

void main() {
  test('o token sai do catálogo salvo', () async {
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'url': 'https://ultranx.exemplo/',
          'auth': {'token': 'tok-secreto', 'cookies': true},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    expect(limpo, isNot(contains('tok-secreto')));
  });

  test('o token colhido vai para o cofre, chaveado por addon e console', () async {
    final vault = MemoryVault();

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-secreto');
  });

  test('o resto do auth sobrevive', () async {
    // Limpar demais aqui quebra o login: `cookies`, `cookie_name`, `signin` e
    // `message` são configuração do catálogo, não segredo.
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {
            'token': 'tok-secreto',
            'cookies': true,
            'cookie_name': 'ultranx_session',
            'message': 'Entre para baixar',
          },
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(limpo) as List).first['auth'] as Map;
    expect(auth['cookies'], isTrue);
    expect(auth['cookie_name'], 'ultranx_session');
    expect(auth['message'], 'Entre para baixar');
    expect(auth.containsKey('token'), isFalse);
    expect(auth['requires_token'], isTrue);
  });

  test('o console limpo continua declarando que pede token', () async {
    // O caso que faz esta Task ser uma correção e não uma regressão. Sem a
    // marca, um console cujo bloco de auth era só o token fica com `auth`
    // vazio, `hasTokenAuth` vira falso, e o usuário perde de uma vez a tela
    // onde digitaria o token e o aviso de que falta token. Ele veria uma fonte
    // privada falhando calada.
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(limpo) as List).first['auth'] as Map<String, dynamic>;
    final console = Console(id: 'ultranx', name: 'UltraNX', urls: const [], auth: auth);

    expect(console.hasTokenAuth, isTrue);
  });

  test('console sem auth passa intacto', () async {
    final original = jsonEncode([
      {'name': 'Nintendo 64', 'url': 'https://exemplo/n64/'},
    ]);

    final limpo = await CatalogService.harvestAuthTokens(original, vault: MemoryVault(), addonId: 'x');

    expect(jsonDecode(limpo), jsonDecode(original));
  });

  test('o formato de mapa legado também é limpo', () async {
    // O app aceita as duas formas (`catalog_service.dart:79-100`). Limpar só a
    // de array deixaria o buraco aberto para quem usa a antiga, que é
    // exatamente quem tem catálogo mais velho.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode({
        'ultranx': {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      }),
      vault: vault,
      addonId: 'meu_addon',
    );

    expect(limpo, isNot(contains('tok-secreto')));
    expect(await vault.read(SecretRef.addonToken('meu_addon', 'ultranx')), 'tok-secreto');
  });

  test('token vazio não cria chave no cofre, mas deixa a marca', () async {
    // `{'token': ''}` é como um catálogo compartilhado declara "este console
    // pede token, e eu não estou te dando o meu". Não há segredo para guardar,
    // e a marca tem que ficar do mesmo jeito: é ela que mantém a tela de login
    // de pé para o usuário digitar o token dele.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': '', 'cookies': true},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), isNull);
    expect((jsonDecode(limpo) as List).first['auth']['requires_token'], isTrue);
  });

  test('a entrada de descoberta também perde o token', () async {
    // `list_systems: true` não vira console (`catalog_service.dart:87`), então
    // é tentador pular. Não pule: o arquivo compartilhado é o mesmo, e o token
    // lá dentro vaza igual. Ele vai para o cofre pelo id do nome, para não ser
    // perdido se um dia o app passar a usar essas entradas.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'Descoberta',
          'list_systems': true,
          'auth': {'token': 'tok-descoberta'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(limpo, isNot(contains('tok-descoberta')));
    expect(await vault.read(SecretRef.addonToken('ultranx', 'descoberta')), 'tok-descoberta');
  });

  test('o cofre já preenchido ganha do arquivo', () async {
    // Mesma regra da migração: reinstalar um catálogo velho não pode devolver
    // ao usuário um token que ele já trocou.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'ultranx'), 'tok-novo');

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-velho'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-novo');
  });

  test('JSON de formato desconhecido volta como veio', () async {
    // Quem valida formato é `setCatalogFromJson`, com mensagem de erro própria.
    // A colheita não pode levantar antes e trocar essa mensagem por um stack
    // trace.
    const cru = '"isto não é um catálogo"';

    expect(await CatalogService.harvestAuthTokens(cru, vault: MemoryVault(), addonId: 'x'), cru);
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/catalog_auth_token_test.dart
```

Esperado: `Undefined name 'harvestAuthTokens'`.

- [ ] **Step 3: Implemente a colheita**

Em `lib/services/catalog_service.dart`, some os imports

```dart
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_vault.dart';
```

e o método estático, logo acima de `setCatalogFromJson`:

```dart
  /// Tira `auth.token` de todo o catálogo e guarda o que achou no cofre.
  ///
  /// O catálogo é o arquivo que o usuário compartilha com outra pessoa. O
  /// formato permite token lá dentro, e a seção 6.3 do spec manda mover para o
  /// cofre na instalação. Esta é a metade da correção que vale em toda
  /// plataforma: tirar do arquivo não depende de haver chaveiro.
  ///
  /// Onde havia `token`, deixa `requires_token: true`. A marca não é segredo:
  /// ela diz que o console pede token, não qual é, e o arquivo que descreve o
  /// console é exatamente o lugar dela. Sem a marca, [Console.hasTokenAuth]
  /// viraria falso e o usuário perderia a tela onde digitaria o token.
  ///
  /// Devolve o JSON limpo. Não valida formato: quem valida é
  /// [setCatalogFromJson], que tem mensagem de erro própria, e levantar aqui
  /// trocaria essa mensagem por um stack trace.
  static Future<String> harvestAuthTokens(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final decoded = jsonDecode(jsonStr);

    Future<void> colher(String id, Map<dynamic, dynamic> item) async {
      final auth = item['auth'];
      if (auth is! Map) return;
      if (!auth.containsKey('token')) return;
      final token = auth.remove('token');
      // A marca entra mesmo quando o token vem vazio, porque é o `containsKey`
      // que ela substitui, não o valor. `{'token': ''}` é como um catálogo
      // compartilhado diz "este console pede token e eu não estou te dando o
      // meu": quem lê tem que continuar sabendo disso.
      auth['requires_token'] = true;
      if (token is! String || token.isEmpty) return;
      final chave = SecretRef.addonToken(addonId, id);
      // O que já está no cofre é o mais novo: reinstalar um catálogo velho não
      // pode devolver ao usuário um token que ele já trocou.
      if (await vault.read(chave) != null) return;
      await vault.write(chave, token);
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        // As entradas de descoberta (`list_systems`) não viram console, e ainda
        // assim entram aqui: o arquivo compartilhado é o mesmo e o token lá
        // dentro vaza igual.
        await colher(_nameToId(name), item);
      }
    } else if (decoded is Map) {
      for (final entrada in decoded.entries) {
        final valor = entrada.value;
        if (valor is! Map) continue;
        await colher(entrada.key.toString(), valor);
      }
    } else {
      return jsonStr;
    }

    return jsonEncode(decoded);
  }
```

- [ ] **Step 4: O modelo passa a enxergar a marca**

Em `lib/models/console_model.dart`, linha 58, troque

```dart
    return auth!.containsKey('token') || auth!.containsKey('auth_message');
```

por

```dart
    // `requires_token` é o que a colheita da instalação deixa no lugar do
    // token que tirou (`CatalogService.harvestAuthTokens`). Sem ele, um
    // catálogo privado cujo bloco de auth era só o token ficaria sem nenhuma
    // marca depois de instalado, e este getter passaria a responder "não pede
    // token" para o console que mais pede.
    return auth!['requires_token'] == true || auth!.containsKey('token') || auth!.containsKey('auth_message');
```

O `containsKey('token')` fica. Ele ainda responde por dois casos vivos: o catálogo embutido que nunca passou pela colheita, e o arquivo que o usuário abriu na mão. Trocar em vez de somar quebraria os dois.

Repare que a guarda do `ia_s3`, duas linhas acima, continua saindo antes: um console do Internet Archive com token dentro é colhido igual, e mesmo assim `hasTokenAuth` segue falso para ele, porque a assinatura dele é outra. Esse comportamento não muda.

- [ ] **Step 5: Ligue na instalação**

Ainda em `catalog_service.dart`, as duas portas de instalação passam a exigir o cofre:

```dart
  Future<void> setCatalogFromJson(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final limpo = await harvestAuthTokens(jsonStr, vault: vault, addonId: addonId);
    final consoles = _parseConsoles(limpo);
    if (consoles.isEmpty) {
      throw const FormatException('No consoles found in the provided catalog.');
    }
    final file = await _userConsolesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(limpo);
    _consolesCache.clear();
  }
```

e o `setCatalogFromUrl` repassa:

```dart
  Future<void> setCatalogFromUrl(String url, {required SecretVault vault, required String addonId}) async {
```

com a chamada interna virando `await setCatalogFromJson(body, vault: vault, addonId: addonId);`.

Repare na ordem: **colhe antes de validar**. Se validasse primeiro, um catálogo inválido com token dentro deixaria o token passar batido pelas mãos do app sem ir para lugar nenhum, e o usuário reinstalaria a versão corrigida já sem ele.

- [ ] **Step 6: Ajuste os cinco chamadores**

São cinco, todos em widget com `ref` à mão. Em `lib/screens/setup_wizard_screen.dart:94`, `:101` e `:108`, e em `lib/widgets/settings/catalog_source_setting.dart:74` e `:82`, cada chamada ganha o cofre. O `:101` é o `setCatalogFromUrl` do wizard: o Step 5 troca a assinatura dele, então esse sítio não compila sem o cofre, não é opcional. Uma versão anterior deste texto dizia "quatro" e omitia ele.

```dart
final vault = (await ref.read(vaultProvider.future)).vault;
await _installCatalog(() => _catalogService.setCatalogFromJson(
      File(path).readAsStringSync(),
      vault: vault,
      addonId: SettingsService.builtinAddonId,
    ));
```

Os dois arquivos ganham:

```dart
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/settings_service.dart';
```

O `addonId` é o `builtinAddonId` porque, até a Grupo 3, existe uma fonte só. E **estes dois sítios continuam sendo o embutido depois dela**: instalar catálogo pela tela de Ferramentas é instalar o catálogo do addon embutido, hoje e no fim da fatia. Quem passa um id de addon de verdade para `harvestAuthTokens` é a Task 21, pela instalação por URL, e é aí que dois addons servindo o mesmo console param de dividir token.

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/catalog_auth_token_test.dart
```

Esperado: `+10`, zero falha.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+421`, zero falha. `test/add_catalog_source_screen_test.dart` e `test/catalog_add_console_test.dart` encostam nesse caminho: se quebrarem por causa da assinatura nova, o conserto é passar um `MemoryVault()`, não afrouxar a assinatura.

**Tropeço provável:** um teste antigo de `Console` que afirme igualdade do mapa `auth` inteiro depois de uma instalação passa a ver a chave `requires_token` a mais. Confira com `grep -rn "requires_token\|'auth'" test/ | grep -v catalog_auth_token`. Se aparecer, o conserto é somar a chave na expectativa, não parar de gravá-la: sem ela o console perde a tela de login.

- [ ] **Step 9: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/catalog_auth_token_test.dart
git commit -m "test(seguranca): instalar catalogo colhe o token para o cofre e limpa o arquivo"
git add lib/services/catalog_service.dart lib/models/console_model.dart lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart
git commit -m "feat(seguranca): instalar catalogo colhe o token para o cofre e limpa o arquivo"
```

**Fim da Grupo 2.** A seção 6.3 está cumprida, **com a ressalva que a decisão travada obriga a repetir**: o token saiu do arquivo compartilhável em toda plataforma, e a cifragem em repouso é melhor esforço, que num Linux sem chaveiro não acontece. Quem relatar só a primeira metade está relatando maquiagem.

| Task | Novos | Acumulado |
| --- | --- | --- |
| 6, segredo no cofre | 13 | 402 |
| 7, quatro sítios | 9 | 411 |
| 8, colheita na instalação | 10 | 421 |

---

## Grupo 3: o modelo de addon

Seis Tasks. Aqui o app deixa de ter **um** catálogo e passa a ter **N**, numa lista ordenada que o usuário controla. É a parte grande da fatia, e a ordem das Tasks segue a mesma regra do Grupo 1: primeiro o que é Dart puro (9, 10, 12), depois o que encosta em disco e em `shared_preferences` (11, 13, 14).

O problema central desta grupo não é guardar uma lista. É este: **`Console.auth` é um mapa só, e `_fetchCatalog` passa um `authToken` só para todas as urls do console** (`catalog_service.dart:304-316` e `:344`). Se dois addons declararem o mesmo console, fundir os dois num `Console` faz as urls do segundo serem buscadas com o token do primeiro, e o usuário vê "HTTP 401" numa fonte que ele configurou certo. Por isso a fusão não devolve só `Map<String, Console>`: devolve também, por console, a lista de `ConsoleSource`, que é onde a auth passa a morar.

Uma decisão de escopo que economiza muito churn: **o arquivo de catálogo do addon embutido continua sendo `config/consoles.json`**. Só os addons novos ganham arquivo em `config/addons/<id>.json`. Com isso `setCatalogFromJson`, `addConsole`, `resetCatalog` e `hasUserCatalog` (`catalog_service.dart:170`, `:229`, `:249`, `:255`) seguem apontando para o mesmo arquivo de sempre, e a migração da Task 11 não move byte nenhum de disco: ela só escreve uma lista de um item no `shared_preferences`. Migração que não mexe em arquivo é migração que não tem como perder o catálogo do usuário.

### Task 8b: a hidratação para de inventar configuração

**Files:**
- Modify: `lib/models/settings_model.dart:129-146`
- Modify: `lib/services/settings_service.dart:63`
- Modify: `test/settings_service_test.dart:68-77` (só o comentário)
- Test: `test/settings_hydrate_test.dart`

Esta Task não estava no plano. Ela existe porque a revisão de qualidade da Task 6 achou, por mutação, um defeito de comportamento que a Task 6 introduziu e que nenhum teste pegava.

**O defeito.** `BaseSettings.copyWith` (`settings_model.dart:140-142`) não é um `copyWith` inocente:

```dart
      autoExtract: autoExtract ?? this.autoExtract ?? true,
      maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads ?? 5,
      maxParallelExtractions: maxParallelExtractions ?? this.maxParallelExtractions ?? 2,
```

Ele **materializa padrão em campo que estava `null`**. A Task 6 pôs uma chamada dele em `_hydrate` (`settings_service.dart:63`), que roda a cada abertura do app, para todo console que tenha token no cofre. Resultado: o console ganha override explícito de `autoExtract: true`, `maxParallelDownloads: 5` e `maxParallelExtractions: 2` que o usuário nunca pediu, e isso vai para o disco no salvamento seguinte, virando permanente.

**Por que não é cosmético.** `autoExtract` muda comportamento. `download_provider.dart:230` chama `getAutoExtract(game.consoleId)`, e `getSetting` (`settings_service.dart`) consulta o console **antes** do geral. Então o usuário desliga a extração automática no geral, e o único efeito de ter login num console é que aquele console volta a extrair sozinho, em silêncio, a cada abertura.

**O que é novo e o que não é, com precisão.** O mecanismo é antigo: `setConsoleAuthToken` já fazia `copyWith(authToken: token)` antes da Task 6, conferido em `git show 058cef5~1:lib/providers/settings_provider.dart`. Mas ali ele dispara **por ação do usuário**, uma vez, na tela em que ele está mexendo em configuração. O que a Task 6 acrescentou é o disparo **a cada carga**. E a Task 8 piora: com a colheita, o token chega ao cofre sem o usuário jamais ter aberto a tela de login, então a hidratação passa a inventar configuração para console que o usuário nunca tocou. Não mexa no `copyWith` para consertar isso: o caminho do formulário quer o padrão materializado. Quem está errado é o chamador novo.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/settings_hydrate_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Arquivo de quem configurou o geral e **não** configurou o console.
///
/// `autoExtract: false` no geral é o que torna o defeito visível: se a
/// hidratação inventar `autoExtract: true` no console, o console passa a
/// ganhar do geral, porque `getSetting` consulta o console primeiro.
String _arquivo() => jsonEncode({
      'consoleSettings': {
        'snes': {'downloadDir': '/roms/snes'},
      },
      'generalSettings': {'downloadDir': '/casa/roms', 'autoExtract': false, 'maxParallelDownloads': 10},
    });

Future<void> _prefsCom(String appSettings) async {
  SharedPreferences.setMockInitialValues({'app_settings': appSettings});
  SharedPreferences.resetStatic();
}

Future<SecretVault> _cofreComTokenDoSnes() async {
  final vault = MemoryVault();
  await vault.write(SecretRef.addonToken(SettingsService.builtinAddonId, 'snes'), 'tok-snes');
  return vault;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o console com token no cofre não ganha `autoExtract` que ninguém pediu', () async {
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.autoExtract, isNull);
    expect(SettingsService().getSetting<bool>(settings, AppSettings.autoExtract, 'snes'), isFalse);
  });

  test('o console com token no cofre não ganha os dois limites de paralelismo', () async {
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.maxParallelDownloads, isNull);
    expect(settings.consoleSettings['snes']?.maxParallelExtractions, isNull);
    expect(SettingsService().getSetting<int>(settings, AppSettings.maxParallelDownloads, 'snes'), 10);
  });

  test('a hidratação continua entregando o token e o que o usuário configurou', () async {
    // O controle. Sem ele, apagar a hidratação inteira faria os dois casos de
    // cima passarem, e eles são asserções sobre ausência.
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('salvar com segredo vazio não apaga o que está no cofre', () async {
    // A guarda `valor.isEmpty` de `_writeIfPresent`. Sem ela, `vault.write`
    // com string vazia vira `delete` (`secret_vault.dart:38-41`), e um
    // salvamento comum apagaria a credencial.
    await _prefsCom(_arquivo());
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');

    await SettingsService().saveSettings(const AppSettings(iaAccessKey: ''), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/settings_hydrate_test.dart
```

Esperado: os dois primeiros casos falham com `Expected: null, Actual: <true>` e `Expected: null, Actual: <5>`. O terceiro e o quarto já passam: eles trancam o que já está certo, para que o conserto não os quebre.

- [ ] **Step 3: Dê ao `BaseSettings` uma cópia que não inventa nada**

Em `lib/models/settings_model.dart`, logo depois do `copyWith`, acrescente:

```dart
  /// Devolve uma cópia com o token trocado e **nada mais**.
  ///
  /// Existe porque [copyWith] materializa padrão em campo `null`
  /// (`autoExtract ?? this.autoExtract ?? true`, e os dois limites logo
  /// abaixo). No formulário isso é o desejado: o usuário está mexendo em
  /// configuração e ver o valor efetivo é útil. Na hidratação do cofre não é:
  /// ela roda a cada abertura do app, e depois da Task 8 roda também para
  /// console que o usuário nunca abriu, então gravaria override que ninguém
  /// pediu. `autoExtract` chega a mudar comportamento, porque `getSetting`
  /// consulta o console antes do geral (`download_provider.dart:230`).
  BaseSettings withAuthToken(String token) => BaseSettings(
        downloadDir: downloadDir,
        autoExtract: autoExtract,
        maxParallelDownloads: maxParallelDownloads,
        maxParallelExtractions: maxParallelExtractions,
        extractToFolder: extractToFolder,
        authToken: token,
      );
```

- [ ] **Step 4: Troque o chamador**

Em `lib/services/settings_service.dart`, linha 63, troque

```dart
      consoles[entrada.key] = token == null ? entrada.value : entrada.value.copyWith(authToken: token);
```

por

```dart
      consoles[entrada.key] = token == null ? entrada.value : entrada.value.withAuthToken(token);
```

- [ ] **Step 5: Conserte o comentário que promete demais**

Em `test/settings_service_test.dart`, o caso "carregar não reescreve o app_settings quando não havia segredo" (linhas 68-77) compara **conteúdo**, e quando não há segredo `jsonEncode(limpo)` é idêntico a `jsonEncode(cru)`. Ou seja: ele não distingue "não escreveu" de "escreveu igual", e tirar o `if` de `settings_service.dart:38` o deixa verde. Medido por mutação. Troque o comentário dele por:

```dart
    // A carga roda em toda abertura. Reescrever sempre é escrita em disco por
    // nada. ATENÇÃO ao que este caso tranca e ao que não tranca: ele compara o
    // conteúdo, e quando não há segredo o JSON limpo é idêntico ao cru, então
    // ele fica verde tanto para "não reescreveu" quanto para "reescreveu igual".
    // Medido por mutação: tirar o `if` de `settings_service.dart:38` não o
    // derruba. Trancar o ato de escrever exigiria injetar o `SharedPreferences`
    // no `SettingsService`, que hoje o chama direto; está anotado para a fatia 5.
```

- [ ] **Step 6: Rode para ver passar**

```bash
flutter test test/settings_hydrate_test.dart test/settings_service_test.dart
```

Esperado: `+13`, zero falha. São os 4 deste arquivo mais os 9 que `test/settings_service_test.dart` já tem. Este número já esteve escrito como `+17`, somando os 13 da Task 6 inteira; errado, porque 4 daqueles 13 estão em `test/settings_model_secrets_test.dart` (`git show --stat e7829f4`), que este comando não roda. Corrigido depois de medir `+13: All tests passed!`.

- [ ] **Step 7: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+425`, zero falha.

- [ ] **Step 8: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 9: Commit**

```bash
git add test/settings_hydrate_test.dart test/settings_service_test.dart
git commit -m "test(cofre): hidratar o token nao pode inventar configuracao de console"
git add lib/models/settings_model.dart lib/services/settings_service.dart
git commit -m "feat(cofre): hidratar o token nao pode inventar configuracao de console"
```

---

### Task 9: `Addon`, o modelo e a lista ordenada

**Files:**
- Create: `lib/models/addon_model.dart`
- Modify: `lib/services/settings_service.dart` (perde a constante duplicada), `lib/screens/setup_wizard_screen.dart`, `lib/widgets/settings/catalog_source_setting.dart`
- Test: `test/addon_model_test.dart`, e ajuste em `test/settings_service_test.dart` e `test/settings_hydrate_test.dart`

O addon é deliberadamente magro: id, nome e a url de origem. Nada de "habilitado", porque a seção 9 do spec de UI não especifica interruptor nenhum (`docs/stremio-de-jogos-ui.md:220-263` lista ícone, nome, cobertura, chip de conta, alça de arrasto e seta, e mais nada), e nada de data de instalação, porque não há tela que a mostre e ela só serviria para atrapalhar teste.

O ponto delicado é o **id**. Ele é a chave sob a qual o token do addon foi guardado no cofre, em `SecretRef.addonToken(addonId, consoleId)` (Task 1). Um id que muda entre duas instalações da mesma fonte deixa o token órfão no cofre e faz o usuário digitar de novo um segredo que ele já tinha dado. Por isso `Addon.idFromUrl` normaliza esquema, `www.`, caixa, query, fragmento e barra final.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/addon_model_test.dart`:

```dart
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
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/addon_model_test.dart
```

Esperado: falha de compilação, `Target of URI doesn't exist: 'package:roms_downloader/models/addon_model.dart'`.

- [ ] **Step 3: Escreva a implementação**

Crie `lib/models/addon_model.dart`:

```dart
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
  static String idFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final cru = (uri == null || uri.host.isEmpty) ? url : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.path}';
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
```

**Tropeço provável:** o `-1` do `ReorderableListView`. É fácil escrever `saida.insert(to, item)` e ver os testes de "subindo" passarem, porque subindo o desconto não existe. Só o caso de descer pega, e é o caso que o usuário faz primeiro, porque a fonte nova nasce no fim da lista e ele quer promovê-la. O teste "descendo aplica o desconto" existe para isso e não deve ser afrouxado.

- [ ] **Step 4: Tire a constante duplicada que a Task 6 criou**

A Task 6 precisou de `'builtin'` antes de esta Task existir e o pôs em `SettingsService.builtinAddonId`. Agora há dois nomes para o mesmo valor, e dois nomes para o mesmo valor é um bug esperando alguém mudar um só. O canônico é o `kBuiltinAddonId` deste arquivo, porque ele mora com o conceito.

Em `lib/services/settings_service.dart`, apague a constante **com o doc dela**, que são oito linhas:

```dart
  /// O addon a que pertencem os consoles do catálogo de hoje.
  ///
  /// Enquanto existe uma fonte só, este id é constante. Quando houver N
  /// addons, este espelho continua sendo só do embutido, e o token dos outros
  /// passa a ser lido sob demanda no cofre (Task 19). Ele vive aqui, e não em
  /// [SecretRef], porque é fato sobre a instalação e não sobre o formato da
  /// chave.
  static const String builtinAddonId = 'builtin';
```

Apagar só a linha da constante deixa o doc pendurado no membro seguinte, e um doc que descreve outra coisa é pior que doc nenhum.

acrescente ao topo

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

e troque os quatro usos internos de `builtinAddonId` por `kBuiltinAddonId`, nas linhas 31, 62, 97 e 113. São quatro usos, e não cinco: o `grep` devolve cinco linhas neste arquivo, mas a primeira é a declaração que você acabou de apagar. Na linha 31 repare que `builtinAddonId: builtinAddonId` tem o nome duas vezes, e só o segundo é uso: o primeiro é o rótulo do parâmetro de `SecretMigration` e não muda. Confira com:

```bash
grep -rn "builtinAddonId" lib/ test/
```

Devem sobrar só ocorrências de `kBuiltinAddonId`, mais o parâmetro `builtinAddonId` de `SecretMigration` (`lib/services/secret_migration.dart`), que é nome de parâmetro e não de constante, e continua entrando por injeção.

Os outros quatro arquivos que citam a constante trocam junto. **Esta lista foi remedida depois que a Task 8b entrou**, e mudou: `test/catalog_auth_token_test.dart` estava aqui por engano e saiu, porque ele passa `addonId: 'ultranx'` como literal e nunca citou a constante; `test/settings_hydrate_test.dart`, que a Task 8b criou depois de este texto ser escrito, entrou, porque cita na linha 29. Confira você mesmo com o `grep` acima antes de editar, em vez de confiar na tabela: a Task 8b é recente e outra Task pode ter mexido de novo.

| Arquivo | Ocorrências medidas | Troca |
| --- | --- | --- |
| `lib/screens/setup_wizard_screen.dart` | 3 | `SettingsService.builtinAddonId` vira `kBuiltinAddonId` |
| `lib/widgets/settings/catalog_source_setting.dart` | 2 | idem |
| `test/settings_service_test.dart` | 3 | idem |
| `test/settings_hydrate_test.dart` | 1 | idem |

**Nos dois arquivos de teste o import de `settings_service.dart` fica; nos dois de `lib/` ele sai.** Os dois de teste instanciam `SettingsService()` para valer (`settings_service_test.dart:39` e outras nove, `settings_hydrate_test.dart:39, 48, 60, 74`), então lá o import de `addon_model.dart` **se soma** ao que já está. Nos dois de `lib/` não: `SettingsService` aparece neles **só** como `SettingsService.builtinAddonId`, três vezes no wizard e duas no widget, e mais nada. Depois da troca o import fica morto e o `flutter analyze` sobe de 22 para 24, com dois `unused_import`, que são warning. Confira em vez de confiar nesta frase: depois da troca, `grep -n "SettingsService" lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart` tem que devolver zero. Duas versões deste texto erraram aqui, em direções opostas: a primeira mandava trocar o import nos arquivos de teste, o que deixaria os quatro sem compilar; a segunda dizia que em nenhum dos quatro o import saía e afirmava que isso tinha sido medido, quando só os dois de teste tinham sido medidos e os dois de `lib/` foram supostos. Medido nos quatro pelo implementador da Task 9, e conferido contra `git show 824434e:` depois.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_model_test.dart
```

Esperado: `+15`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+440`, zero falha. Se `test/settings_service_test.dart` ou `test/settings_hydrate_test.dart` ficarem vermelhos, é o Step 4 pela metade: a troca de constante tem que ser feita nos cinco arquivos, não só nos de `lib/`.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, nenhum em `lib/models/addon_model.dart` nem em `test/addon_model_test.dart`. Um `unused_import` aqui quer dizer que sobrou o import de `settings_service.dart` num dos dois arquivos de `lib/` que só o usavam pela constante, e não num arquivo de teste: os de teste continuam precisando dele.

- [ ] **Step 8: Commit**

```bash
git add test/addon_model_test.dart test/settings_service_test.dart test/settings_hydrate_test.dart
git commit -m "test(addon): modelo de addon, id estavel por url e as operacoes da lista ordenada"
git add lib/models/addon_model.dart lib/services/settings_service.dart lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart
git commit -m "feat(addon): modelo de addon, id estavel por url e as operacoes da lista ordenada"
```

### Task 10: `console_merge.dart`, fundir N catálogos sem perder a auth

**Files:**
- Create: `lib/services/console_merge.dart`
- Modify: `lib/models/console_model.dart` (ganha `withUrls`)
- Test: `test/console_merge_test.dart`

Esta é a Task que resolve o problema central da grupo. A fusão devolve duas coisas: o `Map<String, Console>` que todo o app já consome, e um `Map<String, List<ConsoleSource>>` que diz, por console, de qual addon e com que auth cada url veio.

O invariante que amarra os dois, e que a Task 13 usa sem conferir em tempo de execução: **para todo id, `sources[id]!.map((s) => s.url)` é igual a `consoles[id]!.urls`, na mesma ordem.** Um teste fixa isso.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/console_merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {String? regex, Map<String, dynamic>? auth, String? name}) =>
    Console(id: id, name: name ?? id, urls: urls, regex: regex, auth: auth);

void main() {
  test('lista vazia dá catálogo vazio', () {
    final merged = mergeCatalogs(const []);
    expect(merged.consoles, isEmpty);
    expect(merged.sources, isEmpty);
    expect(merged.isEmpty, isTrue);
  });

  test('um addon só: os consoles saem iguais e cada fonte carrega o id do addon', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
    expect(merged.sources['snes']!.single.addonId, 'um');
    expect(merged.sources['snes']!.single.url, 'https://a/');
  });

  test('console que só o segundo addon declara entra do mesmo jeito', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
      (addonId: 'dois', consoles: {'nes': _console('nes', ['https://b/'])}),
    ]);
    expect(merged.consoles.keys, containsAll(['snes', 'nes']));
    expect(merged.sources['nes']!.single.addonId, 'dois');
  });

  test('mesmo console nos dois: os metadados são do PRIMEIRO addon', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'], name: 'Super Nintendo', regex: 'DO UM')}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'], name: 'SNES', regex: 'DO DOIS')}),
    ]);
    expect(merged.consoles['snes']!.name, 'Super Nintendo');
    expect(merged.consoles['snes']!.regex, 'DO UM');
  });

  test('mesmo console nos dois: as urls concatenam na ordem dos addons', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/', 'https://a2/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/', 'https://a2/', 'https://b/']);
  });

  test('url repetida entre dois addons entra uma vez só, do primeiro', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://mesma/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://mesma/', 'https://outra/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://mesma/', 'https://outra/']);
    expect(merged.sources['snes']!.map((f) => f.addonId), ['um', 'dois']);
  });

  test('url repetida dentro do mesmo addon entra uma vez só', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/', 'https://a/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
  });

  test('a auth de cada fonte é a do addon que declarou AQUELA url', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'], auth: {'token': 'nao usado', 'cookies': true})}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'], auth: {'type': 'ia_s3'})}),
    ]);
    final fontes = merged.sources['snes']!;
    expect(fontes[0].auth!['cookies'], true);
    expect(fontes[1].auth!['type'], 'ia_s3');
  });

  test('o invariante: as urls do console são as urls das fontes, na mesma ordem', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/']), 'nes': _console('nes', ['https://n1/', 'https://n2/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    for (final id in merged.consoles.keys) {
      expect(merged.sources[id]!.map((f) => f.url).toList(), merged.consoles[id]!.urls, reason: 'console $id');
    }
  });

  test('console sem url nenhuma entra com lista de fontes vazia', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', const [])}),
    ]);
    expect(merged.consoles.containsKey('snes'), isTrue);
    expect(merged.sources['snes'], isEmpty);
  });

  test('addon sem console nenhum não atrapalha os outros', () {
    final merged = mergeCatalogs([
      (addonId: 'vazio', consoles: const {}),
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.sources['snes']!.single.addonId, 'um');
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/console_merge_test.dart
```

Esperado: falha de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/console_merge.dart'`.

- [ ] **Step 3: Dê ao `Console` a cópia com outras urls**

Em `lib/models/console_model.dart`, logo depois do getter `url` (linha 51), acrescente:

```dart
  /// Uma cópia com outra lista de urls, e mais nada diferente.
  ///
  /// Existe só para `mergeCatalogs` (`console_merge.dart`), que acrescenta as
  /// urls de outro addon ao console sem tocar em mais nenhum campo. É um
  /// `copyWith` de um campo só de propósito: um `copyWith` completo de vinte e
  /// um campos seria vinte parâmetros que ninguém passa e um lugar a mais para
  /// esquecer de atualizar quando o `Console` crescer.
  Console withUrls(List<String> novas) => Console(
        id: id,
        name: name,
        urls: novas,
        regex: regex,
        boxarts: boxarts,
        fileFormat: fileFormat,
        romsFolder: romsFolder,
        shouldUnzip: shouldUnzip,
        extractContents: extractContents,
        shouldFilterUsa: shouldFilterUsa,
        usaRegex: usaRegex,
        shouldDecompressNsz: shouldDecompressNsz,
        ignoreExtensionFiltering: ignoreExtensionFiltering,
        downloadUrl: downloadUrl,
        auth: auth,
        listUrl: listUrl,
        listJsonFileLocation: listJsonFileLocation,
        listItemId: listItemId,
        listSystems: listSystems,
        added: added,
        convert3dsToCia: convert3dsToCia,
      );
```

- [ ] **Step 4: Escreva a fusão**

Crie `lib/services/console_merge.dart`:

```dart
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
}

/// O catálogo de um addon, já parseado.
typedef AddonCatalog = ({String addonId, Map<String, Console> consoles});

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
```

**Tropeço provável:** deduplicar url com um `Set` global em vez de um por console. Duas urls iguais em consoles diferentes são legítimas (um servidor que lista tudo no mesmo diretório), e um `Set` global comeria a segunda em silêncio. O `jaTem` é recalculado dentro do laço de cada console, a partir das fontes daquele console, e é por isso.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/console_merge_test.dart
```

Esperado: `+11`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+451`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/console_merge_test.dart
git commit -m "test(addon): fusao de N catalogos preservando a auth por url"
git add lib/services/console_merge.dart lib/models/console_model.dart
git commit -m "feat(addon): fusao de N catalogos preservando a auth por url"
```

### Task 11: `AddonStore`, onde a lista e os catálogos moram

**Files:**
- Create: `lib/services/addon_store.dart`
- Modify: `lib/services/settings_service.dart` (`_settingsKey` vira `settingsKey`)
- Test: `test/addon_store_test.dart`

Duas coisas a persistir: a **lista ordenada**, que vai para uma chave nova do `shared_preferences`, e o **catálogo de cada addon**, que vai para disco.

A raiz de disco entra por construtor. Isso não é gosto por injeção: `getApplicationSupportDirectory()` é `path_provider`, que num teste sem plataforma lança `MissingPluginException`. Com a raiz injetada, os testes usam `Directory.systemTemp.createTemp()` e exercitam IO de verdade, que é o que importa aqui, em vez de simular disco.

E a decisão de escopo que o intro da grupo já anunciou: **o embutido continua em `config/consoles.json`**. `catalogFile` é a única função que sabe disso, e é por isso que ela existe em vez de uma concatenação de caminho espalhada.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/addon_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store([Map<String, Object> valores = const {}]) async {
  SharedPreferences.setMockInitialValues(valores);
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_store_test');
  addTearDown(() => raiz.delete(recursive: true));
  return AddonStore(await SharedPreferences.getInstance(), raiz);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migração', () {
    test('sem a chave, a lista é só o embutido', () async {
      final store = await _store();
      final lista = store.load();
      expect(lista.map((a) => a.id), [kBuiltinAddonId]);
      expect(lista.single.name, isNotEmpty);
    });

    test('ler NÃO grava: a chave continua ausente depois do load', () async {
      final store = await _store();
      store.load();
      expect((await SharedPreferences.getInstance()).getString(AddonStore.prefsKey), isNull);
    });

    test('o embutido herda a url que o usuário tinha salvo em catalogSourceUrl', () async {
      final store = await _store({
        'app_settings': jsonEncode({'catalogSourceUrl': 'https://exemplo.com/catalogo.json'}),
      });
      expect(store.load().single.url, 'https://exemplo.com/catalogo.json');
    });

    test('app_settings ilegível não derruba a migração', () async {
      final store = await _store({'app_settings': 'isto não é json'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
      expect(store.load().single.url, isNull);
    });

    test('app_settings sem catalogSourceUrl dá embutido sem url', () async {
      final store = await _store({'app_settings': jsonEncode({'downloadDir': '/tmp'})});
      expect(store.load().single.url, isNull);
    });

    test('lista corrompida cai na migração em vez de lançar', () async {
      final store = await _store({AddonStore.prefsKey: '{não é uma lista}'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
    });

    test('item sem id é ignorado, e o resto da lista entra', () async {
      final store = await _store({
        AddonStore.prefsKey: jsonEncode([
          {'nome': 'sem id'},
          {'id': 'ultranx', 'name': 'UltraNX'},
        ]),
      });
      expect(store.load().map((a) => a.id), ['ultranx']);
    });
  });

  group('lista', () {
    test('save e load fecham o ciclo preservando a ordem', () async {
      final store = await _store();
      await store.save(const [
        Addon(id: 'b', name: 'B'),
        Addon(id: kBuiltinAddonId, name: 'Embutido'),
        Addon(id: 'a', name: 'A', url: 'https://a/'),
      ]);
      final volta = store.load();
      expect(volta.map((x) => x.id), ['b', kBuiltinAddonId, 'a']);
      expect(volta.last.url, 'https://a/');
    });

    test('salvar lista vazia é legítimo e não volta para a migração', () async {
      final store = await _store();
      await store.save(const []);
      expect(store.load(), isEmpty);
    });
  });

  group('catálogo em disco', () {
    test('o embutido mora no consoles.json de sempre', () async {
      final store = await _store();
      expect(store.catalogFile(kBuiltinAddonId).path, endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}consoles.json'));
    });

    test('addon instalado mora em config/addons/<id>.json', () async {
      final store = await _store();
      expect(store.catalogFile('ultranx').path,
          endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}addons${Platform.pathSeparator}ultranx.json'));
    });

    test('writeCatalog cria o diretório e readCatalog lê de volta', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[{"name":"SNES"}]');
      expect(await store.readCatalog('ultranx'), '[{"name":"SNES"}]');
    });

    test('readCatalog de addon sem arquivo devolve null', () async {
      final store = await _store();
      expect(await store.readCatalog('ultranx'), isNull);
    });

    test('deleteCatalog apaga, e apagar o que não existe não lança', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[]');
      await store.deleteCatalog('ultranx');
      expect(await store.readCatalog('ultranx'), isNull);
      await store.deleteCatalog('ultranx');
    });
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/addon_store_test.dart
```

Esperado: falha de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/addon_store.dart'`.

- [ ] **Step 3: Abra a chave das settings**

Em `lib/services/settings_service.dart`, troque

```dart
  static const String _settingsKey = 'app_settings';
```

por

```dart
  /// A chave única onde o app guarda as settings. Pública porque a migração de
  /// addons (`addon_store.dart`) precisa ler o `catalogSourceUrl` de antes da
  /// fatia 4, e uma string literal repetida nos dois arquivos seria pior.
  static const String settingsKey = 'app_settings';
```

e troque os três usos internos de `_settingsKey` por `settingsKey`. Confira:

```bash
grep -rn "_settingsKey" lib/
```

Esperado: nada.

- [ ] **Step 4: Escreva o store**

Crie `lib/services/addon_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Onde a lista de addons e os catálogos de cada um moram.
///
/// A raiz de disco entra por construtor porque `getApplicationSupportDirectory`
/// é `path_provider`, que num teste sem plataforma lança
/// `MissingPluginException`. Com ela injetada, o teste usa
/// `Directory.systemTemp.createTemp()` e exercita IO de verdade.
class AddonStore {
  /// A chave do `shared_preferences` onde a lista ordenada é serializada.
  static const String prefsKey = 'addons';

  final SharedPreferences _prefs;
  final Directory _root;

  AddonStore(this._prefs, this._root);

  static Future<AddonStore> open() async => AddonStore(
        await SharedPreferences.getInstance(),
        await getApplicationSupportDirectory(),
      );

  /// A lista instalada, na ordem de prioridade.
  ///
  /// Quando a chave não existe, devolve a lista de migração (o embutido
  /// sozinho) **sem gravar nada**. Gravar aqui faria uma leitura ter efeito
  /// colateral, e o teste "ler NÃO grava" existe para prender isso: quem
  /// persiste é a primeira instalação, remoção ou arrasto.
  ///
  /// Lista vazia salva é estado legítimo, e diferente de chave ausente: o
  /// usuário que removeu todos os addons não pode ver o embutido voltar
  /// sozinho no próximo boot.
  List<Addon> load() {
    final cru = _prefs.getString(prefsKey);
    if (cru == null) return [_builtinMigrado()];
    try {
      final decoded = jsonDecode(cru);
      if (decoded is! List) return [_builtinMigrado()];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> && item['id'] is String) Addon.fromJson(item),
      ];
    } catch (e) {
      debugPrint('Lista de addons ilegível, caindo na migração: $e');
      return [_builtinMigrado()];
    }
  }

  Future<void> save(List<Addon> lista) async {
    await _prefs.setString(prefsKey, jsonEncode([for (final addon in lista) addon.toJson()]));
  }

  /// O addon que representa o `consoles.json` de antes da fatia 4.
  ///
  /// A url sai do `catalogSourceUrl` que o usuário já tinha salvo, quando ele
  /// instalou o catálogo por endereço. É só nome de tela: `app_settings`
  /// ilegível ou campo ausente dão um addon sem url, e o app funciona igual.
  Addon _builtinMigrado() {
    String? url;
    try {
      final cru = _prefs.getString(SettingsService.settingsKey);
      if (cru != null) {
        final decoded = jsonDecode(cru);
        final valor = decoded is Map ? decoded['catalogSourceUrl'] : null;
        if (valor is String && valor.isNotEmpty) url = valor;
      }
    } catch (e) {
      debugPrint('catalogSourceUrl ilegível na migração de addons: $e');
    }
    return Addon(id: kBuiltinAddonId, name: 'Catálogo embutido', url: url);
  }

  /// Onde mora o catálogo de cada addon.
  ///
  /// O embutido continua em `config/consoles.json`, que é exatamente onde
  /// `CatalogService.setCatalogFromJson`, `addConsole` e `resetCatalog` já
  /// escrevem (`catalog_service.dart:104-107`). É por isso que a migração não
  /// move byte nenhum de disco: ela só escreve uma lista no
  /// `shared_preferences`, e migração que não mexe em arquivo não tem como
  /// perder o catálogo do usuário.
  File catalogFile(String addonId) => addonId == kBuiltinAddonId
      ? File(path.join(_root.path, 'config', 'consoles.json'))
      : File(path.join(_root.path, 'config', 'addons', '$addonId.json'));

  Future<String?> readCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeCatalog(String addonId, String jsonStr) async {
    final file = catalogFile(addonId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> deleteCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (await file.exists()) await file.delete();
  }
}
```

**Tropeço provável:** tratar chave ausente e lista vazia como a mesma coisa. Se `load()` devolvesse o embutido sempre que a lista saísse vazia, o usuário que removeu todos os addons de propósito veria o embutido ressuscitar no próximo boot, e não teria como impedir. O teste "salvar lista vazia é legítimo" prende exatamente essa diferença, e ele passa de graça na implementação errada só se você testar pela chave e não pelo tamanho.

**Segundo tropeço:** `deleteCatalog(kBuiltinAddonId)` apaga o `config/consoles.json`, que é o mesmo arquivo que `resetCatalog` apaga. É o comportamento certo (remover o addon embutido é remover o catálogo dele), mas quem chamar sem querer perde o catálogo importado do usuário. A Task 14 só chama `deleteCatalog` no caminho de remoção explícita.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_store_test.dart
```

Esperado: `+14`, zero falha. São 7 casos de migração, 2 de lista e 5 de disco. Este número já esteve escrito como `+13`, e estava errado: contei os `test(` do bloco do Step 1 e são 14.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+465`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_store_test.dart
git commit -m "test(addon): persistencia da lista de addons e do catalogo de cada um"
git add lib/services/addon_store.dart lib/services/settings_service.dart
git commit -m "feat(addon): persistencia da lista de addons e do catalogo de cada um"
```

### Task 12: `Game.sourceId`, o jogo sabe de qual addon veio

**Files:**
- Modify: `lib/models/game_model.dart`
- Test: `test/game_source_id_test.dart`

O `Game` de hoje não sabe de onde veio (`game_model.dart:4-19`: título, url, tamanho, console, metadados, detalhes). Com um addon só isso nunca fez falta. Com N, é o campo que faz a prioridade arrastável significar alguma coisa: sem ele, `planFromEntries` recebe um `sourcePriority` que não casa com fonte nenhuma e o critério de desempate vira decoração.

Dois detalhes que decidem a forma do campo:

**Ele é não-nulável, com valor padrão.** O `Game` vai e volta de disco: `_fetchCatalog` escreve `jsonEncode(catalog.map((g) => g.toJson()))` no arquivo de cache (`catalog_service.dart:327`) e `loadCatalog` lê de lá (`:271-273`). Todo cache escrito antes desta fatia existe e não tem o campo. Se o campo fosse nulável, cada consumidor teria que lembrar do `?? algo`, e o primeiro que esquecesse produziria um jogo sem fonte no meio da grade. Não-nulável com padrão resolve a degradação **num lugar só**, dentro do `fromJson`.

**O padrão é `kBuiltinAddonId` e não `kBuiltinSourceId`.** O `sourceId` agora é id de addon, e ele é comparado contra a lista de ids que o usuário arrastou. Um jogo marcado `'listagem'` nunca casaria com nenhum addon da lista. O `kBuiltinSourceId` da fatia 3 era explicitamente provisório (`source_pick_model.dart:4-17`: "Na fatia 4 ele vira o id do addon que serviu o arquivo") e a Task 15 o remove.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/game_source_id_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';

void main() {
  const jogo = Game(title: 'Chrono Trigger (USA).zip', url: 'https://a/ct.zip', size: 1024, consoleId: 'snes');

  test('sem fonte declarada, o jogo é do addon embutido', () {
    expect(jogo.sourceId, kBuiltinAddonId);
  });

  test('o sourceId sobrevive à ida e volta pelo json do cache', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    final volta = Game.fromJson(jsonDecode(jsonEncode(marcado.toJson())) as Map<String, dynamic>);
    expect(volta.sourceId, 'ultranx');
    expect(volta.title, jogo.title);
    expect(volta.url, jogo.url);
    expect(volta.consoleId, jogo.consoleId);
  });

  test('toJson emite o campo', () {
    expect(jogo.copyWith(sourceId: 'ultranx').toJson()['sourceId'], 'ultranx');
  });

  test('cache antigo, escrito sem o campo, degrada para o embutido', () {
    final antigo = {'title': 'a.zip', 'url': 'https://a/a.zip', 'size': 1, 'consoleId': 'snes'};
    expect(Game.fromJson(antigo).sourceId, kBuiltinAddonId);
  });

  test('copyWith troca a fonte sem mexer no resto', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    expect(marcado.sourceId, 'ultranx');
    expect(marcado.title, jogo.title);
    expect(marcado.size, jogo.size);
  });

  test('copyWith sem sourceId preserva a fonte que já estava', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    expect(marcado.copyWith(size: 2048).sourceId, 'ultranx');
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/game_source_id_test.dart
```

Esperado: falha de compilação, `No named parameter with the name 'sourceId'`.

- [ ] **Step 3: Escreva a implementação**

Em `lib/models/game_model.dart`, acrescente o import

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

o campo, depois de `consoleId` (linha 8):

```dart
  /// O id do addon que serviu este arquivo.
  ///
  /// Não-nulável de propósito. O `Game` vai e volta de disco pelo cache de
  /// catálogo (`catalog_service.dart:327` escreve, `:271` lê), e todo cache
  /// escrito antes da fatia 4 não tem o campo. Com padrão, a degradação
  /// acontece uma vez, no `fromJson`; com `null`, ela viraria um `??` em cada
  /// consumidor e o primeiro esquecido põe um jogo sem fonte na grade.
  final String sourceId;
```

o parâmetro, no construtor:

```dart
    this.sourceId = kBuiltinAddonId,
```

o parâmetro e o repasse no `copyWith`:

```dart
    String? sourceId,
```
```dart
      sourceId: sourceId ?? this.sourceId,
```

a leitura no `fromJson`:

```dart
      sourceId: json['sourceId'] as String? ?? kBuiltinAddonId,
```

e a escrita no `toJson`:

```dart
      'sourceId': sourceId,
```

**Tropeço provável:** ler `json['sourceId']` sem o `as String?`. O mapa vem de `jsonDecode` e é `Map<String, dynamic>`, então um `json['sourceId'] ?? kBuiltinAddonId` compila e entrega `dynamic` para um campo `String`, o que só explode em tempo de execução, e só com um cache que tenha o campo com outro tipo. Os outros campos do `fromJson` sofrem do mesmo (`title: json['title']`, linha 41), mas isso é dívida anterior e não é desta fatia consertar.

- [ ] **Step 4: Rode para ver passar**

```bash
flutter test test/game_source_id_test.dart
```

Esperado: `+6`, zero falha.

- [ ] **Step 5: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+471`, zero falha. Nenhum teste existente deve mudar: o campo tem padrão, e o padrão é o comportamento de antes.

- [ ] **Step 6: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/game_source_id_test.dart
git commit -m "test(addon): o Game carrega o id do addon que o serviu"
git add lib/models/game_model.dart
git commit -m "feat(addon): o Game carrega o id do addon que o serviu"
```

### Task 13: o `CatalogService` lê N addons e busca cada fonte com a auth dela

**Files:**
- Modify: `lib/services/catalog_service.dart`, `lib/providers/catalog_provider.dart`
- Modify: `lib/providers/tinfoil_server_provider.dart:69` e `lib/providers/fbi_server_provider.dart:95` (os dois passam o parâmetro que esta Task apaga)
- Test: `test/catalog_addons_test.dart`

Esta é a Task que liga tudo o que veio antes. Duas metades:

**Metade de leitura.** `getConsoles` para de ler um arquivo e passa a ler a lista de addons, fundindo os catálogos com `mergeCatalogs`. O cache estático deixa de ser um mapa por caminho de arquivo e vira um `MergedCatalog` só.

**Metade de busca.** `_fetchCatalog` para de iterar `console.urls` e passa a iterar `sources`, mandando para cada url a auth do addon que a declarou e o token daquele addon. Cada jogo que volta é marcado com o `sourceId` da fonte.

Dois seams de teste, porque o caminho inteiro passa por `path_provider` (`getApplicationSupportDirectory` no store, `getApplicationCacheDirectory` no cache de catálogo) e num teste sem plataforma isso lança `MissingPluginException`:

- `buildCatalog(AddonStore store)`, que recebe o store pronto, com raiz de disco temporária.
- `fetchSources(client, console, sources, ...)`, que é o miolo de rede sem cache e sem boxart.

São métodos públicos com doc dizendo para que servem, sem `@visibleForTesting`. O repositório não usa a anotação em lugar nenhum (`grep -rn "visibleForTesting" lib/` não acha nada), e introduzir a primeira nesta Task acrescenta risco de `flutter analyze` mudar de 22 por um detalhe que não é o assunto da fatia.

**O teste de rede serve JSON, não HTML.** `_fetchFromUrl` manda HTML para `compute(_parseHtmlIsolate, ...)`, que sobe isolate de verdade; o ramo JSON (`_parseJsonListing`, `catalog_service.dart:479`) é síncrono e no mesmo isolate. Um corpo que começa com `[` cai no ramo JSON (`:354-356`), e é o que o teste usa.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/catalog_addons_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

typedef _Espiao = ({String url, List<Map<String, String?>> vistos});

/// Um servidor local que grava os cabeçalhos que recebeu e responde [corpo].
Future<_Espiao> _servidor(String corpo, {int status = 200}) async {
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => servidor.close(force: true));
  final vistos = <Map<String, String?>>[];
  servidor.listen((req) async {
    vistos.add({
      'authorization': req.headers.value('authorization'),
      'cookie': req.headers.value('cookie'),
    });
    req.response.statusCode = status;
    req.response.write(corpo);
    await req.response.close();
  });
  return (url: 'http://${servidor.address.address}:${servidor.port}/', vistos: vistos);
}

String _listagem(List<String> nomes) => jsonEncode([
      for (final nome in nomes) {'name': nome, 'size': 1024},
    ]);

Future<AddonStore> _store(List<Addon> addons, Map<String, String> catalogos) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('catalog_addons_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  for (final entrada in catalogos.entries) {
    await store.writeCatalog(entrada.key, entrada.value);
  }
  return store;
}

String _catalogo(String nomeDoConsole, String url, {Map<String, dynamic>? auth}) => jsonEncode([
      {'name': nomeDoConsole, 'url': url, 'file_format': ['.zip'], if (auth != null) 'auth': auth},
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildCatalog', () {
    test('dois addons com arquivo entram os dois, na ordem da lista', () async {
      final store = await _store(
        const [Addon(id: 'um', name: 'Um'), Addon(id: 'dois', name: 'Dois')],
        {
          'um': _catalogo('SNES', 'https://um/'),
          'dois': _catalogo('SNES', 'https://dois/'),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles['snes']!.urls, ['https://um/', 'https://dois/']);
      expect(merged.sources['snes']!.map((f) => f.addonId), ['um', 'dois']);
    });

    test('addon sem arquivo não entra e não derruba os outros', () async {
      final store = await _store(
        const [Addon(id: 'fantasma', name: 'Fantasma'), Addon(id: 'um', name: 'Um')],
        {'um': _catalogo('SNES', 'https://um/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']!.single.addonId, 'um');
    });

    test('catálogo ilegível de um addon não derruba os outros', () async {
      final store = await _store(
        const [Addon(id: 'quebrado', name: 'Quebrado'), Addon(id: 'um', name: 'Um')],
        {'quebrado': 'isto não é json', 'um': _catalogo('SNES', 'https://um/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles.keys, ['snes']);
      expect(merged.sources['snes']!.single.addonId, 'um');
    });

    test('a auth de cada fonte é a do addon que declarou o console', () async {
      final store = await _store(
        const [Addon(id: 'um', name: 'Um'), Addon(id: 'dois', name: 'Dois')],
        {
          'um': _catalogo('SNES', 'https://um/', auth: {'auth_message': 'cole o token'}),
          'dois': _catalogo('SNES', 'https://dois/', auth: {'cookies': true}),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']![0].auth!['auth_message'], 'cole o token');
      expect(merged.sources['snes']![1].auth!['cookies'], true);
    });

    test('lista de addons vazia dá catálogo vazio', () async {
      final store = await _store(const [], const {});
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.isEmpty, isTrue);
    });
  });

  group('fetchSources', () {
    const console = Console(id: 'snes', name: 'SNES', urls: [], fileFormat: ['.zip']);

    test('cada fonte é buscada com a auth do SEU addon', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final b = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(
        client,
        console,
        [
          ConsoleSource(addonId: 'um', url: a.url, auth: const {'auth_message': 'cole'}),
          ConsoleSource(addonId: 'dois', url: b.url, auth: const {'cookies': true, 'cookie_name': 'sessao'}),
        ],
        tokens: const {'um': 'tok-um', 'dois': 'tok-dois'},
      );

      expect(a.vistos.single['authorization'], 'Bearer tok-um');
      expect(a.vistos.single['cookie'], isNull);
      expect(b.vistos.single['cookie'], 'sessao=tok-dois');
      expect(b.vistos.single['authorization'], isNull);
    });

    test('os jogos voltam marcados com o addon que os serviu', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final b = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final jogos = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'um', url: a.url),
        ConsoleSource(addonId: 'dois', url: b.url),
      ]);

      final porTitulo = {for (final jogo in jogos) jogo.title: jogo.sourceId};
      expect(porTitulo, {'A (USA).zip': 'um', 'B (USA).zip': 'dois'});
    });

    test('sem token para o addon, nenhum cabeçalho de auth é mandado', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'um', url: a.url, auth: const {'auth_message': 'cole'}),
      ]);

      expect(a.vistos.single['authorization'], isNull);
    });

    test('uma fonte que falha não impede a outra de entregar', () async {
      final ruim = await _servidor('erro', status: 500);
      final boa = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final jogos = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'ruim', url: ruim.url),
        ConsoleSource(addonId: 'boa', url: boa.url),
      ]);

      expect(jogos.map((j) => j.title), ['B (USA).zip']);
      expect(jogos.single.sourceId, 'boa');
    });

    test('todas as fontes falhando propaga o erro', () async {
      final ruim = await _servidor('erro', status: 500);
      final client = HttpClient();
      addTearDown(client.close);

      expect(
        () => CatalogService().fetchSources(client, console, [ConsoleSource(addonId: 'ruim', url: ruim.url)]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/catalog_addons_test.dart
```

Esperado: falha de compilação, `The method 'buildCatalog' isn't defined for the type 'CatalogService'`.

- [ ] **Step 3: Troque o cache e a leitura do catálogo**

Em `lib/services/catalog_service.dart`, acrescente aos imports:

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
```

Troque o campo estático da linha 17

```dart
  static final Map<String, Map<String, Console>> _consolesCache = {};
```

por

```dart
  /// O catálogo fundido de todos os addons instalados. Um só, porque a lista
  /// de addons é uma só. Invalidado por `clearCache`, que toda escrita de
  /// catálogo chama.
  static MergedCatalog? _merged;
```

e substitua `getConsoles` (linhas 20-48) por:

```dart
  /// Os consoles de todos os addons instalados, fundidos.
  ///
  /// O parâmetro `consolesFilePath` que este método tinha nunca foi usado com
  /// valor diferente do padrão pelos nove chamadores, e não sobreviveria à
  /// lista de addons, onde não existe "o arquivo".
  Future<Map<String, Console>> getConsoles() async => (await mergedCatalog()).consoles;

  /// De onde vem cada url de um console, na mesma ordem de `console.urls`.
  Future<List<ConsoleSource>> sourcesFor(String consoleId) async => (await mergedCatalog()).sources[consoleId] ?? const [];

  Future<MergedCatalog> mergedCatalog() async {
    final cache = _merged;
    if (cache != null && !cache.isEmpty) return cache;
    try {
      return buildCatalog(await AddonStore.open());
    } catch (e) {
      debugPrint('No catalog source configured yet: $e');
      return const MergedCatalog();
    }
  }

  /// Lê e funde os catálogos dos addons de [store].
  ///
  /// Público porque `AddonStore.open()` passa por `path_provider`, que num
  /// teste sem plataforma lança `MissingPluginException`. Com o store entrando
  /// por parâmetro, o teste monta uma raiz em `Directory.systemTemp` e
  /// exercita disco de verdade.
  Future<MergedCatalog> buildCatalog(AddonStore store) async {
    final catalogos = <AddonCatalog>[];
    for (final addon in store.load()) {
      final cru = await store.readCatalog(addon.id) ?? await _bundledCatalog(addon.id);
      if (cru == null) continue;
      try {
        catalogos.add((addonId: addon.id, consoles: _parseConsoles(cru)));
      } catch (e) {
        // Um addon com JSON quebrado não pode derrubar os outros: o usuário
        // perderia a biblioteca inteira por causa de uma fonte de terceiro.
        debugPrint('Catálogo ilegível do addon ${addon.id}: $e');
      }
    }
    final merged = mergeCatalogs(catalogos);
    if (!merged.isEmpty) _merged = merged;
    return merged;
  }

  /// O catálogo de exemplo empacotado no app (`assets/catalog/`, git-ignored).
  ///
  /// Só o embutido tem um, e é a terceira e última precedência dele: arquivo
  /// do usuário, asset, nada. É a mesma precedência de antes da fatia 4.
  static Future<String?> _bundledCatalog(String addonId) async {
    if (addonId != kBuiltinAddonId) return null;
    try {
      return await rootBundle.loadString('assets/catalog/consoles.json');
    } catch (_) {
      return null;
    }
  }

  /// Esquece o catálogo fundido. Toda escrita de catálogo chama.
  static void clearCache() => _merged = null;
```

Troque `consoleByIdSync` (linhas 52-59) por:

```dart
  static Console? consoleByIdSync(String? id) {
    if (id == null) return null;
    return _merged?.consoles[id];
  }
```

E troque as três chamadas de `_consolesCache.clear()` (`setCatalogFromJson`, `addConsole`, `resetCatalog`) por `clearCache()`.

Nota de escopo: `setCatalogFromJson`, `addConsole` e `resetCatalog` continuam escrevendo em `config/consoles.json` via `_userConsolesFile()`, que não muda. Esse é exatamente o arquivo do addon embutido (`AddonStore.catalogFile`), então instalar catálogo pela tela de Ferramentas continua atualizando o embutido. A instalação como addon **novo** é a Task 21.

- [ ] **Step 4: Troque a busca para iterar fontes**

Ainda em `lib/services/catalog_service.dart`, substitua `loadCatalog` (linhas 195-228) e `_fetchCatalog` (230-274) por:

```dart
  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final merged = await mergedCatalog();
    final console = merged.consoles[consoleId];

    if (console == null) {
      debugPrint("Console with id '$consoleId' not found");
      return [];
    }

    final cacheFile = await _getCacheFile(console.cacheFile);
    if (await cacheFile.exists()) {
      try {
        final jsonStr = await cacheFile.readAsString();
        final List<Map<String, dynamic>> jsonList = await compute(_decodeGamesIsolate, jsonStr);
        final cachedResult = jsonList.map((json) => Game.fromJson(json)).toList();
        if (cachedResult.isNotEmpty && cachedResult.first.metadata != null) {
          final hasBoxarts = cachedResult.any((game) => game.details?.boxart != null);
          if (!hasBoxarts && console.boxarts != null) {
            final enrichedResult = await _boxartService.mutateGamesWithBoxarts(cachedResult, console);
            await cacheFile.writeAsString(jsonEncode(enrichedResult.map((g) => g.toJson()).toList()));
            return enrichedResult;
          }
          return cachedResult;
        }
      } catch (e) {
        debugPrint('Error reading cache: $e');
        await cacheFile.delete();
      }
    }

    return _fetchCatalog(console, merged.sources[consoleId] ?? const [],
        iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
  }

  Future<List<Game>> _fetchCatalog(Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    List<Game> catalog = [];

    try {
      catalog = await fetchSources(client, console, sources,
          iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
      catalog = await _boxartService.mutateGamesWithBoxarts(catalog, console);
      final cacheFile = await _getCacheFile(console.cacheFile);
      await cacheFile.writeAsString(jsonEncode(catalog.map((g) => g.toJson()).toList()));
    } catch (e) {
      debugPrint('Error fetching catalog: $e');
      rethrow;
    } finally {
      client.close();
    }

    return catalog;
  }

  /// Busca todas as [sources] em paralelo e devolve os jogos de todas, cada um
  /// já marcado com o addon que o serviu, ordenados por título.
  ///
  /// Público e sem disco por uma razão de teste: `_fetchCatalog` grava o cache
  /// por `getApplicationCacheDirectory`, que é `path_provider`, e num teste sem
  /// plataforma lança. Aqui entra um `HttpClient` e sai uma lista.
  ///
  /// Cada fonte fala com a auth do addon que a declarou e com o token daquele
  /// addon (`tokens[addonId]`). Antes da fatia 4 era uma auth e um token para
  /// todas as urls do console, o que, com dois addons, mandaria o token do
  /// primeiro para o servidor do segundo.
  Future<List<Game>> fetchSources(HttpClient client, Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final total = sources.length;
    var done = 0;
    Object? firstError;
    onProgress?.call(0, total);
    final results = await Future.wait(
      sources.map((source) => _fetchFromUrl(client, source, console,
                  iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, authToken: tokens[source.addonId])
              .then((games) {
            onProgress?.call(++done, total);
            return games;
          }).catchError((Object e) {
            // Mantém o resultado parcial quando só algumas páginas falham;
            // o erro só sobe quando nenhuma entregou nada (ex.: auth exigida).
            firstError ??= e;
            onProgress?.call(++done, total);
            return <Game>[];
          })),
    );
    if (firstError != null && results.every((r) => r.isEmpty)) {
      throw firstError!;
    }

    return results.expand((games) => games).toList()..sort((a, b) => a.title.compareTo(b.title));
  }
```

E troque `_fetchFromUrl` e `_fetchFromUrlIA` (linhas 276-321) para receberem a fonte em vez da url solta:

```dart
  Future<List<Game>> _fetchFromUrl(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    final url = source.url;
    if (_isArchiveOrgUrl(url)) {
      return _fetchFromUrlIA(client, source, console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey);
    }

    final request = await client.getUrl(Uri.parse(url));
    // `source.auth` e não `console.auth`: a auth pertence à url, não ao
    // console, porque dois addons podem servir o mesmo console.
    final headers = buildDownloadHeaders(url, buildConsoleAuthHeaders(source.auth, tokenOverride: authToken));
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to fetch catalog from $url');
    }

    final body = await response.transform(utf8.decoder).join();
    // Auto-detect: a JSON listing (e.g. from Retro Tools Server) vs HTML.
    final trimmed = body.trimLeft();
    final parsed = (trimmed.startsWith('[') || trimmed.startsWith('{'))
        ? _parseJsonListing(body, console, url)
        : await compute(_parseHtmlIsolate, [body, console.toJson(), url]);
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }

  Future<List<Game>> _fetchFromUrlIA(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey}) async {
    final itemId = _extractIAItemId(source.url);
    if (itemId == null) return [];

    final request = await client.getUrl(Uri.parse('$_iaMetadataBase$itemId'));

    // User-saved credentials take precedence over per-system auth config.
    final resolvedKey = iaAccessKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['access_key'] as String? : null);
    final resolvedSecret = iaSecretKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['secret_key'] as String? : null);
    if (resolvedKey != null && resolvedKey.isNotEmpty && resolvedSecret != null && resolvedSecret.isNotEmpty) {
      request.headers.set('Authorization', 'LOW $resolvedKey:$resolvedSecret');
    }

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: IA metadata fetch failed for $itemId');
    }

    final body = await response.transform(utf8.decoder).join();
    final parsed = await compute(_parseIAMetadataIsolate, [body, console.toJson(), itemId]);
    debugPrint('IA $itemId: body=${body.length}b parsed=${parsed.length} shouldUnzip=${console.shouldUnzip} fmts=${console.fileFormat}');
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }
```

**Tropeço provável:** deixar `console.auth` em `_fetchFromUrlIA` ao trocar só o `_fetchFromUrl`. A auth de IA S3 é lida por outro caminho (`auth['type'] == 'ia_s3'`, `catalog_service.dart:368-369`), e o grep por `buildConsoleAuthHeaders` não acha esse trecho. O critério é: **dentro de `_fetchFromUrl` e `_fetchFromUrlIA` não pode sobrar nenhuma leitura de `console.auth`.** Confira:

```bash
grep -n "console.auth" lib/services/catalog_service.dart
```

Esperado: nada.

- [ ] **Step 5: Acerte os dois chamadores que passavam `authToken`**

`loadCatalog` perdeu o parâmetro `authToken` e ganhou `tokens`, e **dois arquivos ainda passam o antigo**: `lib/providers/tinfoil_server_provider.dart:69` e `lib/providers/fbi_server_provider.dart:95`, os dois com a mesma linha

```dart
          authToken: settings.consoleSettings[console.id]?.authToken,
```

Isso é erro de compilação, não aviso: sem este Step o `flutter test` do Step 7 nem chega a rodar. Nos dois arquivos, troque a linha por

```dart
          // Só o embutido. Ver a limitação escrita no doc de `_authHeaders`,
          // logo abaixo neste mesmo arquivo.
          tokens: _tokensDoEmbutido(settings, console.id),
```

e acrescente, nos dois, os imports

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
```

O de `settings_model.dart` é obrigatório e fácil de esquecer: nenhum dos dois arquivos o importa hoje, eles chegam em `settings.consoleSettings` pelo tipo inferido de `_ref.read(settingsProvider)`, e **não existe um único `export` em `lib/`**, então escrever `AppSettings` na assinatura sem o import é erro de compilação.

Depois, o método privado:

```dart
  /// O token do addon embutido para este console, no formato que
  /// `loadCatalog` espera.
  ///
  /// **Limitação conhecida da fatia 4, e deliberada.** Os servidores de LAN
  /// (Tinfoil e FBI) continuam falando só com a credencial do addon embutido.
  /// A razão é o `_authHeaders` daqui: ele é síncrono, porque
  /// `TinfoilServerService.start` o recebe como `Map<String, String>
  /// Function(Console)`, e só tem um `Console` em mãos, sem o `Game` que diria
  /// de qual addon o arquivo veio. Ler o cofre de lá exigiria mudar o contrato
  /// do servidor HTTP, que não é assunto desta fatia. Consequência honesta:
  /// um console servido por um addon de terceiro com auth aparece na listagem
  /// do Tinfoil e falha ao baixar. O caminho normal do app, que é a grade e o
  /// download pelo `download_provider`, usa o token certo por addon.
  Map<String, String> _tokensDoEmbutido(AppSettings settings, String consoleId) {
    final token = settings.consoleSettings[consoleId]?.authToken ?? '';
    return token.isEmpty ? const {} : {kBuiltinAddonId: token};
  }
```

O `settings.consoleSettings[...].authToken` é o espelho do embutido, e continua sendo exatamente o que estas duas linhas liam antes. O comportamento de hoje fica idêntico; o que muda é que ele para de vazar para os outros addons.

- [ ] **Step 6: Ligue o provider ao cofre**

Em `lib/providers/catalog_provider.dart`, acrescente aos imports:

```dart
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
```

e troque o bloco das linhas 57-68 por:

```dart
      final settings = _ref.read(settingsProvider);
      // Um token por addon que serve este console, não um token por console.
      // A lista de addons não entra aqui: quem sabe quais addons servem este
      // console é a fusão, e ler só esses evita ida ao cofre por addon que
      // não tem nada a ver com o console aberto.
      final vault = (await _ref.read(vaultProvider.future)).vault;
      final tokens = <String, String>{};
      for (final addonId in {for (final fonte in await catalogService.sourcesFor(console.id)) fonte.addonId}) {
        final token = await vault.read(SecretRef.addonToken(addonId, console.id));
        if (token != null && token.isNotEmpty) tokens[addonId] = token;
      }

      final games = await catalogService.loadCatalog(
        console.id,
        iaAccessKey: settings.iaAccessKey,
        iaSecretKey: settings.iaSecretKey,
        tokens: tokens,
        onProgress: (done, total) {
          if (mounted && gen == _loadGeneration && total > 1) {
            state = state.copyWith(loadingStatus: 'Reading page $done of $total');
          }
        },
      );
```

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/catalog_addons_test.dart
```

Esperado: `+10`, zero falha.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+481`, zero falha. `test/catalog_selection_test.dart`, `test/add_catalog_source_screen_test.dart` e `test/catalog_add_console_test.dart` encostam em `CatalogService`: se algum quebrar por assinatura, o conserto é acompanhar a assinatura nova, nunca reintroduzir o parâmetro `authToken`.

- [ ] **Step 9: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/catalog_addons_test.dart
git commit -m "test(addon): catalogo lido de N addons, cada fonte com a auth e o token do seu"
git add lib/services/catalog_service.dart lib/providers/catalog_provider.dart lib/providers/tinfoil_server_provider.dart lib/providers/fbi_server_provider.dart
git commit -m "feat(addon): catalogo lido de N addons, cada fonte com a auth e o token do seu"
```

### Task 14: `addonProvider` e a prioridade derivada

**Files:**
- Create: `lib/providers/addon_provider.dart`
- Modify: `lib/services/catalog_service.dart` (ganha `invalidateForAddonChange`)
- Test: `test/addon_provider_test.dart`

O provider é fino de propósito: ele guarda a lista, persiste toda mudança e deriva a prioridade. As regras de lista já são funções puras da Task 9, e o disco já é o store da Task 11.

A única coisa não óbvia é **a ordem da invalidação**. Quando a lista muda, duas coisas ficam velhas: os arquivos de cache de jogo de cada console (`catalog_<id>.json`) e a fusão de catálogos em memória. `clearCatalogCache()` varre os caches de jogo iterando `getConsoles()`, ou seja, ela **precisa do catálogo antigo** para saber quais arquivos apagar. Se a fusão for esquecida primeiro, a varredura roda com a lista nova e deixa para trás o cache de um console que só o addon removido servia, e esse cache continuaria alimentando a grade.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/addon_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_provider_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  return store;
}

/// Devolve o container já com a lista inicial carregada, mais o store e o
/// contador de invalidações.
///
/// No topo do arquivo, e não dentro de `main`, por causa do lint
/// `no_leading_underscores_for_local_identifiers`, que vem ligado no
/// `flutter_lints` e vale para função local. `addTearDown` continua legal aqui
/// porque quem chama é sempre um corpo de teste.
Future<({ProviderContainer container, AddonStore store, List<int> invalidacoes})> _montar(List<Addon> iniciais) async {
  final store = await _store(iniciais);
  final invalidacoes = <int>[];
  final container = ProviderContainer(overrides: [
    addonProvider.overrideWith((ref) => AddonNotifier(
          Future.value(store),
          invalidarCache: () async => invalidacoes.add(1),
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(addonProvider.notifier).ready;
  return (container: container, store: store, invalidacoes: invalidacoes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carrega a lista do store no boot', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
  });

  test('install acrescenta no fim e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'b', name: 'B'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.store.load().map((x) => x.id), ['a', 'b']);
  });

  test('install do mesmo id substitui sem mudar a posição', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A corrigido'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.container.read(addonProvider).first.name, 'A corrigido');
  });

  test('install grava o catálogo no arquivo do addon', () async {
    final m = await _montar(const []);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A'), '[{"name":"SNES"}]');
    expect(await m.store.readCatalog('a'), '[{"name":"SNES"}]');
  });

  test('remove tira da lista e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).remove('a');
    expect(m.container.read(addonProvider).map((x) => x.id), ['b']);
    expect(m.store.load().map((x) => x.id), ['b']);
  });

  test('remove apaga o arquivo de catálogo do addon', () async {
    final m = await _montar(const []);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'a', name: 'A'), '[]');
    await notifier.remove('a');
    expect(await m.store.readCatalog('a'), isNull);
  });

  test('reorder aplica a semântica do ReorderableListView e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B'), Addon(id: 'c', name: 'C')]);
    await m.container.read(addonProvider.notifier).reorder(0, 3);
    expect(m.container.read(addonProvider).map((x) => x.id), ['b', 'c', 'a']);
    expect(m.store.load().map((x) => x.id), ['b', 'c', 'a']);
  });

  test('install e remove invalidam o cache, reorder também', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'c', name: 'C'), '[]');
    await notifier.remove('a');
    await notifier.reorder(0, 2);
    expect(m.invalidacoes.length, 3);
  });

  test('sourcePriority devolve os ids na ordem da lista', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(sourcePriorityProvider), ['a', 'b']);
  });

  test('sourcePriority acompanha o arrasto', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).reorder(1, 0);
    expect(m.container.read(sourcePriorityProvider), ['b', 'a']);
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/addon_provider_test.dart
```

Esperado: falha de compilação, `Target of URI doesn't exist: 'package:roms_downloader/providers/addon_provider.dart'`.

- [ ] **Step 3: Dê ao `CatalogService` a invalidação na ordem certa**

Em `lib/services/catalog_service.dart`, logo depois de `clearCatalogCache` (que fecha a classe), acrescente:

```dart
  /// Esquece tudo que dependia da lista de addons: os arquivos de cache de
  /// jogo de cada console **e depois** a fusão de catálogos.
  ///
  /// A ordem não é estilo. `clearCatalogCache` descobre quais arquivos apagar
  /// iterando `getConsoles()`, então ela precisa do catálogo **antigo**.
  /// Invertida, a varredura rodaria com a lista nova e deixaria para trás o
  /// cache de um console que só o addon removido servia, e esse arquivo
  /// continuaria alimentando a grade depois da remoção.
  Future<void> invalidateForAddonChange() async {
    await clearCatalogCache();
    clearCache();
  }
```

- [ ] **Step 4: Escreva o provider**

Crie `lib/providers/addon_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';

final addonProvider = StateNotifierProvider<AddonNotifier, List<Addon>>((ref) {
  return AddonNotifier(AddonStore.open());
});

/// A ordem de prioridade das fontes, derivada da ordem da lista.
///
/// É o que alimenta o `sourcePriority` de `planFromEntries`
/// (`source_pick_service.dart:54`), o último critério de desempate da seção 6
/// do spec de UI. Derivado e não guardado: prioridade que fosse um campo
/// próprio poderia discordar da ordem que o usuário vê na tela.
final sourcePriorityProvider = Provider<List<String>>((ref) => [for (final addon in ref.watch(addonProvider)) addon.id]);

class AddonNotifier extends StateNotifier<List<Addon>> {
  final Future<AddonStore> _store;

  /// O que esquecer quando a lista muda. Entra por parâmetro porque o padrão
  /// passa por `path_provider`, que num teste sem plataforma lança; o teste
  /// passa uma função que só conta quantas vezes foi chamada.
  final Future<void> Function() _invalidarCache;

  /// Resolve quando a lista inicial chegou do disco.
  late final Future<void> ready;

  AddonNotifier(this._store, {Future<void> Function()? invalidarCache})
      : _invalidarCache = invalidarCache ?? CatalogService().invalidateForAddonChange,
        super(const []) {
    ready = _carregar();
  }

  Future<void> _carregar() async {
    final store = await _store;
    if (!mounted) return;
    state = store.load();
  }

  /// Instala, ou reinstala, um addon com o catálogo já baixado.
  ///
  /// Reinstalar mantém a posição (`upsertAddon`), e é por isso que corrigir a
  /// url de uma fonte não rebaixa a prioridade dela.
  Future<void> install(Addon addon, String catalogoJson) async {
    final store = await _store;
    await store.writeCatalog(addon.id, catalogoJson);
    final nova = upsertAddon(state, addon);
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }

  /// Tira o addon da lista e apaga o catálogo dele do disco.
  ///
  /// **Não** apaga o segredo do cofre. Reinstalar a mesma fonte tem que
  /// reencontrar o token, e é para isso que `Addon.idFromUrl` é estável. Quem
  /// apaga credencial é a tela de conta, por pedido explícito (Grupo 5).
  Future<void> remove(String id) async {
    final store = await _store;
    await store.deleteCatalog(id);
    final nova = removeAddon(state, id);
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }

  Future<void> reorder(int from, int to) async {
    final nova = reorderAddons(state, from, to);
    final store = await _store;
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }
}
```

**Tropeço provável:** `remove` apagando também o segredo do cofre, "para limpar". Parece higiene e é perda de dado: o usuário que remove um addon para reinstalá-lo com a url corrigida teria que descobrir de novo o token. A escolha está escrita no doc do método para não ser "consertada" numa revisão.

**Segundo tropeço, sem teste que o pegue:** a ordem dentro de `invalidateForAddonChange`. Ela não é coberta por teste porque as duas metades passam por `path_provider`: `clearCatalogCache` chama `getApplicationCacheDirectory` e `getConsoles` chama `getApplicationSupportDirectory`, e num teste sem plataforma as duas viram no-op silencioso em vez de falhar. O que existe é o comentário no método, e é honesto dizer que essa linha é conferida por leitura, não por suíte.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_provider_test.dart
```

Esperado: `+10`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+491`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_provider_test.dart
git commit -m "test(addon): provider da lista de addons e a prioridade derivada da ordem"
git add lib/providers/addon_provider.dart lib/services/catalog_service.dart
git commit -m "feat(addon): provider da lista de addons e a prioridade derivada da ordem"
```

**Fim da Grupo 3.** O app tem N catálogos, cada um com identidade, auth e token próprios, e uma ordem que o usuário vai poder arrastar na Grupo 5. O que ainda não acontece: a grade continua dizendo que toda fonte é `kBuiltinSourceId`, e o lote continua sem receber a prioridade. É a Grupo 4.

| Task | Novos | Acumulado |
| --- | --- | --- |
| 8b, hidratação sem inventar config | 4 | 425 |
| 9, modelo de addon | 15 | 440 |
| 10, fusão de catálogos | 11 | 451 |
| 11, persistência | 14 | 465 |
| 12, `Game.sourceId` | 6 | 471 |
| 13, catálogo de N addons | 10 | 481 |
| 14, provider e prioridade | 10 | 491 |

---

## Grupo 4: a fonte com identidade

A Grupo 3 deu identidade ao catálogo: cada `Console` sabe quais addons o servem, cada `Game` que sai da rede já vem carimbado com o `sourceId` de quem o serviu, e `sourcePriorityProvider` já devolve a ordem da lista. Nada disso chegou na grade nem nas telas ainda.

Três coisas faltam, e cada uma é uma Task:

1. **O carimbo não é lido.** `pack_grid_provider.dart:75` e `source_pick_service.dart:27` escrevem `kBuiltinSourceId` na mão, uma constante de fatia 3 cujo próprio doc já anunciava a data de validade: *"Na fatia 4 ele vira o id do addon que serviu o arquivo"* (`source_pick_model.dart:4-9`). A Task 15 lê `game.sourceId` nos dois lugares e apaga a constante.
2. **A prioridade não chega em quem escolhe.** `planFromEntries` aceita `sourcePriority` desde a fatia 3 (`source_pick_service.dart:54`) e os dois chamadores, `home_screen.dart:43` e `game_detail_screen.dart:74`, não passam nada. O parâmetro tem valor padrão, então isso compila hoje e continuaria compilando para sempre. A Task 16 liga os dois.
3. **A tela mostra o id, e o usuário não escolheu um id.** A seção 7 do spec de UI pede "4.0 MB, Myrient". Depois da Task 15 o campo passa a valer `myrient_org_files`, que é chave de cofre e de disco, não texto de tela. A Task 17 resolve o id para o nome do addon nos dois lugares onde ele é desenhado.

**Uma regra para as trocas de `kBuiltinSourceId` nos testes, porque ela decide seis arquivos.** A constante morre na Task 15, e onze linhas de teste a citam pelo nome. Elas não são todas a mesma coisa:

- Onde o teste **afirma o que a produção calculou**, a troca é por `kBuiltinAddonId`. É um sítio só: `test/pack_grid_provider_test.dart:108`, que lê o `sourceId` que o `sourceIndexProvider` montou a partir de um `Game`.
- Onde o id é **dado de entrada inventado pelo teste**, a troca é pelo literal `'listagem'`, que é o que oito outras linhas da suíte já usam (`source_verification_provider_test.dart:18`, `source_pick_model_test.dart:17`, `pack_grid_filter_test.dart:10`, `batch_confirm_sheet_test.dart:12`, `source_pick_service_test.dart:20`, `source_index_test.dart:25` e `:67`, `grid_entry_model_test.dart:9`). Nesses sítios o id é opaco: qualquer string não vazia serve, e nenhuma asserção depende de qual é.

**Não faça um `sed` do literal `'listagem'` para `'builtin'`.** Parece a limpeza óbvia e custa caro por nada: em `test/game_detail_screen_test.dart` o `sourceId` da fonte é desenhado na tela, e dez expectativas do arquivo carregam a string (`'4.0 MB, listagem'` na linha 121, e mais nove entre as linhas 269 e 462). Trocar o literal obrigaria a reescrever as dez, num commit que é sobre apagar uma constante. O literal fica.

### Task 15: o id do addon chega na grade e no lote

**Files:**
- Modify: `lib/providers/pack_grid_provider.dart:75` (mais o import da linha 5, que fica órfão)
- Modify: `lib/services/source_pick_service.dart:27`
- Modify: `lib/models/source_pick_model.dart:4-17` (apaga `kBuiltinSourceId`) e `:35-37` (o doc do campo)
- Test: `test/pack_grid_provider_test.dart`, `test/source_pick_service_test.dart`, `test/pack_grid_test.dart`, `test/game_detail_screen_test.dart`

São duas linhas de produção e uma constante apagada. O que dá trabalho é a arrumação nos testes, e ela é mecânica se você seguir a regra do topo do grupo.

Repare no detalhe do import: `lib/providers/pack_grid_provider.dart` importa `source_pick_model.dart` na linha 5 **só** por causa de `kBuiltinSourceId`. Conferido com `grep -n "SourcePick\|BatchPlan\|PickFailure\|kBuiltinSourceId" lib/providers/pack_grid_provider.dart`, que devolve uma linha só, a 75. Tirado o uso, o import vira `unused_import` e o analyze sai de 22. Em `lib/services/source_pick_service.dart` o import fica, porque de lá vêm `SourcePick` e `BatchPlan`.

- [ ] **Step 1: Escreva os testes que falham**

Em `test/pack_grid_provider_test.dart`, acrescente o import do modelo de addon junto dos outros:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

troque a assinatura do `_game` das linhas 28 a 33 por esta, que aceita o addon:

```dart
Game _game(String filename, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename,
      url: 'https://exemplo.org/snes/$filename',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );
```

troque as três citações de `kBuiltinSourceId` do arquivo (linhas 108, 126 e 141) por `kBuiltinAddonId`, e acrescente este caso logo depois do teste `'a fonte casada carrega o tamanho e o id de fonte embutido'`:

```dart
  test('cada fonte carrega o id do addon do jogo que a originou', () async {
    final container = _container(jogos: [
      _game('Chrono Trigger (USA).zip', sourceId: 'myrient'),
      _game('Super Metroid (USA).zip', sourceId: 'arquivo-do-fulano'),
    ]);
    await _pronto(container);

    // Mapa e não lista: o que está sendo afirmado é que cada fonte ficou com
    // o id do **seu** jogo, e isso não depende da ordem da grade.
    expect(
      {for (final e in container.read(packGridEntriesProvider)) e.game.id: e.sources.single.sourceId},
      {'snes/chrono-trigger': 'myrient', 'snes/super-metroid': 'arquivo-do-fulano'},
    );
  });
```

Em `test/source_pick_service_test.dart`, troque o `_game` das linhas 10 a 15 por:

```dart
Game _game(String filename, int size, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://exemplo.org/snes/$filename',
      size: size,
      consoleId: 'snes',
      sourceId: sourceId,
    );
```

acrescente o import do modelo de addon:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

troque o `kBuiltinSourceId` da linha 50, dentro do helper `_v`, pelo literal `'listagem'` (é fixture: `_v` monta a entrada de `splitByVerification` e nenhuma asserção do arquivo lê esse campo), e acrescente os dois casos abaixo logo depois do teste `'cada jogo selecionado vira uma escolha, na mesma ordem'`:

```dart
  test('planFromGames carrega o id do addon de cada jogo', () {
    final plan = planFromGames([
      _game('Chrono Trigger (USA).zip', 4 * 1024 * 1024, sourceId: 'myrient'),
      _game('Super Metroid (USA).zip', 2 * 1024 * 1024, sourceId: 'arquivo-do-fulano'),
    ]);

    expect(plan.picks.map((p) => p.sourceId), ['myrient', 'arquivo-do-fulano']);
  });

  test('jogo de cache antigo, sem addon declarado, vira o embutido', () {
    // `Game.sourceId` tem padrão (Task 12), então um `Game` vindo de um
    // `catalog_<id>.json` gravado antes desta fatia entra aqui sem carimbo.
    // Ele não pode virar string vazia: fonte sem id some da prioridade e
    // apareceria na tela como ", " entre o tamanho e o selo.
    final plan = planFromGames([_game('Chrono Trigger (USA).zip', 1024)]);

    expect(plan.picks.single.sourceId, kBuiltinAddonId);
  });
```

Em `test/pack_grid_test.dart`, troque os dois `kBuiltinSourceId` (linhas 24 e 39) pelo literal `'listagem'` e apague o import de `source_pick_model.dart` se ele ficar sem uso. Confira com `grep -n "source_pick_model\|SourcePick\|BatchPlan" test/pack_grid_test.dart` antes de apagar: se o arquivo usa `SourcePick` em outro lugar, o import fica.

Em `test/game_detail_screen_test.dart`, troque o `kBuiltinSourceId` da linha 46 pelo literal `'listagem'` e apague o import de `source_pick_model.dart` pelo mesmo critério. Aqui o `grep` é obrigatório e não decorativo: o arquivo usa `SourcePick` no callback `onDownload`, então é provável que o import fique.

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/pack_grid_provider_test.dart test/source_pick_service_test.dart
```

Esperado: erro de compilação, `Undefined name 'kBuiltinSourceId'` nos arquivos que ainda a citam e `No named parameter with the name 'sourceId'` se você tiver pulado a Task 12. Depois que compilar, os três casos novos falham: a grade e o lote ainda carimbam a constante.

- [ ] **Step 3: A grade lê o carimbo do jogo**

Em `lib/providers/pack_grid_provider.dart`, apague o import da linha 5:

```dart
import 'package:roms_downloader/models/source_pick_model.dart';
```

e troque a linha 75:

```dart
      (filename: game.filename, sourceId: game.sourceId, size: game.size, url: game.url),
```

- [ ] **Step 4: O lote lê o carimbo do jogo**

Em `lib/services/source_pick_service.dart`, na linha 27, dentro de `planFromGames`:

```dart
          sourceId: game.sourceId,
```

e ajuste o doc da função, que hoje diz que a regra de prioridade "só tem sujeito em MODO PACK". Continua verdade, mas a menção à Task 14 da fatia 3 confunde numa fatia que também tem Task 14:

```dart
/// A regra de verdade da seção 6 do spec de UI, com região, revisão,
/// confiança e prioridade de addon, mora em `planFromEntries` e só tem
/// sujeito em MODO PACK, onde existe mais de uma versão do mesmo jogo.
```

- [ ] **Step 5: Apague a constante**

Em `lib/models/source_pick_model.dart`, apague o bloco das linhas 4 a 17 inteiro, doc e constante. Se o arquivo ficar sem uso para o import de `game_model.dart`, confira antes: `SourcePick.game` é um `Game`, então o import fica.

Troque o doc do campo `sourceId`, nas linhas 35 a 37, que descreve um mundo que acabou de deixar de existir:

```dart
  /// De qual addon veio, pelo id de [Addon]. É o que a linha "4.0 MB,
  /// Myrient" da seção 7 mostra, depois de a tela resolver o id para o nome
  /// (Task 17). Vem de `Game.sourceId`, carimbado pelo `CatalogService` na
  /// hora de buscar a listagem.
  final String sourceId;
```

Confira que não sobrou nada:

```bash
grep -rn "kBuiltinSourceId" lib/ test/
```

Esperado: nenhuma linha.

- [ ] **Step 6: Rode os arquivos tocados**

```bash
flutter test test/pack_grid_provider_test.dart test/source_pick_service_test.dart test/pack_grid_test.dart test/game_detail_screen_test.dart
```

Esperado: zero falha. Os três casos novos passam e nenhum dos antigos mudou de resultado, inclusive as dez expectativas de `'... listagem ...'` da tela de detalhe, que continuam valendo porque o literal ficou.

**Tropeço provável:** apagar o import da linha 5 de `pack_grid_provider.dart` e não apagar, ou apagar um import que ainda é usado em `pack_grid_test.dart` e `game_detail_screen_test.dart`. Os dois erros são pegos pelo `flutter analyze` do Step 8, um como `unused_import` e o outro como erro de compilação, mas o primeiro é `info` e passa batido numa leitura apressada da saída. O critério é o `grep` de cada arquivo, não o olho.

**Segundo tropeço:** trocar o literal `'listagem'` por `'builtin'` "para ficar coerente". Está escrito na abertura do grupo por quê, e a consequência é dez expectativas de string vermelhas em `game_detail_screen_test.dart` numa Task que não mexeu em tela nenhuma.

- [ ] **Step 7: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+494`, zero falha.

- [ ] **Step 8: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/pack_grid_provider_test.dart test/source_pick_service_test.dart test/pack_grid_test.dart test/game_detail_screen_test.dart
git commit -m "test(addon): a fonte casada passa a carregar o id do addon que a serviu"
git add lib/providers/pack_grid_provider.dart lib/services/source_pick_service.dart lib/models/source_pick_model.dart
git commit -m "feat(addon): a fonte casada passa a carregar o id do addon que a serviu"
```

### Task 16: as duas telas passam a prioridade do usuário

**Files:**
- Modify: `lib/screens/home_screen.dart:43-47`
- Modify: `lib/screens/game_detail_screen.dart:74-78`
- Test: `test/game_detail_screen_test.dart`

`planFromEntries` tem `List<String> sourcePriority = const []` com valor padrão desde a fatia 3, e é por isso que esta Task é necessária: sem o padrão, o compilador teria cobrado os dois chamadores no dia em que o parâmetro nasceu. Com ele, o app compila hoje passando lista vazia para sempre, e a ordem que o usuário vai arrastar na Grupo 5 não decidiria nada.

**Uma honestidade sobre cobertura, antes dos passos.** `test/` não tem teste de `HomeScreen`: a tela monta o app inteiro, com fila de download, estado global e catálogo. A linha dela é conferida por leitura e pelo `flutter build linux --debug` do Step 6, não por suíte. O que a suíte prova é a outra metade: a tela de detalhe chama a mesma função com a mesma lista, e os testes abaixo mostram que a saída muda quando a lista muda. Não escreva no relatório que "as duas telas estão testadas".

- [ ] **Step 1: Escreva os testes que falham**

Em `test/game_detail_screen_test.dart`, acrescente o import do provider de addon:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

dê ao `_fonte` das linhas 39 a 49 um id de fonte configurável:

```dart
MatchedSource _fonte(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confianca = MatchConfidence.likely,
  String sourceId = 'listagem',
}) =>
    MatchedSource(
      filename: filename,
      sourceId: sourceId,
      confidence: confianca,
      size: size,
    );
```

e dê ao `_host` um parâmetro de prioridade, com a sobrescrita do provider:

```dart
Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verificacao,
  List<String> prioridade = const [],
}) {
  return ProviderScope(
    overrides: [
      semDiscoDeFavoritos,
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolvePadrao),
      // Obrigatória, e não conveniência: sem ela o provider de verdade seria
      // construído, e ele lê `addonProvider`, que abre `AddonStore` por
      // `path_provider`. Num teste de widget sem plataforma isso lança
      // `MissingPluginException` dentro de um `Future` que ninguém espera.
      sourcePriorityProvider.overrideWithValue(prioridade),
```

**A mesma sobrescrita tem que entrar no `ProviderScope` solto do teste `'o checkbox alterna a seleção pela chave de pack'`, nas linhas 158 a 178**, que não usa o `_host`. Lá ela vai com a lista vazia:

```dart
        sourcePriorityProvider.overrideWithValue(const []),
```

Acrescente os três casos no fim do `main`:

```dart
  testWidgets('a prioridade do usuário decide o destaque entre fontes empatadas', (tester) async {
    // Mesmo nome de arquivo nas duas, então região, revisão e confiança
    // empatam e sobra só o eixo de addon. O `size` difere porque ele não
    // entra no desempate e serve de observável: é ele que diz qual das duas
    // ganhou, e não só o que o motivo escreveu.
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip', size: 10, sourceId: 'lento'),
        _fonte('Chrono Trigger (USA).zip', size: 20, sourceId: 'rapido'),
      ]),
      prioridade: const ['rapido', 'lento'],
    ));

    // Pela ordem de chegada venceria a de 10 bytes. Venceu a de 20.
    expect(find.text('20.0 B, rapido'), findsOneWidget);
  });

  testWidgets('invertida a ordem dos addons, o destaque troca', (tester) async {
    // O par do caso acima, com a ordem de chegada invertida junto com a
    // prioridade. Os dois juntos são o que separa "a tela passa a lista do
    // usuário" de "a tela passa uma lista qualquer que por sorte acertou".
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip', size: 20, sourceId: 'rapido'),
        _fonte('Chrono Trigger (USA).zip', size: 10, sourceId: 'lento'),
      ]),
      prioridade: const ['lento', 'rapido'],
    ));

    expect(find.text('10.0 B, lento'), findsOneWidget);
  });

  testWidgets('sem addon na lista, o desempate volta para a ordem de chegada', (tester) async {
    // O estado de um usuário que removeu todos os addons e ficou só com o
    // cache. Lista vazia não pode virar exceção nem sumir com o destaque.
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip', size: 10, sourceId: 'lento'),
        _fonte('Chrono Trigger (USA).zip', size: 20, sourceId: 'rapido'),
      ]),
      prioridade: const [],
    ));

    expect(find.text('10.0 B, lento'), findsOneWidget);
  });
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: os dois primeiros casos falham com `Expected: exactly one matching candidate / Actual: _TextFinder:<zero widgets>`, porque a tela ainda não passa prioridade nenhuma e o destaque sai pela ordem de chegada. O terceiro já passa, e é assim mesmo: ele é rede de segurança, não motor.

- [ ] **Step 3: A tela de detalhe passa a prioridade**

Em `lib/screens/game_detail_screen.dart`, acrescente o import:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

e a linha nova na chamada das linhas 74 a 78:

```dart
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
      sourcePriority: ref.watch(sourcePriorityProvider),
    );
```

`watch` e não `read`, como os vizinhos: arrastar um addon na tela de addons tem que redesenhar o destaque de uma tela de detalhe aberta atrás dela.

- [ ] **Step 4: A tela inicial passa a prioridade**

Em `lib/screens/home_screen.dart`, acrescente o import:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

e a linha nova em `_planoDaSelecao`, linhas 43 a 47:

```dart
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selecionadas),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
        sourcePriority: ref.read(sourcePriorityProvider),
      );
```

`read` e não `watch`, como os vizinhos: isto roda dentro de um callback de botão, e um `watch` fora de `build` é erro do Riverpod, não questão de gosto.

**Tropeço provável:** copiar o `watch` da tela de detalhe para dentro de `_planoDaSelecao`. O método é chamado de `_confirmarLote`, que é um `Future<void>` disparado por toque. `ref.watch` ali lança em tempo de execução, e o teste que pegaria isso não existe, porque `HomeScreen` não tem teste. O que pega é o Step 6.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/game_detail_screen_test.dart
```

Esperado: zero falha.

- [ ] **Step 6: Compile o app inteiro**

```bash
flutter build linux --debug
```

Esperado: `Building Linux application...` e nenhum erro. É o que cobre `home_screen.dart`, que não tem teste de widget. Não prova o que aparece na tela: prova que a tela compila com a chamada nova e que nenhum import ficou faltando.

- [ ] **Step 7: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+497`, zero falha.

- [ ] **Step 8: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/game_detail_screen_test.dart
git commit -m "test(addon): as telas passam a ordem de addons do usuario para a regra de escolha"
git add lib/screens/game_detail_screen.dart lib/screens/home_screen.dart
git commit -m "feat(addon): as telas passam a ordem de addons do usuario para a regra de escolha"
```

### Task 17: a tela de detalhe mostra o nome do addon, não o id

**Files:**
- Modify: `lib/providers/addon_provider.dart` (ganha `addonNamesProvider`)
- Modify: `lib/screens/game_detail_screen.dart` (`_Destaque` e `_OutrasFontes`/`_LinhaFonte` ganham o mapa)
- Test: `test/addon_provider_test.dart`, `test/game_detail_screen_test.dart`

A seção 7 do spec de UI pede "4.0 MB, Myrient". Depois da Task 15, `SourcePick.sourceId` vale `myrient_org_files`, porque `Addon.idFromUrl` normaliza a url para virar chave de cofre e nome de arquivo. Chave é para máquina. A tela tem que mostrar o `Addon.name`.

Os dois sítios que desenham o id são `game_detail_screen.dart:344`, dentro de `_Destaque`, e `:499`, dentro de `_LinhaFonte`. Os dois são `StatelessWidget`, e o arquivo tem uma regra escrita sobre isso: *"Os widgets filhos não veem `ref`: eles são burros como todo o resto desta fatia"* (`game_detail_screen.dart:63-65`). Então o mapa desce como dado, igual a todo o resto. Não transforme `_Destaque` em `ConsumerWidget`.

- [ ] **Step 1: Escreva os testes que falham**

Em `test/addon_provider_test.dart`, acrescente o caso no fim do `main`:

```dart
  test('addonNames mapeia cada id para o nome do addon', () async {
    final m = await _montar(const [
      Addon(id: 'myrient', name: 'Myrient'),
      Addon(id: kBuiltinAddonId, name: 'Catálogo embutido'),
    ]);

    expect(m.container.read(addonNamesProvider), {
      'myrient': 'Myrient',
      kBuiltinAddonId: 'Catálogo embutido',
    });
  });
```

Em `test/game_detail_screen_test.dart`, dê ao `_host` o mapa de nomes:

```dart
Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verificacao,
  List<String> prioridade = const [],
  Map<String, String> nomes = const {},
}) {
```

com a sobrescrita logo abaixo da de prioridade, pela mesma razão dela (o provider de verdade lê `addonProvider`, que abre disco):

```dart
      addonNamesProvider.overrideWithValue(nomes),
```

e a mesma linha, com `const {}`, no `ProviderScope` solto do teste `'o checkbox alterna a seleção pela chave de pack'`.

Repare que o padrão é mapa vazio, e é ele que mantém verdes as dez expectativas de `'... listagem ...'` do arquivo: sem nome conhecido, a tela desenha o id, e o id nesses testes é `'listagem'`.

Acrescente os três casos no fim do `main`:

```dart
  testWidgets('o destaque mostra o nome do addon, não o id', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip', sourceId: 'myrient_org_files')]),
      nomes: const {'myrient_org_files': 'Myrient'},
    ));

    expect(find.text('4.0 MB, Myrient'), findsOneWidget);
  });

  testWidgets('a lista de outras fontes também mostra o nome', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [
        _fonte('Chrono Trigger (USA).zip', size: 10, sourceId: 'myrient_org_files'),
        _fonte('Chrono Trigger (USA).zip', size: 20, sourceId: 'arquivo_do_fulano'),
      ]),
      nomes: const {'myrient_org_files': 'Myrient', 'arquivo_do_fulano': 'Arquivo do Fulano'},
    ));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    expect(find.text('20.0 B, Arquivo do Fulano, HTTP, casamento provável'), findsOneWidget);
  });

  testWidgets('addon que não está mais na lista cai no id, e não em branco', (tester) async {
    // O usuário removeu o addon e o cache de jogo dele ainda está em disco.
    // A informação vira ruim, e tem que continuar existindo: "4.0 MB, " com
    // a vírgula pendurada é pior que um id feio.
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip', sourceId: 'addon_removido')]),
      nomes: const {},
    ));

    expect(find.text('4.0 MB, addon_removido'), findsOneWidget);
  });
```

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/addon_provider_test.dart test/game_detail_screen_test.dart
```

Esperado: erro de compilação, `Undefined name 'addonNamesProvider'`.

- [ ] **Step 3: O provider do mapa**

Em `lib/providers/addon_provider.dart`, logo abaixo de `sourcePriorityProvider`:

```dart
/// Do id do addon para o nome que o usuário escreveu ou que o catálogo trouxe.
///
/// A seção 7 do spec de UI pede "4.0 MB, Myrient", e `SourcePick.sourceId`
/// guarda `myrient_org_files`, que é chave de cofre e nome de arquivo. Mapa e
/// não busca linear porque a lista de outras fontes resolve um nome por linha.
///
/// Quem lê tem que tratar id ausente: o cache de jogo de um addon removido
/// sobrevive à remoção, e o `sourceId` dele não está mais na lista.
final addonNamesProvider = Provider<Map<String, String>>(
  (ref) => {for (final addon in ref.watch(addonProvider)) addon.id: addon.name},
);
```

- [ ] **Step 4: O mapa desce até quem desenha**

Em `lib/screens/game_detail_screen.dart`, dentro do `build`, logo depois de `final resolver = ref.watch(gameResolverProvider);` (linha 61):

```dart
    final nomesDeAddon = ref.watch(addonNamesProvider);
```

passe para o `_Destaque` (linhas 145 a 152):

```dart
            _Destaque(
              pick: escolha,
              addonNames: nomesDeAddon,
              verification: vencedora.state,
              confirmadoPorCrc: split.confirmed,
              // Hesita só enquanto a hesitação pode mudar alguma coisa.
              hesita: split.verifying && !split.confirmed,
              onDownload: () => onDownload(escolha),
            ),
```

e para o `_OutrasFontes` (linhas 161 a 166):

```dart
            _OutrasFontes(
              sources: outras,
              addonNames: nomesDeAddon,
              descartadas: split.discarded.length,
              comecaAberta: split.noCertainty,
              onDownload: split.noCertainty ? baixarFonte : null,
            ),
```

Em `_Destaque` (linha 290), acrescente o campo e o parâmetro:

```dart
class _Destaque extends StatelessWidget {
  final SourcePick pick;

  /// Id do addon para nome. Vazio é estado legítimo: quem não estiver no mapa
  /// é desenhado pelo id.
  final Map<String, String> addonNames;
  final SourceVerification verification;
  final bool confirmadoPorCrc;
  final bool hesita;
  final VoidCallback onDownload;

  const _Destaque({
    required this.pick,
    required this.addonNames,
    required this.verification,
    required this.confirmadoPorCrc,
    required this.hesita,
    required this.onDownload,
  });
```

e troque a linha 344:

```dart
            '${formatBytes(pick.size)}, ${addonNames[pick.sourceId] ?? pick.sourceId}'
            '${selo == null ? '' : ', $selo'}',
```

Em `_OutrasFontes` (linha 432), acrescente o campo, o parâmetro, e o repasse:

```dart
class _OutrasFontes extends StatelessWidget {
  final List<VerifiedSource> sources;
  final Map<String, String> addonNames;
  final int descartadas;
  final bool comecaAberta;

  /// Null na maioria das vezes: o botão por linha é só o estado "verificação
  /// impossível" da seção 8.
  final void Function(VerifiedSource item)? onDownload;

  const _OutrasFontes({
    required this.sources,
    required this.addonNames,
    required this.descartadas,
    required this.comecaAberta,
    required this.onDownload,
  });
```

```dart
          for (final item in sources)
            _LinhaFonte(
              item: item,
              addonNames: addonNames,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
```

Em `_LinhaFonte` (linha 477):

```dart
class _LinhaFonte extends StatelessWidget {
  final VerifiedSource item;
  final Map<String, String> addonNames;
  final VoidCallback? onDownload;

  const _LinhaFonte({required this.item, required this.addonNames, required this.onDownload});
```

e troque a linha 499:

```dart
            '${formatBytes(item.source.size)}, '
            '${addonNames[item.source.sourceId] ?? item.source.sourceId}, '
```

**Tropeço provável:** trocar o `?? item.source.sourceId` por `?? ''` ou por `?? 'desconhecido'`. O primeiro deixa `"4.0 MB, , HTTP, ..."` na tela, com a vírgula pendurada, e é o que acontece com todo jogo em cache de um addon removido. O segundo apaga a única pista que o usuário tem de onde o arquivo veio. O id feio é a resposta certa aqui.

**Segundo tropeço:** transformar `_Destaque` ou `_LinhaFonte` em `ConsumerWidget` para ler o provider direto. Funciona e quebra a regra escrita em `game_detail_screen.dart:63-65`, que existe por um motivo medido na fatia 3: os widgets filhos são testados pelo `_host`, com dado injetado, e um `ref` dentro deles obrigaria todo teste de widget filho a montar `ProviderScope`.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_provider_test.dart test/game_detail_screen_test.dart
```

Esperado: zero falha. As dez expectativas de `'... listagem ...'` continuam verdes, porque o mapa padrão do `_host` é vazio e a tela cai no id.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+501`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_provider_test.dart test/game_detail_screen_test.dart
git commit -m "test(addon): a tela de detalhe mostra o nome do addon, com o id como reserva"
git add lib/providers/addon_provider.dart lib/screens/game_detail_screen.dart
git commit -m "feat(addon): a tela de detalhe mostra o nome do addon, com o id como reserva"
```

**Fim da Grupo 4.** O multi-addon está inteiro por dentro: cada fonte diz de onde veio, a ordem do usuário decide o desempate, e a tela fala o nome que ele deu. O que não existe ainda é a tela onde ele instala, arrasta e remove, nem a tela de contas com o aviso do cofre em texto puro. É a Grupo 5.

| Task | Novos | Acumulado |
| --- | --- | --- |
| 15, o id do addon na grade e no lote | 3 | 494 |
| 16, a prioridade chega nas telas | 3 | 497 |
| 17, o nome do addon na tela | 4 | 501 |

---

## Grupo 5: as telas

Tudo que a seção 9 do spec de UI pede existe por dentro e não tem porta. O usuário não consegue instalar um addon que não seja o embutido, não consegue arrastar a ordem que `sourcePriorityProvider` deriva, não consegue digitar o token de um addon de terceiro, não vê as contas que tem num lugar só, e não recebe o aviso de que o cofre caiu para texto puro. Esta grupo é o que transforma dezessete Tasks de encanamento em software que alguém usa.

A ordem tem um critério, e é o de **não entregar elemento de UI morto**: cada Task deixa a tela que ela criou inteiramente ligada antes de a seguinte começar. Por isso o serviço de instalação vem antes da tela de detalhe, a tela de detalhe vem antes da lista que a abre, e as portas de entrada vêm por último, quando já existe para onde mandar o usuário. O Accounts consolidado fecha a grupo porque ele reúne o que as Tasks anteriores espalharam: sem a lista de addons e sem o formulário por par, não haveria o que reunir.

Antes das telas vêm duas Tasks sem pixel nenhum, pelo mesmo motivo de sempre: o que dá para testar como função pura não vai para dentro de widget. A Task 18 tira do catálogo fundido as três perguntas que as telas fazem, e a Task 19 fecha a última metade do cofre, que é o token deixar de ser por console e passar a ser por par (addon, console).

**O que esta grupo não faz, e está escrito para não ser descoberto na revisão:** a seção 9 pede, na Cobertura, "quais consoles ele atende **e quantos itens em cada**". A contagem de itens por console só existe depois de `loadCatalog`, que é rede por url. Desenhá-la na tela de detalhe significaria buscar N catálogos ao abrir a tela de um addon. Fica de fora, com a Cobertura mostrando os consoles e não a contagem, e a varredura da Grupo 6 lista isso como lacuna conhecida em vez de dizer que a seção 9 está cumprida.

---

### Task 18: as três perguntas que as telas fazem ao catálogo

**Files:**
- Modify: `lib/models/console_model.dart:55-59` (o getter vira uma chamada)
- Modify: `lib/services/console_merge.dart` (ganha `authForAddon`, `AddonCoverage` e `MergedCatalog.coverage`)
- Modify: `lib/providers/addon_provider.dart` (ganha `addonCoverageProvider`)
- Test: `test/addon_coverage_test.dart`

Três perguntas, e nenhuma delas tem resposta hoje:

1. **"esta fonte pede conta?"** `Console.hasTokenAuth` responde pelo console, e desde a Grupo 3 a auth que importa é a da fonte: com dois addons servindo o mesmo console, `Console.auth` é a do primeiro que o declarou. Quem tem um `ConsoleSource` em mãos não tem `Console` para chamar o getter.
2. **"com que auth este addon fala neste console?"** É o que falta para o `download_provider` da Task 19 parar de mandar o cookie de um servidor para o outro.
3. **"o que este addon cobre?"** É o `"25 consoles"` e o chip de conta da linha da seção 9.

As três são funções puras sobre dado que a fusão já tem. Escrever isso dentro das telas seria transformar regra testável em teste de widget.

O arquivo de teste é novo, `test/addon_coverage_test.dart`, por dois motivos: não existe arquivo de teste do modelo `Console` no repositório (`ls test/` não tem nenhum), e `test/console_merge_test.dart` já existe desde a Task 10 com os onze casos da fusão, que são sobre outra coisa.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/addon_coverage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {Map<String, dynamic>? auth}) =>
    Console(id: id, name: id.toUpperCase(), urls: urls, auth: auth);

AddonCatalog _catalogo(String addonId, Map<String, Console> consoles) => (addonId: addonId, consoles: consoles);

void main() {
  group('authNeedsToken', () {
    test('console sem bloco de auth não pede token', () {
      expect(authNeedsToken(null), isFalse);
    });

    test('a marca que a colheita deixou basta', () {
      // `requires_token` é o que a Task 8 grava no lugar do token que tira do
      // arquivo compartilhável. Sem este caso, um catálogo privado instalado
      // perderia justamente a tela onde o usuário digitaria o token dele.
      expect(authNeedsToken(const {'requires_token': true}), isTrue);
    });

    test('o campo cru do catálogo ainda conta', () {
      // O embutido nunca passou pela colheita, e um arquivo que o usuário
      // abriu na mão também não.
      expect(authNeedsToken(const {'token': 'tok'}), isTrue);
    });

    test('só a mensagem de login já conta', () {
      expect(authNeedsToken(const {'auth_message': 'Peça convite no fórum.'}), isTrue);
    });

    test('ia_s3 não pede token, nem com a marca', () {
      // O Internet Archive assina de outro jeito e tem tela própria em
      // Accounts. Um campo de token aqui seria campo que não autentica nada.
      expect(authNeedsToken(const {'type': 'ia_s3', 'requires_token': true}), isFalse);
    });

    test('auth que não fala de token não pede token', () {
      expect(authNeedsToken(const {'cookies': true, 'cookie_name': 'sess'}), isFalse);
    });

    test('hasTokenAuth é a função, e não uma segunda regra', () {
      // O caso que impede a volta da duplicação: se alguém mexer num dos dois
      // lugares, este expect para de valer.
      const auth = {'requires_token': true};
      expect(_console('snes', const ['https://a/'], auth: auth).hasTokenAuth, authNeedsToken(auth));
      expect(_console('snes', const ['https://a/']).hasTokenAuth, authNeedsToken(null));
    });
  });

  group('authForAddon', () {
    final fundido = mergeCatalogs([
      _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      _catalogo('ultranx', {
        'snes': _console('snes', const ['https://ultranx/snes/'], auth: const {'token': 'tok', 'cookies': true}),
      }),
    ]);

    test('devolve a auth da fonte do addon pedido', () {
      expect(authForAddon(fundido.sources['snes']!, 'ultranx'), {'token': 'tok', 'cookies': true});
    });

    test('addon que não serve este console devolve null', () {
      expect(authForAddon(fundido.sources['snes']!, 'arquivo-do-fulano'), isNull);
    });

    test('addon que serve sem declarar auth também devolve null', () {
      // As duas ausências viram o mesmo `null` de propósito: quem lê faz a
      // mesma coisa nos dois casos, que é não mandar header nenhum.
      expect(authForAddon(fundido.sources['snes']!, 'myrient'), isNull);
    });

    test('entre duas fontes do mesmo addon, a primeira manda', () {
      // Não sai da fusão, que dá a mesma auth a todas as urls de um console
      // num mesmo catálogo. A regra fica fixada porque `coverage` depende dela
      // para concordar com esta função.
      const lista = [
        ConsoleSource(addonId: 'a', url: 'https://um/', auth: {'token': 'primeiro'}),
        ConsoleSource(addonId: 'a', url: 'https://dois/', auth: {'token': 'segundo'}),
      ];

      expect(authForAddon(lista, 'a'), {'token': 'primeiro'});
    });
  });

  group('coverage', () {
    test('lista os consoles de cada addon', () {
      final fundido = mergeCatalogs([
        _catalogo('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/']),
          'md': _console('md', const ['https://myrient/md/']),
        }),
        _catalogo('ultranx', {'switch': _console('switch', const ['https://ultranx/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes', 'md']);
      expect(fundido.coverage()['ultranx']!.consoles, ['switch']);
    });

    test('console servido por dois addons conta para os dois', () {
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalogo('fulano', {'snes': _console('snes', const ['https://fulano/snes/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes']);
      expect(fundido.coverage()['fulano']!.consoles, ['snes']);
    });

    test('duas urls do mesmo addon no mesmo console contam um console só', () {
      // A linha da seção 9 diz "25 consoles", não "25 urls". Um espelho a mais
      // não deixa a fonte maior.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/', 'https://espelho/snes/']),
        }),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes']);
    });

    test('authConsoles traz só os consoles que pedem conta', () {
      final fundido = mergeCatalogs([
        _catalogo('ultranx', {
          'switch': _console('switch', const ['https://ultranx/switch/'], auth: const {'requires_token': true}),
          'wiiu': _console('wiiu', const ['https://ultranx/wiiu/']),
        }),
      ]);

      final cobertura = fundido.coverage()['ultranx']!;

      expect(cobertura.consoles, ['switch', 'wiiu']);
      expect(cobertura.authConsoles, ['switch']);
    });

    test('addon sem conta em console nenhum tem authConsoles vazio', () {
      // É este vazio que apaga o chip de conta da linha, e ele precisa ser
      // lista vazia e não `null`: a tela pergunta `isNotEmpty`.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.authConsoles, isEmpty);
    });

    test('addon que não serve nenhum console não aparece no mapa', () {
      // O caso do addon recém instalado cujo catálogo ainda não foi lido, e o
      // do addon cuja url morreu. Quem desenha a linha trata ausente como
      // zero, e é por isso que a tela da Task 23 usa
      // `?? (consoles: const <String>[], authConsoles: const <String>[])` em
      // vez de `!`.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalogo('vazio', const {}),
      ]);

      expect(fundido.coverage().containsKey('vazio'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_coverage_test.dart
```

Esperado: erro de compilação, `Undefined name 'authNeedsToken'`.

- [ ] **Step 3: A regra do token sai do getter**

Em `lib/models/console_model.dart`, **acima** da declaração `class Console {` da linha 1, acrescente a função de topo:

```dart
/// Se este bloco de `auth` diz que o console pede um token do usuário.
///
/// Existe como função de topo, e não só como getter, porque desde a Grupo 3 a
/// auth que importa é a da **fonte** (`ConsoleSource.auth`) e não a do
/// `Console`: com dois addons servindo o mesmo console, `Console.auth` é a do
/// primeiro que o declarou. Quem tem uma fonte em mãos não tem um `Console`
/// para chamar o getter.
///
/// `requires_token` é a marca que a colheita da instalação deixa no lugar do
/// token que tirou (`CatalogService.harvestAuthTokens`). Os outros dois termos
/// continuam valendo para o catálogo embutido, que nunca passou pela colheita,
/// e para arquivo aberto na mão.
bool authNeedsToken(Map<String, dynamic>? auth) {
  if (auth == null) return false;
  // O Internet Archive assina de outro jeito, e a conta dele é gerida pelo
  // fluxo de login próprio, em Accounts. Sai antes dos outros três termos de
  // propósito: um item do IA colhido com token continua não pedindo campo de
  // token na tela.
  if (auth['type'] == 'ia_s3') return false;
  return auth['requires_token'] == true || auth.containsKey('token') || auth.containsKey('auth_message');
}
```

e troque o getter inteiro das linhas 55 a 59 por:

```dart
  /// True when this console uses a user-editable bearer/cookie token for auth.
  /// IA S3 auth is managed separately via the Internet Archive login flow.
  bool get hasTokenAuth => authNeedsToken(auth);
```

**Tropeço provável:** copiar a regra para a função e deixar o corpo antigo no getter, "para não mexer no que funciona". Fica igual hoje e diverge no primeiro dia em que alguém corrigir um dos dois. O caso `'hasTokenAuth é a função, e não uma segunda regra'` existe para pegar isso, e ele passa com a duplicação: o que ele fixa é que os dois concordam, e o que impede a divergência é a delegação. Delegue.

- [ ] **Step 4: A auth por addon e a cobertura**

Em `lib/services/console_merge.dart`, logo depois do `typedef AddonCatalog`, acrescente:

```dart
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
```

e, dentro de `MergedCatalog`, logo depois de `isEmpty`:

```dart
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
```

**Tropeço provável:** deduplicar o addon com um `Set` por fora do laço dos consoles, em vez de um por console. Assim o addon entraria uma vez no mapa inteiro e a cobertura dele viraria sempre `["snes"]`, o primeiro console que ele servisse. O `vistos` nasce dentro do laço de `sources.entries`, e é por isso.

- [ ] **Step 5: O provider que as telas sobrescrevem**

Em `lib/providers/addon_provider.dart`, logo depois de `addonNamesProvider`:

```dart
/// A cobertura de cada addon, recalculada toda vez que a lista muda.
///
/// `ref.watch(addonProvider)` está ali pelo efeito e não pelo valor: a fusão
/// mora dentro do `CatalogService`, e é ela que muda quando o usuário instala,
/// remove ou arrasta.
///
/// **Sem teste, e de propósito.** `mergedCatalog()` chega em disco por
/// `path_provider`, que num teste sem plataforma não falha: ele devolve vazio
/// em silêncio. Um teste aqui afirmaria cobertura zero e passaria para sempre,
/// inclusive depois de a regra quebrar. O que tem teste é
/// `MergedCatalog.coverage()`, que é onde a regra mora. As telas das Tasks 22
/// e 23 sobrescrevem este provider.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  ref.watch(addonProvider);
  return (await CatalogService().mergedCatalog()).coverage();
});
```

com o import novo:

```dart
import 'package:roms_downloader/services/console_merge.dart';
```

- [ ] **Step 6: Rode para ver passar**

```bash
flutter test test/addon_coverage_test.dart
```

Esperado: `+17`, zero falha.

- [ ] **Step 7: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+518`, zero falha.

- [ ] **Step 8: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/addon_coverage_test.dart
git commit -m "test(addon): auth por fonte e cobertura por addon sobre o catalogo fundido"
git add lib/models/console_model.dart lib/services/console_merge.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): auth por fonte e cobertura por addon sobre o catalogo fundido"
```

---

### Task 19: o token deixa de ser do console e passa a ser do par (addon, console)

**Files:**
- Modify: `lib/services/settings_service.dart` (`clearConsoleToken` vira `writeAddonToken`, mais `readAddonToken`)
- Modify: `lib/providers/settings_provider.dart` (`ready`, `setAddonToken`, `readAddonToken`, `setConsoleAuthToken` delega)
- Modify: `lib/utils/console_auth.dart` (ganha `addonsThatNeedToken`)
- Modify: `lib/providers/download_provider.dart:429-441`
- Modify: `lib/services/task_queue_service.dart:14-24`
- Modify: `test/settings_service_test.dart` (um caso muda de método, e a contagem do arquivo não muda)
- Test: `test/addon_token_test.dart`

A Task 13 já fez o **catálogo** buscar cada url com o token do addon dono dela. Sobraram dois caminhos falando de token por console: o download de um arquivo (`download_provider.dart:434`) e o bloqueio do lote (`task_queue_service.dart:18-24`). Os dois ainda leem `settings.consoleSettings[consoleId].authToken`, que é o espelho do embutido. Com dois addons no mesmo console, o primeiro manda o token do embutido para o servidor do terceiro, e o segundo bloqueia o lote inteiro por uma conta que talvez nem seja a da fonte de onde o jogo veio.

Duas decisões dentro desta Task valem mais lidas antes do código.

**O espelho fica, e fica só para o embutido.** Seria tentador hidratar todo token de addon dentro de `AppSettings.consoleSettings` e deixar todo mundo lendo dali, síncrono. Não dá, por duas razões independentes. A primeira é de contrato: `SecretVault` não enumera, não tem `readAll`, e isso é de propósito (Task 2), então o app não consegue descobrir para quais pares existe segredo sem já saber a lista. A segunda é de segurança: `consoleHasToken` e os dois `_authHeaders` de LAN leem esse espelho de forma síncrona e sem saber de addon, então um token de terceiro espelhado ali sairia pelo servidor do Tinfoil como se fosse do embutido. Quem precisa de token de terceiro lê sob demanda, no cofre.

**O bloqueio do lote passa a ser por fonte.** Hoje é `console.hasTokenAuth`, uma pergunta sobre o console. Um console servido por um addon aberto e por um privado bloquearia o download do arquivo aberto por causa da conta do privado. A regra nova pergunta quais dos addons que serviram **estes jogos** pedem token, e cobra só desses.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/addon_token_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/utils/console_auth.dart';

/// Container com o `settingsProvider` de verdade sobre um cofre de mentira.
///
/// O `app_settings` entra semeado com `{}` de propósito. Sem a chave,
/// `loadSettings` cai no ramo padrão, que chama
/// `DirectoryService.getDownloadDir`, que em Android pergunta permissão por
/// plugin e num teste sem plataforma não responde. Com a chave, a carga segue
/// o caminho normal e `AppSettings.fromJson({})` devolve os padrões.
Future<({ProviderContainer container, MemoryVault vault})> _montar() async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final vault = MemoryVault();
  final container = ProviderContainer(overrides: [
    vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
  ]);
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).ready;
  return (container: container, vault: vault);
}

Game _game(String title, {required String sourceId}) => Game(
      title: title,
      url: 'https://exemplo.org/snes/$title',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );

ConsoleSource _fonte(String addonId, {Map<String, dynamic>? auth}) =>
    ConsoleSource(addonId: addonId, url: 'https://$addonId/snes/', auth: auth);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAddonToken e readAddonToken', () {
    test('grava o token na chave do par (addon, console)', () async {
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok');
      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), 'tok');
    });

    test('ler o que nunca foi gravado devolve vazio, e não null', () async {
      // Vazio e não `null` porque todo chamador pergunta `isEmpty`. O cofre
      // devolve `null`, e é aqui que a tradução acontece, uma vez só.
      final m = await _montar();

      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), '');
    });

    test('token vazio apaga a chave', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken('ultranx', 'snes', 'tok');

      await notifier.setAddonToken('ultranx', 'snes', '');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    });

    test('o token do embutido espelha nas settings', () async {
      // O espelho é o que mantém de pé `consoleHasToken` e os dois
      // `_authHeaders` de LAN, que leem síncrono e não sabem de addon.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });

    test('o token de um addon de terceiro não espelha nas settings', () async {
      // O caso que faz esta Task ser sobre segurança. Se espelhasse, o
      // servidor do Tinfoil mandaria a credencial do UltraNX para o servidor
      // do embutido, porque ele lê o espelho sem perguntar de qual addon é.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
    });

    test('apagar o token do embutido limpa o espelho', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      await notifier.setAddonToken(kBuiltinAddonId, 'snes', '');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), isNull);
    });

    test('dois addons no mesmo console guardam tokens separados', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);

      await notifier.setAddonToken('ultranx', 'snes', 'tok-ultranx');
      await notifier.setAddonToken('fulano', 'snes', 'tok-fulano');

      expect(await notifier.readAddonToken('ultranx', 'snes'), 'tok-ultranx');
      expect(await notifier.readAddonToken('fulano', 'snes'), 'tok-fulano');
    });

    test('setConsoleAuthToken é o caso particular do embutido', () async {
      // Quatro telas ainda chamam o nome antigo. Ele não pode virar outra
      // coisa por baixo.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setConsoleAuthToken('snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), 'tok');
      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });
  });

  group('addonsThatNeedToken', () {
    test('addon cuja fonte pede token entra', () {
      final pedem = addonsThatNeedToken(
        [_game('Xenoblade.nsp', sourceId: 'ultranx')],
        [_fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, ['ultranx']);
    });

    test('addon cuja fonte não pede token fica fora', () {
      final pedem = addonsThatNeedToken(
        [_game('Chrono Trigger.zip', sourceId: 'myrient')],
        [_fonte('myrient')],
      );

      expect(pedem, isEmpty);
    });

    test('a conta de um addon não bloqueia o download do outro', () {
      // O motivo de a pergunta ser por fonte. O console é servido pelos dois, e
      // o lote só tem arquivo do aberto: cobrar a conta do privado aqui seria
      // impedir um download que não precisa dela.
      final pedem = addonsThatNeedToken(
        [_game('Chrono Trigger.zip', sourceId: 'myrient')],
        [_fonte('myrient'), _fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, isEmpty);
    });

    test('jogo de addon que não serve mais este console fica fora', () {
      // Cache de um addon removido. Bloquear por causa dele seria cobrar conta
      // de uma fonte que não existe mais, e o usuário não teria onde digitar.
      final pedem = addonsThatNeedToken(
        [_game('Xenoblade.nsp', sourceId: 'removido')],
        [_fonte('myrient')],
      );

      expect(pedem, isEmpty);
    });

    test('cada addon entra uma vez, mesmo com muitos jogos', () {
      final pedem = addonsThatNeedToken(
        [
          _game('Xenoblade.nsp', sourceId: 'ultranx'),
          _game('Zelda.nsp', sourceId: 'ultranx'),
          _game('Mario.nsp', sourceId: 'ultranx'),
        ],
        [_fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, ['ultranx']);
    });
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_token_test.dart
```

Esperado: erro de compilação, `The method 'setAddonToken' isn't defined`.

- [ ] **Step 3: O serviço passa a saber gravar, e não só apagar**

Em `lib/services/settings_service.dart`, troque o método `clearConsoleToken` inteiro por:

```dart
  /// O token de um par (addon, console) no cofre. Valor vazio **apaga**.
  ///
  /// Era `clearConsoleToken(consoleId, vault)`, que sabia apagar e não sabia
  /// gravar, e que assumia o embutido. O addon vira parâmetro porque dois
  /// addons servindo o mesmo console têm tokens diferentes, e misturá-los é
  /// mandar a credencial de um servidor para o outro.
  ///
  /// Continua morando nesta classe, e não no notifier, porque ela é a única
  /// dona do formato da chave: [_hydrate] e [_writeSecrets] leem e escrevem a
  /// mesma `SecretRef.addonToken`.
  Future<void> writeAddonToken(String addonId, String consoleId, String token, SecretVault vault) async {
    final chave = SecretRef.addonToken(addonId, consoleId);
    if (token.isEmpty) return vault.delete(chave);
    return vault.write(chave, token);
  }

  /// O token do par, ou string vazia. A tradução de `null` para `''` acontece
  /// aqui, uma vez só, porque todo chamador pergunta `isEmpty`.
  Future<String> readAddonToken(String addonId, String consoleId, SecretVault vault) async =>
      await vault.read(SecretRef.addonToken(addonId, consoleId)) ?? '';
```

e no doc de `_writeSecrets`, troque a frase

```dart
  /// um clique apressado no boot em perda de todas as credenciais, sem erro na
  /// tela. Quem apaga são [clearIaSecrets] e [clearConsoleToken], chamados de
  /// propósito.
```

por

```dart
  /// um clique apressado no boot em perda de todas as credenciais, sem erro na
  /// tela. Quem apaga são [clearIaSecrets] e [writeAddonToken] com valor
  /// vazio, chamados de propósito.
```

- [ ] **Step 4: Reaponte o caso de teste da Task 6**

O caso `'apagar o token de um console não leva o do vizinho'`, em `test/settings_service_test.dart`, chama o método que acabou de sumir. Ele continua sendo o mesmo caso, com o mesmo valor: troque a linha

```dart
    await SettingsService().clearConsoleToken('snes', vault);
```

por

```dart
    await SettingsService().writeAddonToken(kBuiltinAddonId, 'snes', '', vault);
```

A contagem do arquivo **não muda**. Se você se pegar acrescentando um caso aqui, pare: o par (addon, console) tem cobertura própria em `test/addon_token_test.dart`, e um caso a mais aqui empurraria o acumulado de todas as Tasks seguintes.

- [ ] **Step 5: O notifier ganha `ready` e os dois métodos por addon**

Em `lib/providers/settings_provider.dart`, o topo da classe passa a ser:

```dart
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _settingsService = SettingsService();
  final Future<SecretVault> _vault;

  /// Resolve quando a carga inicial chegou do prefs e do cofre.
  ///
  /// Existe pelo teste, e não é enfeite: sem ela, um teste que leia o estado
  /// logo depois de construir o container lê `const AppSettings()` e passa por
  /// acidente, inclusive depois de a carga quebrar. Mesma saída do
  /// `AddonNotifier.ready` da Task 14.
  late final Future<void> ready;

  SettingsNotifier(this._vault) : super(const AppSettings()) {
    ready = _loadSettings();
  }
```

e o `setConsoleAuthToken` da Task 6 é substituído por três membros:

```dart
  /// Guarda, ou apaga, o token de um par (addon, console).
  ///
  /// **O espelho em `AppSettings.consoleSettings` só é mexido para o addon
  /// embutido, e isso não é economia.** `consoleHasToken` (as duas telas da
  /// Task 7) e os dois `_authHeaders` de LAN leem esse espelho de forma
  /// síncrona e sem saber de addon. Espelhar ali o token de um terceiro faria
  /// o servidor de LAN mandar a credencial de um servidor para outro, que é o
  /// vazamento que a Task 13 acabou de fechar.
  ///
  /// O token de terceiro mora só no cofre. Ele não pode ser hidratado em
  /// `AppSettings` porque `SecretVault` não enumera: não existe `readAll`, de
  /// propósito (Task 2), então o app não descobre para quais pares existe
  /// segredo sem já saber a lista. Quem precisa lê sob demanda, por
  /// [readAddonToken].
  Future<void> setAddonToken(String addonId, String consoleId, String token) async {
    await _settingsService.writeAddonToken(addonId, consoleId, token, await _vault);
    if (addonId != kBuiltinAddonId) return;

    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    final updated = token.isEmpty ? current.copyWith(clearAuthToken: true) : current.copyWith(authToken: token);
    await _persist(state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    ));
  }

  Future<String> readAddonToken(String addonId, String consoleId) async =>
      _settingsService.readAddonToken(addonId, consoleId, await _vault);

  /// O caso particular do addon embutido. Continua existindo com este nome
  /// porque quatro telas o chamam.
  Future<void> setConsoleAuthToken(String consoleId, String token) => setAddonToken(kBuiltinAddonId, consoleId, token);
```

com o import novo:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

**Tropeço provável:** deixar `_persist` fora do ramo do terceiro "para salvar de qualquer jeito". `_persist` chama `saveSettings`, que chama `_writeSecrets`, que grava `SecretRef.addonToken(kBuiltinAddonId, id)` para cada console do espelho. Rodar isso depois de gravar um token de terceiro não estraga nada, mas é escrita em disco por nada em toda digitação de token de addon. O `return` antecipado é intencional.

- [ ] **Step 6: A regra do bloqueio vira função pura**

Em `lib/utils/console_auth.dart`, acrescente:

```dart
/// Os addons que serviram [games] e cuja fonte neste console pede token.
///
/// Pura e aqui, e não dentro de `TaskQueueService._downloadBlockReason`,
/// porque aquele método é estático, assíncrono e cheio de `ref`: sem separar,
/// a regra de bloqueio só teria teste através de widget.
///
/// Dois casos que a lista deixa de fora de propósito. Um jogo cujo `sourceId`
/// não está mais entre as fontes do console (cache de addon removido) não
/// bloqueia nada, porque não haveria onde o usuário digitar a conta que
/// faltou. E um addon aberto no mesmo console que um privado não é contagiado
/// pela conta do vizinho: baixar do aberto não precisa dela.
List<String> addonsThatNeedToken(List<Game> games, List<ConsoleSource> sources) {
  final pedem = <String>{};
  final vistos = <String>{};
  for (final fonte in sources) {
    // Primeira fonte de cada addon manda, igual a `authForAddon` e a
    // `MergedCatalog.coverage`. Sem isto, um addon com um espelho sem auth e
    // outro com auth responderia uma coisa aqui e outra na tela.
    if (!vistos.add(fonte.addonId)) continue;
    if (authNeedsToken(fonte.auth)) pedem.add(fonte.addonId);
  }

  return [
    for (final addonId in {for (final game in games) game.sourceId})
      if (pedem.contains(addonId)) addonId,
  ];
}
```

com os imports novos:

```dart
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/console_merge.dart';
```

- [ ] **Step 7: O lote cobra por fonte**

Em `lib/services/task_queue_service.dart`, troque o corpo de `_downloadBlockReason` até o bloco do NSZ (linhas 15 a 25) por:

```dart
    final catalogService = CatalogService();
    final console = (await catalogService.getConsoles())[consoleId];
    if (console == null) return null;

    final settingsNotifier = ref.read(settingsProvider.notifier);

    // Por fonte, e não por console. Um console servido por um addon aberto e
    // por um privado bloquearia o arquivo do aberto por causa da conta do
    // privado, que é conta que aquele download não usa.
    for (final addonId in addonsThatNeedToken(games, await catalogService.sourcesFor(console.id))) {
      if ((await settingsNotifier.readAddonToken(addonId, console.id)).isEmpty) {
        return console.authMessage ?? 'This system requires authentication. Sign in from the system settings first.';
      }
    }
```

O `final settingsNotifier = ref.read(settingsProvider.notifier);` da linha 26 sai, porque agora está acima. O bloco do NSZ continua igual, usando o mesmo `settingsNotifier`. Os imports mudam: entra

```dart
import 'package:roms_downloader/utils/console_auth.dart';
```

e o `import 'package:roms_downloader/providers/settings_provider.dart';` continua, porque é dele que vem `settingsProvider`.

**Tropeço provável:** a mensagem. Ela continua sendo `console.authMessage ?? ...`, exatamente a de hoje, e não nomeia o addon. Nomear seria melhor e custaria trazer `addonNamesProvider` para dentro de um método estático, num commit que é sobre qual conta é cobrada. Fica como está, de propósito.

- [ ] **Step 8: O download usa a auth e o token da fonte do arquivo**

Em `lib/providers/download_provider.dart`, troque o bloco das linhas 429 a 441 por:

```dart
    // Same auth as catalog fetches, agora pela fonte que serviu este arquivo.
    final settings = _ref.read(settingsProvider);
    final catalogService = CatalogService();
    final isIaUrl = game.url.contains('archive.org/download/');
    // A auth é da fonte e não do console: `console.auth` é a do primeiro addon
    // que declarou o console, então usá-la aqui mandaria o cookie de um
    // servidor junto com o token de outro. `null` quando o addon que serviu o
    // arquivo não serve mais este console, e aí não vai header nenhum.
    final auth = authForAddon(await catalogService.sourcesFor(game.consoleId), game.sourceId);
    final token = await _ref.read(settingsProvider.notifier).readAddonToken(game.sourceId, game.consoleId);
    final headers = <String, String>{
      ...buildConsoleAuthHeaders(auth, tokenOverride: token.isEmpty ? null : token),
      // Restricted ("loggedin") IA items only accept session cookies; S3 keys
      // are kept as a fallback for older flows.
      if (isIaUrl && (settings.iaCookies?.isNotEmpty ?? false))
        'Cookie': settings.iaCookies!
      else if (isIaUrl && (settings.iaAccessKey?.isNotEmpty ?? false) && (settings.iaSecretKey?.isNotEmpty ?? false))
        'Authorization': 'LOW ${settings.iaAccessKey}:${settings.iaSecretKey}',
    };
```

com o import novo:

```dart
import 'package:roms_downloader/services/console_merge.dart';
```

Repare que a linha `final console = (await CatalogService().getConsoles())[game.consoleId];` **sai**. Ela só existia para o `console?.auth`, e deixá-la vira `unused_local_variable`, que é um finding a mais no `flutter analyze` e derruba o `22 issues found`.

**Tropeço provável:** manter um `?? console?.auth` como reserva, "para não quebrar cache antigo". Isso desfaz a Task inteira no caso mais perigoso, que é justamente o console com dois addons. Um cache de antes da fatia tem `sourceId == kBuiltinAddonId` (o padrão do `Game.fromJson` da Task 12), e o embutido está nas fontes, então esse caso já funciona. O que sobra sem header é cache de addon **removido**, e para esse a resposta certa é falhar visivelmente, não mandar a credencial do vizinho.

**Este Step não tem teste, e é honesto dizer.** `executeDownload` chega em `CatalogService`, em `background_downloader` e em disco, e um teste aqui exigiria três dublês para afirmar um mapa de headers. O que tem teste é `authForAddon` (Task 18) e `readAddonToken` (esta Task), que são as duas peças. A ligação entre elas é conferida por leitura e pelo `flutter build linux --debug` do Step 11.

- [ ] **Step 9: Rode para ver passar**

```bash
flutter test test/addon_token_test.dart test/settings_service_test.dart
```

Esperado: `+13` no arquivo novo, e o de serviço com a mesma contagem de antes, zero falha nos dois.

- [ ] **Step 10: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+531`, zero falha.

- [ ] **Step 11: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 12: Commit**

```bash
git add test/addon_token_test.dart test/settings_service_test.dart
git commit -m "test(seguranca): token por par addon e console, e bloqueio de lote por fonte"
git add lib/services/settings_service.dart lib/providers/settings_provider.dart lib/utils/console_auth.dart lib/services/task_queue_service.dart lib/providers/download_provider.dart
git commit -m "feat(seguranca): token por par addon e console, e bloqueio de lote por fonte"
```

---

### Task 20: o formulário de conta passa a ser de um addon

**Files:**
- Modify: `lib/widgets/settings/console_auth_setting.dart` (ganha `addonId` e lê do cofre)
- Modify: `lib/widgets/settings/settings_content.dart:158`
- Test: `test/console_auth_setting_test.dart`

`ConsoleAuthSetting` é o formulário que a seção 9 pede dentro do detalhe do addon ("**Conta**: o formulário de credencial"). Ele já existe e já sabe fazer login por usuário e senha, colar token cru, mostrar a mensagem do catálogo e deslogar. O que ele não sabe é de qual addon é o token: ele lê `settingsProvider.consoleSettings[id].authToken`, que depois da Task 19 é o espelho do embutido e mais nada.

A mudança é de fonte de verdade, não de aparência: o token vem do cofre, pelo par (addon, console), e vai para o cofre pelo mesmo par. Como ler do cofre é assíncrono e `initState` não é, o widget ganha um estado de carga. Isso é visível: por um quadro, o formulário mostra uma barra em vez do campo.

O arquivo de teste é novo. Nenhum dos quatro widgets de settings tem teste hoje (`grep -rl "ConsoleAuthSetting" test/` não acha nada), e esta Task é a primeira que dá um a um deles.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/console_auth_setting_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://exemplo.org/snes/'], auth: {'requires_token': true});

/// `Scaffold` porque o widget chama `ScaffoldMessenger` ao salvar, e o
/// `app_settings` semeado com `{}` pelo mesmo motivo do `addon_token_test`:
/// sem a chave a carga cai no ramo que pergunta diretório por plugin.
Widget _host(MemoryVault vault, {String addonId = kBuiltinAddonId}) {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  return ProviderScope(
    overrides: [
      vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Scaffold(body: ConsoleAuthSetting(console: _snes, addonId: addonId)),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  testWidgets('sem token guardado, mostra o campo para digitar', (tester) async {
    await tester.pumpWidget(_host(MemoryVault()));
    await tester.pumpAndSettle();

    expect(find.text('Bearer token'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('com token no cofre, mostra assinado', (tester) async {
    // A leitura é assíncrona, então o estado inicial é carregando e só depois
    // vira "Signed in". Sem o `pumpAndSettle`, este caso passaria a ver o
    // formulário vazio e a afirmar o contrário do que o usuário vê.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('salvar grava na chave do par (addon, console)', (tester) async {
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-ultranx');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok-ultranx');
  });

  testWidgets('o mesmo console em dois addons não divide token', (tester) async {
    // O que esta Task existe para garantir. O usuário tem conta no UltraNX e
    // não tem no embutido, e os dois servem `snes`.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('deslogar apaga a chave do par', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('o token do embutido continua chegando no espelho das settings', (tester) async {
    // O espelho é o que mantém de pé `consoleHasToken` e os `_authHeaders` de
    // LAN. Salvar pela tela tem que continuar alimentando os dois.
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-embutido');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(settingsProvider).consoleSettings['snes']?.authToken, 'tok-embutido');
  });
}
```

**Por que `find.text('Save')` e não `find.widgetWithText(FilledButton, 'Save')`:** `FilledButton.icon` é uma fábrica que devolve `_FilledButtonWithIcon`, e `find.byType` casa por tipo de execução exato (`finders.dart`: `candidate.widget.runtimeType == widgetType`). O finder por tipo acharia zero e o teste morreria em `Bad state: No element` antes de afirmar coisa alguma, que foi exatamente o que manteve `test/rar_decompress_screen_test.dart` vermelho por meses. Tocar no `Text` funciona porque ele está dentro da área de toque do botão.

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/console_auth_setting_test.dart
```

Esperado: erro de compilação, `No named parameter with the name 'addonId'`.

- [ ] **Step 3: O widget passa a ser de um addon**

Em `lib/widgets/settings/console_auth_setting.dart`, o cabeçalho:

```dart
class ConsoleAuthSetting extends ConsumerStatefulWidget {
  final Console console;

  /// De qual addon é esta conta. O mesmo console pode ser servido por dois
  /// addons, com credenciais diferentes, e o formulário é de um deles.
  final String addonId;

  const ConsoleAuthSetting({super.key, required this.console, required this.addonId});
```

o estado ganha dois campos e perde a leitura síncrona:

```dart
class _ConsoleAuthSettingState extends ConsumerState<ConsoleAuthSetting> {
  final TextEditingController _tokenController = TextEditingController();
  final Map<String, TextEditingController> _signinControllers = {};

  /// O que está guardado no cofre agora. Não vem de `settingsProvider`: o
  /// espelho de lá é só do addon embutido (Task 19).
  String _saved = '';
  bool _carregando = true;
  bool _obscure = true;
  bool _dirty = false;
  bool _signingIn = false;

  List<String> get _signinParams => List<String>.from(widget.console.authSignin?['params'] as List? ?? const []);

  @override
  void initState() {
    super.initState();
    for (final param in _signinParams) {
      _signinControllers[param] = TextEditingController();
    }
    _carregarToken();
  }

  /// O cofre é assíncrono e `initState` não é, então o formulário nasce em
  /// estado de carga. Um quadro com barra é melhor que um quadro com o campo
  /// vazio: o campo vazio diz "você não tem conta" para quem tem.
  Future<void> _carregarToken() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(widget.addonId, widget.console.id);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _tokenController.text = token;
      _carregando = false;
    });
  }
```

Repare que `_tokenController` deixou de ser `late final` com texto inicial e virou um controller vazio criado no campo: o texto chega em `_carregarToken`.

Os três métodos que gravam passam pelo par:

```dart
  Future<void> _guardar(String token) async {
    await ref.read(settingsProvider.notifier).setAddonToken(widget.addonId, widget.console.id, token);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _dirty = false;
    });
  }

  Future<void> _signin() async {
    setState(() => _signingIn = true);
    try {
      final token = await signinForToken(
        widget.console.authSignin!,
        {for (final e in _signinControllers.entries) e.key: e.value.text.trim()},
      );
      _tokenController.text = token;
      await _guardar(token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in, token saved.'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    await _guardar(_tokenController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auth token saved.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clear() async {
    _tokenController.clear();
    await _guardar('');
  }
```

O `_save` de hoje chama `setState` **antes** do `if (mounted)`, o que é uma janela para `setState() called after dispose` se o usuário sair da tela durante a gravação. Isso desaparece porque agora quem chama `setState` é `_guardar`, atrás do seu próprio `if (!mounted) return`. Não é escopo desta Task e sai de graça junto.

E o `build` troca as duas primeiras linhas:

```dart
  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final hasToken = _saved.isNotEmpty;
```

O resto do `build` e o `_tokenSection` ficam idênticos.

**Tropeço provável:** deixar o `ref.watch(settingsProvider)` no `build` "porque não custa". Custa: o widget passaria a reconstruir a cada salvamento de qualquer setting, e, pior, alguém leria dali o token de novo daqui a seis meses achando que aquele é o valor vivo. Para addon de terceiro ele é sempre `null`. A linha some.

- [ ] **Step 4: A tela de settings diz de qual addon é**

Em `lib/widgets/settings/settings_content.dart`, linha 158:

```dart
              // O painel de settings de um console é a porta do catálogo
              // embutido. A conta de um addon de terceiro se edita no detalhe
              // dele (Task 22).
              child: ConsoleAuthSetting(console: selectedConsole!, addonId: kBuiltinAddonId),
```

com o import novo:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/console_auth_setting_test.dart
```

Esperado: `+6`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+537`, zero falha.

- [ ] **Step 7: Analise e compile**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 8: Commit**

```bash
git add test/console_auth_setting_test.dart
git commit -m "test(addon): formulario de conta passa a ser do par addon e console"
git add lib/widgets/settings/console_auth_setting.dart lib/widgets/settings/settings_content.dart
git commit -m "feat(addon): formulario de conta passa a ser do par addon e console"
```

---

### Task 21: instalar um addon a partir de uma URL

**Files:**
- Create: `lib/services/addon_install.dart`
- Modify: `lib/services/catalog_service.dart:79` (`_parseConsoles` vira público)
- Test: `test/addon_install_test.dart`

Esta é a porta de entrada da seção 9: "**Adicionar addon**: um campo de URL e um botão". Tudo que ela precisa já existe em pedaços, e nenhum pedaço sabe dos outros. `Addon.idFromUrl` (Task 9) dá a chave estável, `CatalogService.harvestAuthTokens` (Task 8) tira o token do arquivo e põe no cofre, e `AddonNotifier.install` (Task 14) grava o catálogo e a lista. Esta Task é a costura, e ela mora em arquivo próprio porque não é de nenhum dos três: `CatalogService` não conhece `AddonNotifier`, e é bom que continue assim.

A ordem das três chamadas não é gosto, é a metade incondicional da 6.3: **colher antes de validar e antes de instalar**. Se a validação viesse primeiro, um catálogo que falhasse por outro motivo teria passado pelo disco com o token dentro. Como está, nada é escrito enquanto a colheita não devolveu o JSON limpo.

Consequência que vale dizer em voz alta: quando a validação falha **depois** da colheita, o token fica no cofre e o addon não é instalado. Isso é de propósito. O segredo veio do arquivo que o próprio usuário mandou instalar, guardá-lo faz a segunda tentativa não perguntar de novo, e uma entrada de cofre sob um id que não está na lista não é lida por ninguém: quem lê é `SecretRef.addonToken(addonId, consoleId)` a partir de um addon instalado.

A rede entra por parâmetro. `http` não é dependência deste projeto (`grep '^  http:' pubspec.yaml` não acha nada), então `MockClient` não existe aqui e o teste não tem como interceptar um `HttpClient` real. O `CatalogFetcher` injetável é o que torna esta função testável sem subir servidor.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/addon_install_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _catalogoComToken = '''
[{"name": "SNES", "urls": ["https://exemplo.org/snes/"], "auth": {"token": "segredo-do-arquivo"}}]
''';

const _catalogoSemConsole = '[]';

/// Um notifier com store em diretório temporário e sem `path_provider`.
///
/// `invalidarCache` é trocado porque o padrão passa por
/// `getApplicationCacheDirectory`, que num teste sem plataforma lança.
Future<AddonNotifier> _notifier() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_install_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(const []);
  final notifier = AddonNotifier(Future.value(store), invalidarCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baixa, colhe o token e instala o catálogo limpo', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    final addon = await installAddonFromUrl(
      'https://exemplo.org/catalogo.json',
      notifier: notifier,
      vault: vault,
      fetch: (_) async => _catalogoComToken,
    );

    expect(notifier.state.map((a) => a.id), [addon.id]);
    // O token saiu do arquivo e está no cofre sob o par (addon, console). Quem
    // prova que ele saiu do JSON é `catalog_service_test.dart` (Task 8); o que
    // este caso afirma é que a instalação por URL passa pela colheita.
    expect(await vault.read(SecretRef.addonToken(addon.id, 'snes')), 'segredo-do-arquivo');
  });

  test('o id vem de Addon.idFromUrl e o nome vem do host', () async {
    final notifier = await _notifier();

    final addon = await installAddonFromUrl(
      'https://WWW.Exemplo.org/catalogo.json?v=2',
      notifier: notifier,
      vault: MemoryVault(),
      fetch: (_) async => _catalogoComToken,
    );

    expect(addon.id, Addon.idFromUrl('https://exemplo.org/catalogo.json'));
    expect(addon.name, 'exemplo.org');
    expect(addon.url, 'https://WWW.Exemplo.org/catalogo.json?v=2');
  });

  test('reinstalar a mesma fonte por outra forma da url não duplica', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    await installAddonFromUrl('http://www.exemplo.org/catalogo.json/',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogoComToken);
    await installAddonFromUrl('https://exemplo.org/catalogo.json',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogoComToken);

    expect(notifier.state.length, 1);
  });

  test('corpo que não é JSON não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => '<html>login</html>'),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('JSON válido sem nenhum console não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => _catalogoSemConsole),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('erro de rede sobe e não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => throw const HttpException('HTTP 404 fetching catalog')),
      throwsA(isA<HttpException>()),
    );
    expect(notifier.state, isEmpty);
  });
}
```

Repare que o caso do `MemoryVault` não confere o arquivo gravado. Quem prende o formato do JSON limpo é `catalog_service_test.dart`, na Task 8, com nove casos só para isso; repetir a asserção aqui daria a mesma cobertura duas vezes e quebraria nos dois lugares na próxima mudança de formato. O que este arquivo prende é a costura: que a instalação por URL **passa** pela colheita.

- [ ] **Step 2: Rode para ver falhar**

```bash
flutter test test/addon_install_test.dart
```

Esperado: falha de compilação, `Error: Couldn't resolve the package 'roms_downloader/services/addon_install.dart'`.

- [ ] **Step 3: Abra o parser do catálogo**

Em `lib/services/catalog_service.dart`, linha 79, tire o underscore:

```dart
  static Map<String, Console> parseConsoles(String jsonStr) {
```

E troque as três chamadas internas (`catalog_service.dart:41`, `:110`, e a de `buildCatalog` que a Task 13 criou) de `_parseConsoles(` para `parseConsoles(`.

Público de propósito e não copiado: validar um catálogo baixado com um parser diferente do que vai lê-lo depois é como o app aceita na instalação um arquivo que ele não consegue abrir no boot. É o mesmo código ou não vale nada.

```bash
grep -n "_parseConsoles" lib/services/catalog_service.dart
```

Esperado: nenhuma linha.

- [ ] **Step 4: Escreva a instalação**

Crie `lib/services/addon_install.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Como o catálogo chega da rede.
///
/// Entra por parâmetro porque `http` não é dependência deste projeto, então
/// não existe `MockClient` aqui: sem a injeção, testar esta função pediria um
/// servidor de verdade.
typedef CatalogFetcher = Future<String> Function(String url);

/// Baixa o catálogo de [url], guarda os tokens que vierem nele e instala a
/// fonte como um addon.
///
/// A ordem é a metade incondicional da seção 6.3 do spec: colher antes de
/// validar e antes de gravar. Nada toca o disco enquanto
/// [CatalogService.harvestAuthTokens] não devolveu o JSON sem os tokens.
///
/// Quando a validação falha depois da colheita, o segredo fica no cofre e o
/// addon não entra na lista. É de propósito: o token veio do arquivo que o
/// usuário mandou instalar, e uma entrada de cofre sob um id que não está na
/// lista não é lida por ninguém.
///
/// Levanta [FormatException] se o corpo não for um catálogo com pelo menos um
/// console, e o que [fetch] levantar se a rede falhar.
Future<Addon> installAddonFromUrl(
  String url, {
  required AddonNotifier notifier,
  required SecretVault vault,
  CatalogFetcher? fetch,
}) async {
  final body = await (fetch ?? fetchCatalogByHttp)(url);
  final id = Addon.idFromUrl(url);

  final limpo = await CatalogService.harvestAuthTokens(body, vault: vault, addonId: id);
  if (CatalogService.parseConsoles(limpo).isEmpty) {
    throw const FormatException('No consoles found in the provided catalog.');
  }

  final addon = Addon(id: id, name: _nomeDe(url, id), url: url);
  await notifier.install(addon, limpo);
  return addon;
}

/// O nome que aparece na lista de addons: o host, sem `www.`.
///
/// Host e não id porque o id é chave de cofre e nome de arquivo
/// (`myrient_erista_me_files`), e chave é para máquina. Uma url sem host, que
/// `Addon.idFromUrl` aceita, cai no id, que é feio e é melhor que vazio.
String _nomeDe(String url, String id) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return id;
  return host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
}

/// A rede de verdade, igual à de `CatalogService.setCatalogFromUrl`
/// (`catalog_service.dart:121-135`): mesmo teto de 30 segundos para conectar e
/// mesma recusa de qualquer status que não seja 200.
Future<String> fetchCatalogByHttp(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} fetching catalog');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}
```

**Tropeço provável:** passar `body` para `notifier.install` em vez de `limpo`. Os dois compilam, os cinco outros casos passam, e o token volta para o disco, agora num arquivo novo em `config/addons/<id>.json`. O caso que pega isso é o primeiro, e só porque ele lê o cofre depois de instalar; é por isso que ele existe.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_install_test.dart
```

Esperado: `+6`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+543`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, e nenhum deles em `addon_install.dart`, `addon_install_test.dart` ou `catalog_service.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_install_test.dart
git commit -m "test(addon): instalacao de addon por url"
git add lib/services/addon_install.dart lib/services/catalog_service.dart
git commit -m "feat(addon): instalar addon a partir de uma url"
```

---

### Task 22: a tela de detalhe do addon

**Files:**
- Create: `lib/screens/addon_detail_screen.dart`
- Modify: `lib/providers/addon_provider.dart` (ganha `mergedCatalogProvider`, e `addonCoverageProvider` passa a derivar dele)
- Test: `test/addon_detail_screen_test.dart`

A seção 9 pede cinco blocos nesta tela, nesta ordem: identificação, conta, cobertura, prioridade e remover. Quatro deles já têm a resposta pronta em provider: `addonProvider` dá nome, url e posição, `MergedCatalog.coverage()` dá os consoles e quais pedem conta (Task 18), e `ConsoleAuthSetting(console:, addonId:)` é o formulário de conta (Task 20). Esta Task só monta.

**Uma exigência da seção 9 fica de fora, e é melhor dizer isso agora do que descobrir na revisão.** O spec pede "**Cobertura**: quais consoles ele atende **e quantos itens em cada**". A primeira metade entra; a segunda, não. Contar itens de um console é buscar a listagem dele (`_fetchCatalog`, `catalog_service.dart:4016`), uma requisição por console, e o app carrega listagem sob demanda justamente porque ela é cara. Um addon com 25 consoles pagaria 25 requisições ao abrir uma tela de leitura. O que a tela mostra é `"3 consoles"` e a lista deles. A contagem por console fica para quando houver contagem barata, e isso é dívida declarada, não esquecimento.

A mudança em `addon_provider.dart` é para a tela não ler o disco duas vezes. Hoje `addonCoverageProvider` monta o `MergedCatalog` inteiro e devolve só a cobertura, e esta tela também precisa dos `Console` em si, para dar o nome de tela do console e para passar ao formulário de conta. Em vez de um segundo provider que refaz o mesmo trabalho, o fundido vira o provider e a cobertura passa a derivar dele.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/addon_detail_screen_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://outro/ps2/']);

/// Dois addons servindo três consoles: `myrient` serve Switch (com conta) e
/// SNES, `outro` serve PS2. A tela do `myrient` não pode mostrar PS2.
MergedCatalog _catalogo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'outro', url: 'https://outro/ps2/')],
      },
    );

/// Um notifier de verdade, com store em diretório temporário: o caso do
/// "Remover" precisa que a remoção chegue no disco e volte pela lista.
///
/// O `app_settings` semeado com `{}` é pelo mesmo motivo do
/// `console_auth_setting_test`: sem a chave, a carga das settings cai no ramo
/// que pergunta diretório por plugin.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_detail_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  final notifier = AddonNotifier(Future.value(store), invalidarCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

/// Empilha a tela sobre uma home vazia.
///
/// Empilhada e não como `home` porque `Navigator.pop` na rota raiz é no-op: o
/// caso do "Remover" passaria sem provar que a tela fecha.
Future<void> _abrir(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalogo,
  String addonId = 'myrient',
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _catalogo()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addonId)),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o nome e a url de origem', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient.erista.me/catalogo.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('myrient.erista.me'), findsWidgets);
    expect(find.text('https://myrient.erista.me/catalogo.json'), findsOneWidget);
  });

  testWidgets('addon sem url mostra a origem por extenso', (tester) async {
    // O embutido e o catálogo aberto de arquivo não têm endereço. Um campo de
    // url vazio faria a tela parecer quebrada num caso que é normal.
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Catálogo embutido')]);

    await _abrir(tester, notifier: notifier, addonId: kBuiltinAddonId);

    expect(find.text('Catálogo embutido'), findsWidgets);
    expect(find.text('Instalado com o app'), findsOneWidget);
  });

  testWidgets('a cobertura lista só os consoles deste addon', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('Switch'), findsWidgets);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('PS2'), findsNothing);
  });

  testWidgets('addon que ainda não cobre nada mostra zero e não quebra', (tester) async {
    // `MergedCatalog.coverage()` **omite** o addon sem console (Task 18), então
    // este é o caminho do mapa sem a chave, não o da lista vazia. É o estado
    // real de um addon recém instalado cujo catálogo ainda não foi lido.
    final notifier = await _notifier(const [Addon(id: 'novo', name: 'novo.org', url: 'https://novo.org/c.json')]);

    await _abrir(tester, notifier: notifier, addonId: 'novo');

    expect(find.text('Nenhum console'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('só o console que pede conta ganha formulário', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);

    final formularios = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(formularios.length, 1);
    expect(formularios.single.console.id, 'switch');
    // O `addonId` é o que faz o token ser guardado sob o par certo. Passar o
    // embutido aqui compila, a tela funciona, e o token do Myrient vai para a
    // gaveta do catálogo embutido.
    expect(formularios.single.addonId, 'myrient');
  });

  testWidgets('a prioridade mostra a posição na lista', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: kBuiltinAddonId, name: 'Catálogo embutido'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2ª de 3'), findsOneWidget);
  });

  testWidgets('cancelar a remoção não remove', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(notifier.state.length, 1);
    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('confirmar remove e fecha a tela', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    // O rótulo do botão do diálogo é diferente do da tela de propósito: com os
    // dois escritos "Remover", este `tap` acharia dois widgets e o teste
    // morreria em ambiguidade em vez de provar alguma coisa.
    await tester.tap(find.text('Remover addon'));
    await tester.pumpAndSettle();

    expect(notifier.state, isEmpty);
    expect(find.byType(AddonDetailScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_detail_screen_test.dart
```

Esperado: falha de compilação, `Error: Couldn't resolve the package 'roms_downloader/screens/addon_detail_screen.dart'`.

- [ ] **Step 3: O fundido vira provider**

Em `lib/providers/addon_provider.dart`, troque o `addonCoverageProvider` inteiro (o que a Task 18 criou) por dois providers:

```dart
/// O catálogo fundido de todos os addons instalados, na ordem deles.
///
/// **Sem teste, e de propósito.** `mergedCatalog()` chega em disco por
/// `path_provider`, que num teste sem plataforma não falha: devolve vazio em
/// silêncio. Um teste aqui afirmaria catálogo vazio e passaria para sempre,
/// inclusive depois de a regra quebrar. O que tem teste é `mergeCatalogs` e
/// `MergedCatalog.coverage()`, que é onde a regra mora. As telas das Tasks 22,
/// 23 e 25 sobrescrevem este provider.
final mergedCatalogProvider = FutureProvider<MergedCatalog>((ref) async {
  ref.watch(addonProvider);
  return CatalogService().mergedCatalog();
});

/// De cada addon para o que ele cobre.
///
/// Deriva do fundido em vez de montá-lo de novo: a tela de detalhe precisa dos
/// dois, e duas leituras de disco para a mesma resposta é o tipo de custo que
/// ninguém vê até a lista de addons ficar grande.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  return (await ref.watch(mergedCatalogProvider.future)).coverage();
});
```

- [ ] **Step 4: Escreva a tela**

Crie `lib/screens/addon_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

/// Os cinco blocos que a seção 9 do spec de UI pede para um addon:
/// identificação, conta, cobertura, prioridade e remover.
///
/// A cobertura mostra quais consoles o addon atende, e **não** quantos itens
/// em cada. A contagem por console é uma requisição de listagem por console
/// (`CatalogService._fetchCatalog`), e o app carrega listagem sob demanda
/// justamente porque ela é cara: um addon com 25 consoles pagaria 25
/// requisições ao abrir uma tela de leitura.
class AddonDetailScreen extends ConsumerWidget {
  final String addonId;

  const AddonDetailScreen({super.key, required this.addonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final indice = addons.indexWhere((a) => a.id == addonId);

    // A remoção muda a lista antes de o `pop` completar, então este quadro
    // existe de verdade. Sem a guarda, o `addons[indice]` abaixo estoura com
    // índice -1 no caminho feliz do botão Remover.
    if (indice < 0) return const Scaffold(body: SizedBox.shrink());

    final addon = addons[indice];
    final catalogo = ref.watch(mergedCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(addon.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Secao(
            titulo: 'Origem',
            child: Text(addon.url ?? (addon.isBuiltin ? 'Instalado com o app' : 'Instalado de arquivo')),
          ),
          catalogo.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => _Secao(titulo: 'Cobertura', child: Text('Catálogo ilegível: $e')),
            data: (fundido) {
              final cobertura = fundido.coverage()[addonId] ?? (consoles: const <String>[], authConsoles: const <String>[]);
              // Declaração e não `final nome = (String id) => ...`: o
              // `prefer_function_declarations_over_variables` vem ligado no
              // `flutter_lints` e a variável empurraria o analyze para 23.
              String nome(String id) => fundido.consoles[id]?.name ?? id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final consoleId in cobertura.authConsoles)
                    if (fundido.consoles[consoleId] != null)
                      _Secao(
                        titulo: 'Conta: ${nome(consoleId)}',
                        child: ConsoleAuthSetting(console: fundido.consoles[consoleId]!, addonId: addonId),
                      ),
                  _Secao(
                    titulo: 'Cobertura',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cobertura.consoles.isEmpty
                            ? 'Nenhum console'
                            : '${cobertura.consoles.length} console${cobertura.consoles.length == 1 ? '' : 's'}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final id in cobertura.consoles) Chip(label: Text(nome(id)))],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          _Secao(
            titulo: 'Prioridade',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${indice + 1}ª de ${addons.length}'),
                const SizedBox(height: 4),
                Text(
                  'Arraste na lista de addons para mudar a ordem. A primeira fonte que tem o arquivo é a que baixa.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmarRemocao(context, ref, addon),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarRemocao(BuildContext context, WidgetRef ref, Addon addon) async {
    final navigator = Navigator.of(context);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${addon.name}?'),
        // O token fica no cofre de propósito (`AddonNotifier.remove`), e dizer
        // isso aqui é o que impede o usuário de achar que vai ter que
        // redescobrir a credencial para reinstalar.
        content: const Text('O catálogo sai do app. A credencial fica guardada, e reinstalar a mesma fonte volta a encontrá-la.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remover addon')),
        ],
      ),
    );
    if (confirmou != true) return;
    await ref.read(addonProvider.notifier).remove(addon.id);
    navigator.pop();
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _Secao({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
```

**Tropeço provável:** guardar o `Navigator.of(context)` **depois** do `await`. O `use_build_context_synchronously` do `flutter_lints` é `info`, então ele não quebra o build, ele empurra o analyze para 23 e a Task falha no Step 7 por um motivo que parece cosmético. A linha `final navigator = Navigator.of(context);` antes do diálogo é o que evita isso.

**Segundo tropeço:** montar o bloco de conta a partir de `cobertura.consoles` filtrando por `hasTokenAuth` do `Console`. Funciona na maioria dos casos e erra exatamente no que a Grupo 3 consertou: com dois addons servindo o mesmo console, `Console.auth` é a do **primeiro** que o declarou, então a tela do segundo addon mostraria o formulário do primeiro. `authConsoles` vem de `coverage()`, que percorre as fontes, e é por isso que ele existe.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addon_detail_screen_test.dart
```

Esperado: `+8`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+551`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, e nenhum deles em `addon_detail_screen.dart`, `addon_detail_screen_test.dart` ou `addon_provider.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_detail_screen_test.dart
git commit -m "test(addon): tela de detalhe do addon"
git add lib/screens/addon_detail_screen.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): tela de detalhe com origem, conta, cobertura e prioridade"
```

---

### Task 23: a lista de addons, com arrasto e instalação por URL

**Files:**
- Create: `lib/screens/addons_screen.dart`
- Modify: `lib/providers/addon_provider.dart` (ganha `catalogFetcherProvider`)
- Test: `test/addons_screen_test.dart`

A linha que a seção 9 pede: "ícone, nome, cobertura resumida ("25 consoles"), chip de "conta" quando exige credencial, alça de arrasto e seta. No fim, "+ Instalar de URL"". Esta Task é a última peça de UI da fatia, e é onde a prioridade deixa de ser um conceito e vira uma alça que o usuário arrasta.

O arrasto é o ponto. `sourcePriorityProvider` (Task 14) já é a ordem desta lista, e `planFromEntries` (fatia 3) já usa `sourcePriority` como último desempate da seção 6. Nada disso é observável hoje porque a ordem nunca muda. Depois desta Task, arrastar uma linha muda qual fonte baixa o arquivo.

O `catalogFetcherProvider` existe por um motivo de teste e um de produção. De teste: `installAddonFromUrl` só é injetável por parâmetro, e um widget não tem como receber parâmetro de dentro do `onPressed`. De produção: é o único lugar onde a tela toca a rede, então é o único lugar que precisa ser trocado se um dia houver proxy ou cabeçalho próprio.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/addons_screen_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://outro/ps2/']);

const _catalogoBaixado = '''
[{"name": "PS2", "urls": ["https://novo.org/ps2/"]}]
''';

/// `myrient` cobre dois consoles e um deles pede conta; `outro` cobre um e
/// nenhum pede.
MergedCatalog _catalogo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'outro', url: 'https://outro/ps2/')],
      },
    );

/// O fetcher que os casos que não falam de rede usam.
///
/// Função de topo e não literal no `??`: `fetch ?? (_) async => ...` não
/// parseia como se lê, porque o `=>` come o resto da expressão.
Future<String> _fetchPadrao(String url) async => _catalogoBaixado;

Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addons_screen_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  final notifier = AddonNotifier(Future.value(store), invalidarCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

Future<void> _abrir(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalogo,
  CatalogFetcher? fetch,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _catalogo()),
      catalogFetcherProvider.overrideWithValue(fetch ?? _fetchPadrao),
      vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(home: AddonsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Preenche o campo do diálogo de instalação e confirma.
Future<void> _instalar(WidgetTester tester, String url) async {
  await tester.tap(find.text('Instalar de URL'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('Instalar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista os addons na ordem da prioridade', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    final nomes = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(nomes.indexOf('myrient.erista.me'), lessThan(nomes.indexOf('outro.org')));
  });

  testWidgets('cada linha resume a cobertura', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('1 console'), findsOneWidget);
  });

  testWidgets('o chip de conta só aparece em quem exige credencial', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('conta'), findsOneWidget);
  });

  testWidgets('addon sem cobertura não some da lista', (tester) async {
    // `coverage()` omite o addon sem console, e omitir na tela seria pior que
    // mostrar zero: o usuário acabou de instalar uma fonte e ela não aparece,
    // então ele instala de novo.
    final notifier = await _notifier(const [Addon(id: 'novo', name: 'novo.org', url: 'https://novo.org/c.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('novo.org'), findsOneWidget);
    expect(find.text('Nenhum console'), findsOneWidget);
  });

  testWidgets('lista vazia convida a instalar', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier);

    expect(find.text('Nenhum addon instalado.'), findsOneWidget);
    expect(find.text('Instalar de URL'), findsOneWidget);
  });

  testWidgets('tocar na linha abre o detalhe', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('arrastar reordena e a nova ordem persiste', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    // Na alça e não na linha: a linha inteira é um `ListTile` com `onTap` que
    // abre o detalhe, e arrastar por ela abriria a tela em vez de reordenar.
    //
    // Gesto na mão e não `tester.drag`: o `ReorderableDragStartListener` usa
    // `ImmediateMultiDragGestureRecognizer`, que precisa do `moveBy` em um
    // quadro próprio para o reorder começar. Com `drag` o teste passa ou falha
    // conforme o tamanho da linha, que é a pior espécie de teste.
    final alca = find.byIcon(Icons.drag_handle).first;
    final gesto = await tester.startGesture(tester.getCenter(alca));
    await tester.pump(kLongPressTimeout);
    await gesto.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();

    expect(notifier.state.map((a) => a.id), ['outro', 'myrient']);
  });

  testWidgets('instalar de URL acrescenta o addon', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier);
    await _instalar(tester, 'https://novo.org/catalogo.json');

    expect(notifier.state.map((a) => a.id), [Addon.idFromUrl('https://novo.org/catalogo.json')]);
  });

  testWidgets('url que não devolve catálogo mostra o erro e não instala', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier, fetch: (_) async => '<html>login</html>');
    await _instalar(tester, 'https://novo.org/catalogo.json');

    expect(notifier.state, isEmpty);
    expect(find.textContaining('Não deu para instalar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addons_screen_test.dart
```

Esperado: falha de compilação, `Error: Couldn't resolve the package 'roms_downloader/screens/addons_screen.dart'`.

- [ ] **Step 3: A rede vira provider**

Em `lib/providers/addon_provider.dart`, acrescente, depois do `mergedCatalogProvider`:

```dart
/// Como a tela de addons baixa um catálogo.
///
/// Existe porque `installAddonFromUrl` só é injetável por parâmetro e um
/// `onPressed` não recebe parâmetro. Em produção é sempre
/// `fetchCatalogByHttp`; em teste, uma função que devolve uma string.
final catalogFetcherProvider = Provider<CatalogFetcher>((ref) => fetchCatalogByHttp);
```

com o import novo:

```dart
import 'package:roms_downloader/services/addon_install.dart';
```

- [ ] **Step 4: Escreva a tela**

Crie `lib/screens/addons_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// A lista ordenada de fontes, como a seção 9 do spec de UI pede.
///
/// A ordem **é** a prioridade: ela alimenta `sourcePriorityProvider`, que
/// alimenta o `sourcePriority` de `planFromEntries`. Arrastar uma linha aqui
/// muda qual fonte baixa o arquivo.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final cobertura = ref.watch(addonCoverageProvider).valueOrNull ?? const <String, AddonCoverage>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Addons')),
      body: Column(
        children: [
          Expanded(
            child: addons.isEmpty
                ? const Center(child: Text('Nenhum addon instalado.'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: addons.length,
                    onReorder: (from, to) => ref.read(addonProvider.notifier).reorder(from, to),
                    itemBuilder: (context, i) {
                      final addon = addons[i];
                      return _Linha(
                        key: ValueKey(addon.id),
                        indice: i,
                        addon: addon,
                        // Ausente é cobertura zero, não erro: é o estado de um
                        // addon recém instalado cujo catálogo ainda não foi lido.
                        cobertura: cobertura[addon.id] ?? (consoles: const <String>[], authConsoles: const <String>[]),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _dialogoDeInstalacao(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Instalar de URL'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoDeInstalacao(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Instalar de URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Endereço do catálogo', hintText: 'https://exemplo.org/catalogo.json'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Instalar')),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final vault = (await ref.read(vaultProvider.future)).vault;
      await installAddonFromUrl(
        url,
        notifier: ref.read(addonProvider.notifier),
        vault: vault,
        fetch: ref.read(catalogFetcherProvider),
      );
    } catch (e) {
      // Mensagem em vez de stack trace: os dois erros prováveis são url errada
      // e servidor que devolve página de login, e nenhum dos dois é bug.
      messenger.showSnackBar(SnackBar(content: Text('Não deu para instalar: $e')));
    }
  }
}

class _Linha extends StatelessWidget {
  final int indice;
  final Addon addon;
  final AddonCoverage cobertura;

  const _Linha({super.key, required this.indice, required this.addon, required this.cobertura});

  @override
  Widget build(BuildContext context) {
    final n = cobertura.consoles.length;
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text(addon.name),
      subtitle: Row(
        children: [
          Text(n == 0 ? 'Nenhum console' : '$n console${n == 1 ? '' : 's'}'),
          if (cobertura.authConsoles.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('conta'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A alça é o único ponto que arrasta, e por isso
          // `buildDefaultDragHandles` é falso lá em cima: com ele ligado, a
          // linha inteira arrasta e o toque que abre o detalhe vira um arrasto
          // de um pixel.
          ReorderableDragStartListener(index: indice, child: const Icon(Icons.drag_handle)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addon.id)),
      ),
    );
  }
}
```

**Tropeço provável:** deixar `buildDefaultDragHandles` no padrão, que é `true`. A tela fica funcionando e o teste do toque passa, porque em desktop o `ReorderableListView` só põe alça própria em mobile. O que quebra é no celular, onde a linha inteira vira arrastável e o toque que abre o detalhe compete com o arrasto. O par `buildDefaultDragHandles: false` mais `ReorderableDragStartListener` é o que dá as duas coisas em toda plataforma.

**Segundo tropeço:** `ValueKey(i)` em vez de `ValueKey(addon.id)`. O `ReorderableListView` exige chave e o índice satisfaz o requisito, então nada reclama. Só que a chave passa a mudar exatamente quando a lista reordena, que é quando ela precisava ser estável, e a animação troca o conteúdo das linhas erradas.

- [ ] **Step 5: Rode para ver passar**

```bash
flutter test test/addons_screen_test.dart
```

Esperado: `+11`, zero falha.

- [ ] **Step 6: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+560`, zero falha.

- [ ] **Step 7: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, e nenhum deles em `addons_screen.dart`, `addons_screen_test.dart` ou `addon_provider.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addons_screen_test.dart
git commit -m "test(addon): lista de addons com arrasto e instalacao por url"
git add lib/screens/addons_screen.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): lista de addons com prioridade arrastavel"
```

---

### Task 24: as portas para a tela, e o aviso de que o cofre não cifra

**Files:**
- Create: `lib/widgets/settings/vault_warning.dart`
- Modify: `lib/screens/addon_detail_screen.dart` (o aviso entra acima do bloco de conta)
- Modify: `lib/widgets/settings/accounts_setting.dart` (o aviso entra no topo)
- Modify: `lib/screens/menu_screen.dart` (as tiles de Tools viram função de topo e ganham "Addons")
- Test: `test/vault_warning_test.dart` (novo, 5 casos)
- Test: `test/support/fake_addon_store.dart` (novo, ajuda compartilhada, sem `main`)
- Test: `test/menu_grid_test.dart` (existente, +1 caso)

Duas coisas pequenas que fecham o Grupo 5: a tela de addons ainda não é alcançável por ninguém, e a decisão travada do cofre ainda não apareceu em pixel nenhum.

**O aviso é a segunda metade da decisão travada, e é o que impede a fatia de virar maquiagem.** A 6.3 tem dois objetivos e só um é incondicional. Tirar o token do JSON compartilhável fecha em toda plataforma, porque é o arquivo que o usuário manda para outra pessoa, e quem fecha isso é `harvestAuthTokens` (Task 8). Cifrar o segredo **em repouso** é melhor-esforço: num Linux de servidor, sem `gnome-keyring` nem KWallet no D-Bus, `flutter_secure_storage` não abre e `chooseVault` cai no `PrefsVault`, que é texto puro. Nessa máquina o segredo continua onde sempre esteve. O usuário tem que saber disso na tela onde ele digita o segredo, e não num CHANGELOG.

`AsyncLoading` não avisa de propósito. Enquanto a sondagem do chaveiro não voltou, o app não sabe se cifra, e um aviso que pisca em todo boot de máquina que **tem** chaveiro é um aviso que o usuário aprende a ignorar. `AsyncError` avisa: chaveiro que não abriu é exatamente o caso que o aviso existe para contar.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/vault_warning_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

const _aviso = 'As credenciais ficam em texto puro neste aparelho.';

Widget _host(Override cofre, {Widget child = const VaultWarning()}) {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  return ProviderScope(
    overrides: [cofre],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Override _cofre({required bool cifra}) =>
    vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: cifra));

void main() {
  testWidgets('cofre que não cifra avisa', (tester) async {
    await tester.pumpWidget(_host(_cofre(cifra: false)));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsOneWidget);
  });

  testWidgets('cofre que cifra não avisa nada', (tester) async {
    await tester.pumpWidget(_host(_cofre(cifra: true)));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsNothing);
    // Nem um espaço: o aviso ausente não pode deixar buraco no layout da tela
    // de contas, que é onde ele mais aparece.
    expect(tester.getSize(find.byType(VaultWarning)), Size.zero);
  });

  testWidgets('enquanto sonda o chaveiro, não avisa', (tester) async {
    // Um aviso que pisca em todo boot de máquina que tem chaveiro é um aviso
    // que o usuário aprende a ignorar.
    final travado = Completer<VaultChoice>();
    // Sem `const`: `MemoryVault` guarda um mapa mutável e não tem construtor
    // const. E o `complete` no teardown existe para o `Completer` pendurado
    // não deixar o teste vazando um future para sempre.
    addTearDown(() => travado.complete(VaultChoice(MemoryVault(), encryptedAtRest: true)));

    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) => travado.future)));
    await tester.pump();

    expect(find.text(_aviso), findsNothing);
  });

  testWidgets('chaveiro que não abriu avisa', (tester) async {
    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) async => throw StateError('sem D-Bus'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não deu para abrir o chaveiro'), findsOneWidget);
  });

  testWidgets('o detalhe do addon avisa junto do formulário de conta', (tester) async {
    // O aviso tem que estar onde o segredo é digitado. Só em Accounts, ele não
    // alcança quem configura o token pela tela do addon, que é o caminho novo.
    const console = Console(id: 'switch', name: 'Switch', urls: ['https://m/switch/'], auth: {'requires_token': true});
    const fundido = MergedCatalog(
      consoles: {'switch': console},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://m/switch/', auth: {'requires_token': true})],
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _cofre(cifra: false),
        addonProvider.overrideWith((ref) => AddonNotifier(
              Future.value(FakeAddonStore(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://m/c.json')])),
              invalidarCache: () async {},
            )),
        mergedCatalogProvider.overrideWith((ref) async => fundido),
      ],
      child: const MaterialApp(home: AddonDetailScreen(addonId: 'myrient')),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsOneWidget);
  });
}
```

Repare no `FakeAddonStore`: os testes das Tasks 22 e 23 montam um `AddonStore` de verdade em `Directory.systemTemp`, e aqui isso seria cerimônia de dez linhas para um caso que não escreve nada. `test/support/` já existe no repositório, e é lá que ele mora. Crie `test/support/fake_addon_store.dart`:

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

/// Um `AddonStore` que só sabe devolver a lista que recebeu.
///
/// Para casos que leem e não escrevem. Quem exercita gravação usa o store de
/// verdade num diretório temporário, como nas Tasks 22 e 23: um duplo que
/// finge gravar provaria que a tela chamou o método, não que o dado sobreviveu.
class FakeAddonStore implements AddonStore {
  final List<Addon> _addons;

  const FakeAddonStore(this._addons);

  @override
  List<Addon> load() => _addons;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'FakeAddonStore só responde load(). Chamado: ${invocation.memberName}',
      );
}
```

`noSuchMethod` com `implements` é o jeito de não reescrever os seis outros métodos do store, e o `throw` é o que diferencia este duplo de um mock permissivo: se alguém usá-lo num caso que grava, o teste morre dizendo qual método foi chamado, em vez de passar em silêncio.

E acrescente um caso a `test/menu_grid_test.dart`, dentro do `main` existente:

```dart
  testWidgets('as tiles de Tools levam para os Addons', (tester) async {
    final abertas = <Type>[];
    final tiles = toolsTiles((tela) => abertas.add(tela.runtimeType));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MenuGrid(tiles: tiles))));
    await tester.tap(find.text('Addons'));
    await tester.pump();

    expect(abertas, [AddonsScreen]);
  });
```

com os imports novos no topo do arquivo:

```dart
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/screens/menu_screen.dart';
```

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/vault_warning_test.dart test/menu_grid_test.dart
```

Esperado: falha de compilação nos dois, `Couldn't resolve the package 'roms_downloader/widgets/settings/vault_warning.dart'` e `Undefined name 'toolsTiles'`.

- [ ] **Step 3: Escreva o aviso**

Crie `lib/widgets/settings/vault_warning.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/vault_provider.dart';

/// Avisa, onde o segredo é digitado, que este aparelho não tem chaveiro.
///
/// É a segunda metade da seção 6.3 do spec de arquitetura, e a metade que
/// **não** é incondicional. Tirar o token do JSON compartilhável fecha em toda
/// plataforma (`CatalogService.harvestAuthTokens`); cifrar em repouso depende
/// de haver `gnome-keyring` ou KWallet no D-Bus, e num Linux de servidor não
/// há. Nessa máquina o segredo continua em texto puro, e quem digita tem que
/// saber disso na hora de digitar.
///
/// Carregando não avisa: enquanto a sondagem não voltou, o app não sabe se
/// cifra, e um aviso que pisca em todo boot de máquina que tem chaveiro é um
/// aviso que o usuário aprende a ignorar. Erro avisa, e avisa pior que o caso
/// normal, porque aí não há cofre nenhum.
///
/// **O ramo de erro não é o chaveiro falhando.** Chaveiro que não abre é o
/// caminho previsto: a sonda engole a exceção, devolve `false` e a escolha cai
/// para a reserva, o que chega aqui como `data` com `encryptedAtRest: false`. O
/// único jeito de o `error` acontecer é a **reserva** levantar, ou seja
/// `PrefsVault.open()` (`vault_provider.dart:33`, fora de qualquer `try`). Por
/// isso a mensagem fala em cofre e não em chaveiro: culpar o chaveiro aqui
/// mandaria o usuário procurar o problema no lugar errado.
class VaultWarning extends ConsumerWidget {
  const VaultWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texto = ref.watch(vaultProvider).when(
          loading: () => null,
          error: (e, _) => 'Não deu para abrir cofre nenhum, nem o do sistema nem a reserva: $e',
          data: (escolha) => escolha.encryptedAtRest ? null : 'As credenciais ficam em texto puro neste aparelho.',
        );
    if (texto == null) return const SizedBox.shrink();

    final cores = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cores.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_open, size: 20, color: cores.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: TextStyle(color: cores.onErrorContainer)),
                const SizedBox(height: 4),
                Text(
                  'Sem gnome-keyring nem KWallet, o app guarda o segredo como antes. O catálogo que você compartilha continua sem token.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cores.onErrorContainer),
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

A segunda linha do aviso não é enfeite: sem ela, o usuário lê "texto puro" e conclui que o arquivo que ele manda para um amigo tem o token dele dentro. Tem exatamente o contrário, e é a metade que fechou.

- [ ] **Step 4: Ponha o aviso nas duas telas**

Em `lib/screens/addon_detail_screen.dart`, dentro do `data:` do `catalogo.when`, troque o `for` do bloco de conta por um bloco que começa com o aviso:

```dart
                  if (cobertura.authConsoles.isNotEmpty) const VaultWarning(),
                  for (final consoleId in cobertura.authConsoles)
                    if (fundido.consoles[consoleId] != null)
```

O `if` na frente é para o addon que não pede conta nenhuma não ganhar um aviso sobre um segredo que ele não guarda.

E o import:

```dart
import 'package:roms_downloader/widgets/settings/vault_warning.dart';
```

Em `lib/widgets/settings/accounts_setting.dart`, troque o `return ExpansionTile(` por uma coluna com o aviso em cima:

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
```

fechando a coluna depois do `children: const [IaCredentialsSetting()],` do `ExpansionTile`:

```dart
          children: const [IaCredentialsSetting()],
        ),
      ],
    );
```

com o mesmo import.

- [ ] **Step 5: A porta para a tela**

Em `lib/screens/menu_screen.dart`, tire a lista de tiles de Tools de dentro do `build` e ponha como função de topo, acima da classe:

```dart
/// As tiles de Tools, fora do `build` para terem teste.
///
/// [push] entra por parâmetro porque a navegação de dentro do `MenuScreen`
/// depende do `context` dele, e um teste que precisasse desse context teria
/// que montar a tela inteira, com fila de tarefas e tudo.
List<MenuTile> toolsTiles(void Function(Widget tela) push) => [
      MenuTile(label: 'Addons', icon: Icons.extension, accentColor: const Color(0xFF2E7D5B), onTap: () => push(const AddonsScreen())),
      MenuTile(label: 'NSZ Decompress', icon: Icons.unarchive, accentColor: const Color(0xFFE56717), onTap: () => push(const NszDecompressScreen())),
      MenuTile(label: 'Steam Shortcuts', icon: Icons.videogame_asset, accentColor: const Color(0xFF3B6FB5), onTap: () => push(SteamShortcutScreen())),
      MenuTile(label: 'New Catalog Source', icon: Icons.playlist_add, accentColor: const Color(0xFF2E7D5B), onTap: () => push(const AddCatalogSourceScreen())),
      MenuTile(label: 'Collection Clean', icon: Icons.cleaning_services, accentColor: const Color(0xFF9C4DA0), onTap: () => push(const CollectionCleanScreen())),
      MenuTile(label: 'Rar Decompress', icon: Icons.folder_zip, accentColor: const Color(0xFFB4632E), onTap: () => push(const RarDecompressScreen())),
      MenuTile(label: 'M3U Playlists', icon: Icons.playlist_play, accentColor: const Color(0xFF3B6FB5), onTap: () => push(const M3uScreen())),
      MenuTile(label: 'CHD Converter', icon: Icons.compress, accentColor: const Color(0xFF167C80), onTap: () => push(const ChdConvertScreen())),
      MenuTile(label: '3DS → CIA', icon: Icons.sd_card, accentColor: const Color(0xFF9C4DA0), onTap: () => push(const CiaConvertScreen())),
    ];
```

e no `build`, a tile de Tools passa a ser:

```dart
      MenuTile(
        label: 'Tools',
        icon: Icons.build,
        accentColor: const Color(0xFFE56717),
        onTap: () => _push(MenuGridScreen(title: 'Tools', tiles: toolsTiles(_push))),
      ),
```

com o import novo:

```dart
import 'package:roms_downloader/screens/addons_screen.dart';
```

"Addons" em primeiro na lista, e não no fim junto do "New Catalog Source", porque a seção 9 abre dizendo que "instalar addon é a primeira coisa que o usuário faz". As duas portas coexistem, e o spec já aceitou esse custo: a tool monta um console à mão, o "+ Instalar de URL" instala um catálogo pronto.

`_push` tem assinatura `void Function(Widget)`, que é exatamente o que `toolsTiles` pede, então não há adaptador no meio.

- [ ] **Step 6: Rode para ver passar**

```bash
flutter test test/vault_warning_test.dart test/menu_grid_test.dart
```

Esperado: `+7`, zero falha, sendo 5 do arquivo novo e 2 do `menu_grid_test`, que já tinha um.

- [ ] **Step 7: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+566`, zero falha.

- [ ] **Step 8: Analise**

```bash
flutter analyze
flutter build linux --debug
```

Esperado: `22 issues found`, build ok.

- [ ] **Step 9: Commit**

```bash
git add test/vault_warning_test.dart test/support/fake_addon_store.dart test/menu_grid_test.dart
git commit -m "test(cofre): aviso de texto puro e porta para a tela de addons"
git add lib/widgets/settings/vault_warning.dart lib/screens/addon_detail_screen.dart lib/widgets/settings/accounts_setting.dart lib/screens/menu_screen.dart
git commit -m "feat(cofre): avisar quando o segredo fica em texto puro"
```

### Task 25: Accounts vira a visão consolidada

**Files:**
- Modify: `lib/providers/addon_provider.dart` (ganha `addonAccountsProvider`)
- Modify: `lib/widgets/settings/console_auth_setting.dart` (ganha `onSaved`)
- Modify: `lib/widgets/settings/accounts_setting.dart`
- Modify: `lib/widgets/settings/settings_content.dart` (só um comentário)
- Test: `test/accounts_setting_test.dart`

A seção 9 pede isto em letras: "**Accounts** (`accounts_setting.dart`) continua sendo o cofre único e vira a visão consolidada: todas as contas em um lugar, de addon ou não, com o estado de conexão. A mesma credencial é editável pelos dois caminhos, e isso é o custo aceito da decisão."

Sem esta Task, o que a fatia entrega é o contrário: a conta de um addon de terceiro só existe dentro do detalhe daquele addon, e a tela chamada "Accounts" continua mostrando um provedor só, o Internet Archive. O usuário que tem três contas tem que abrir três telas para saber quais estão conectadas.

As três peças já existem. `MergedCatalog.coverage()` diz, por addon, quais consoles pedem conta (Task 18). `addonProvider` dá a ordem e o nome (Task 14). `ConsoleAuthSetting(console:, addonId:)` é o formulário do par (Task 20). Esta Task lista os pares e empilha os formulários.

**O par é a unidade, não o console.** Dois addons servindo o mesmo console aparecem como duas linhas, com o mesmo nome de console e nomes de addon diferentes. É feio de olhar e é o único jeito honesto: são dois segredos, em duas gavetas, e uma linha só faria o usuário logar num e achar que logou nos dois. Um caso de teste prende isso.

**O estado de conexão custa um retorno de chamada, e é por isso que ele existe.** O subtítulo precisa dizer "Conectado" ou "Não conectado", e a única fonte dessa resposta é o cofre, que é assíncrono e que `SecretVault` não enumera de propósito (Task 2). Ler uma vez ao montar resolve a abertura da tela e erra logo depois: o usuário digita o token no formulário de dentro, o formulário grava no cofre, e o subtítulo de fora continua dizendo "Não conectado" em cima de um campo preenchido. Para addon de terceiro nem adianta observar `settingsProvider`, porque `setAddonToken` sai antes de mexer no espelho quando o addon não é o embutido (Task 19). Então `ConsoleAuthSetting` ganha um `onSaved`, e quem desenha o subtítulo relê.

- [ ] **Step 1: Escreva o teste que falha**

Crie `test/accounts_setting_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/accounts_setting.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);

/// Dois addons no **mesmo** console de conta, mais um console sem conta. É o
/// caso que a tela tem que desenhar como duas linhas, e é o caso que uma
/// implementação chaveada por console desenharia como uma.
MergedCatalog _doisNoMesmo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes},
      sources: {
        'switch': [
          ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true}),
          ConsoleSource(addonId: 'outro', url: 'https://outro/switch/', auth: {'requires_token': true}),
        ],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
      },
    );

/// Só o addon embutido, servindo um console que não pede conta.
MergedCatalog _semConta() => const MergedCatalog(
      consoles: {'snes': _snes},
      sources: {
        'snes': [ConsoleSource(addonId: kBuiltinAddonId, url: 'https://myrient/snes/')],
      },
    );

Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('accounts_setting_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  final notifier = AddonNotifier(Future.value(store), invalidarCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

Future<void> _abrir(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalogo,
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _doisNoMesmo()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AccountsSetting())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem addon que peça conta, sobra só o Internet Archive', (tester) async {
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Catálogo embutido')]);

    await _abrir(tester, notifier: notifier, catalogo: _semConta());

    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('cada par (addon, console) que pede conta vira um bloco', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    // Dois blocos, não um: o console é o mesmo e os segredos são dois.
    expect(find.text('myrient.erista.me'), findsOneWidget);
    expect(find.text('outro.org'), findsOneWidget);
    expect(find.textContaining('Switch'), findsNWidgets(2));
    // O SNES não pede conta e não aparece.
    expect(find.textContaining('SNES'), findsNothing);
  });

  testWidgets('a ordem dos blocos é a ordem de prioridade dos addons', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    final titulos = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    expect(titulos.indexOf('outro.org') < titulos.indexOf('myrient.erista.me'), isTrue);
  });

  testWidgets('o formulário de dentro recebe o par certo', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    final formularios = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(formularios.length, 1);
    expect(formularios.single.addonId, 'myrient');
    expect(formularios.single.console.id, 'switch');
  });

  testWidgets('o cofre vazio diz não conectado e o cofre cheio diz conectado', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('outro', 'switch'), 'tok');
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier, vault: vault);

    expect(find.text('Switch: Not connected'), findsOneWidget);
    expect(find.text('Switch: Connected'), findsOneWidget);
  });

  testWidgets('salvar no formulário atualiza o subtítulo sem recarregar a tela', (tester) async {
    final vault = MemoryVault();
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier, vault: vault);
    expect(find.text('Switch: Not connected'), findsOneWidget);

    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tok-novo');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('myrient', 'switch')), 'tok-novo');
    expect(find.text('Switch: Connected'), findsOneWidget);
    expect(find.text('Switch: Not connected'), findsNothing);
  });

  testWidgets('remover o addon tira a conta dele da lista', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);
    expect(find.text('outro.org'), findsOneWidget);

    await notifier.remove('outro');
    await tester.pumpAndSettle();

    expect(find.text('outro.org'), findsNothing);
    expect(find.text('myrient.erista.me'), findsOneWidget);
  });
}
```

O último caso é o que justifica a lista ser derivada e não guardada. `mergedCatalogProvider` já observa `addonProvider` (Task 22), então remover o addon reconstrói a fusão, a fusão reconstrói os pares, e a linha some sozinha. Se alguém trocar o `ref.watch` por um `ref.read`, é este caso que cai.

`'Save'` e `'Not connected'` ficam em inglês porque são os textos que já existem nos widgets (`console_auth_setting.dart` e `accounts_setting.dart`). Esta Task não traduz tela.

- [ ] **Step 2: Rode para ver falhar**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/accounts_setting_test.dart
```

Esperado: compila e falha em seis dos sete casos, com `Expected: exactly one matching candidate / Actual: _TextFinder:<zero widgets>` em cima de `find.text('myrient.erista.me')` e das variações de subtítulo. O teste não cita `addonAccountsProvider` nem `onSaved` de propósito: ele afirma o que a tela mostra, e por isso não precisa esperar a produção existir para compilar.

O **primeiro** caso passa desde já, porque a tela de hoje já mostra só o Internet Archive. Isso é esperado e não é motivo para reescrevê-lo: ele é o caso que garante que a Task não acrescentou bloco onde não há conta, e ele passa antes e depois.

- [ ] **Step 3: Os pares que pedem conta**

Em `lib/providers/addon_provider.dart`, logo depois de `addonCoverageProvider`:

```dart
/// Um par (addon, console) que pede credencial.
///
/// O par é a unidade e não o console: dois addons servindo o mesmo console têm
/// dois segredos, em duas chaves de cofre, e quem desenha uma linha só faz o
/// usuário logar num e achar que logou nos dois.
typedef AddonAccount = ({Addon addon, Console console});

/// Todas as contas de addon, na ordem de prioridade dos addons.
///
/// Derivado, e não guardado: instalar addon, remover addon ou arrastar a lista
/// muda esta resposta, e o `ref.watch` é o que faz a tela de Accounts
/// acompanhar sem ninguém avisar.
final addonAccountsProvider = FutureProvider<List<AddonAccount>>((ref) async {
  final addons = ref.watch(addonProvider);
  final fundido = await ref.watch(mergedCatalogProvider.future);
  final cobertura = fundido.coverage();
  return [
    for (final addon in addons)
      for (final consoleId in cobertura[addon.id]?.authConsoles ?? const <String>[])
        if (fundido.consoles[consoleId] != null) (addon: addon, console: fundido.consoles[consoleId]!),
  ];
});
```

com o import de `console_model.dart`, se ele ainda não estiver no arquivo.

O `if (fundido.consoles[consoleId] != null)` não é paranoia gratuita: `coverage()` monta `authConsoles` a partir de `sources`, e o invariante que amarra `sources` a `consoles` (Task 10) é fixado por teste, não pelo compilador. Um `!` aqui trocaria um bug de fusão por um crash na tela de settings.

- [ ] **Step 4: O formulário avisa quando grava**

Em `lib/widgets/settings/console_auth_setting.dart`, o cabeçalho ganha um campo:

```dart
  /// Chamado depois de o token ir para o cofre, com o valor novo (vazio quando
  /// o usuário deslogou).
  ///
  /// Existe porque quem desenha o estado de conexão **fora** deste formulário
  /// não tem como saber que ele gravou: o cofre não notifica, e para addon de
  /// terceiro `setAddonToken` nem chega a mexer em `settingsProvider`
  /// (Task 19). Opcional, porque os dois outros chamadores desenham o estado
  /// aqui dentro.
  final void Function(String token)? onSaved;

  const ConsoleAuthSetting({super.key, required this.console, required this.addonId, this.onSaved});
```

e `_guardar` avisa no fim, depois do `setState`:

```dart
  Future<void> _guardar(String token) async {
    await ref.read(settingsProvider.notifier).setAddonToken(widget.addonId, widget.console.id, token);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _dirty = false;
    });
    widget.onSaved?.call(token);
  }
```

Os três caminhos que gravam (`_save`, `_signin`, `_clear`) passam por `_guardar`, então um aviso só cobre os três. Pôr o aviso em `_save` daria um subtítulo que acerta no token colado e erra no login por usuário e senha.

- [ ] **Step 5: A tela empilha as contas**

Em `lib/widgets/settings/accounts_setting.dart`, o arquivo inteiro:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/ia_credentials_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// Connected accounts, one accordion per provider. Collapsed once connected so
/// it stays out of the way; opens when the user still needs to log in.
///
/// A visão consolidada da seção 9 do spec de UI: as contas que não são de
/// addon (hoje, o Internet Archive) e uma por par (addon, console) que pede
/// credencial. A mesma credencial é editável aqui e no detalhe do addon, e
/// isso é custo aceito e não descuido.
class AccountsSetting extends ConsumerWidget {
  const AccountsSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(settingsProvider).hasIaCredentials;
    final contas = ref.watch(addonAccountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
          // Rebuild so the status subtitle updates after login/logout.
          key: ValueKey('ia_$loggedIn'),
          initiallyExpanded: false,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          // account_balance is the columned-building glyph — matches the IA logo.
          leading: const Icon(Icons.account_balance),
          title: const Text('Internet Archive'),
          subtitle: Text(loggedIn ? 'Connected' : 'Not connected'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: const [IaCredentialsSetting()],
        ),
        // Carga e erro não desenham nada: esta é uma seção dentro da tela de
        // settings, e uma barra de progresso piscando aqui a cada abertura
        // custa mais do que a espera de um quadro.
        ...contas.maybeWhen(
          data: (lista) => [for (final conta in lista) _ContaDeAddon(conta: conta)],
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

/// Uma conta de addon, com o estado de conexão no subtítulo.
///
/// Tem estado porque o token vem do cofre, que é assíncrono, e porque o
/// formulário de dentro pode gravar enquanto esta linha está montada.
class _ContaDeAddon extends ConsumerStatefulWidget {
  final AddonAccount conta;

  const _ContaDeAddon({required this.conta});

  @override
  ConsumerState<_ContaDeAddon> createState() => _ContaDeAddonState();
}

class _ContaDeAddonState extends ConsumerState<_ContaDeAddon> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(
          widget.conta.addon.id,
          widget.conta.console.id,
        );
    if (!mounted) return;
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.conta.console;
    // Enquanto o cofre não respondeu, o subtítulo é só o nome do console. Não
    // é "Not connected": dizer que não tem conta para quem tem, durante um
    // quadro, é a única das três respostas que é mentira.
    final estado = _token == null ? console.name : '${console.name}: ${_token!.isEmpty ? 'Not connected' : 'Connected'}';

    return ExpansionTile(
      initiallyExpanded: false,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text(widget.conta.addon.name),
      subtitle: Text(estado),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        ConsoleAuthSetting(
          console: console,
          addonId: widget.conta.addon.id,
          onSaved: (token) {
            if (mounted) setState(() => _token = token);
          },
        ),
      ],
    );
  }
}
```

**Tropeço provável:** dar `key: ValueKey(...)` com o token dentro, imitando a linha do Internet Archive. Lá a chave existe para forçar reconstrução quando o `settingsProvider` muda; aqui o `setState` já reconstrói, e uma chave que muda com o token **destrói e remonta** o `ConsoleAuthSetting` no instante em que ele grava, apagando o campo de texto debaixo do dedo do usuário.

- [ ] **Step 6: Ajuste o comentário da tela de settings**

Em `lib/widgets/settings/settings_content.dart`, o comentário da Task 20 ficou incompleto. Troque

```dart
              // O painel de settings de um console é a porta do catálogo
              // embutido. A conta de um addon de terceiro se edita no detalhe
              // dele (Task 22).
```

por

```dart
              // O painel de settings de um console é a porta do catálogo
              // embutido. A conta de um addon de terceiro se edita em Accounts
              // (Task 25) ou no detalhe do addon (Task 22), e as duas gravam na
              // mesma chave de cofre.
```

- [ ] **Step 7: Rode para ver passar**

```bash
flutter test test/accounts_setting_test.dart test/console_auth_setting_test.dart test/addon_detail_screen_test.dart
```

Esperado: `+21`, zero falha, sendo 7 do arquivo novo, 6 do `console_auth_setting_test` e 8 do `addon_detail_screen_test`. Os dois antigos entram na conta porque são os outros dois chamadores de `ConsoleAuthSetting`, e o `onSaved` é opcional justamente para que nenhum dos dois mude: se um deles cair aqui, o parâmetro novo não ficou opcional de verdade.

- [ ] **Step 8: Rode a suíte inteira**

```bash
flutter test
flutter analyze
```

Esperado: `+573`, zero falha, `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/accounts_setting_test.dart
git commit -m "test(accounts): a visao consolidada lista uma conta por par addon e console"
git add lib/providers/addon_provider.dart lib/widgets/settings/console_auth_setting.dart lib/widgets/settings/accounts_setting.dart lib/widgets/settings/settings_content.dart
git commit -m "feat(accounts): reunir as contas de addon na tela de Accounts"
```

---

Fecha o Grupo 5. Oito Tasks, 72 casos novos, e a suíte sai de `+492` para `+564`.

O que o grupo entregou, contra a seção 9 do spec de UI: a lista ordenada com alça de arrasto, o detalhe por addon com origem, conta, cobertura, prioridade e remoção, a instalação por URL, o Accounts consolidado com uma linha por par (addon, console) e o estado de conexão, e o token deixando de ser do console para ser do par. O que ele não entregou, e está declarado na Task 22: a contagem de itens por console na cobertura, que custaria uma requisição de listagem por console ao abrir uma tela de leitura.

| Task | Casos | Acumulado |
| --- | --- | --- |
| 18 | 17 | `+518` |
| 19 | 13 | `+531` |
| 20 | 6 | `+537` |
| 21 | 6 | `+543` |
| 22 | 8 | `+551` |
| 23 | 9 | `+560` |
| 24 | 6 | `+566` |
| 25 | 7 | `+573` |

---

## Grupo 6: o contrato com o RTS, e a varredura da fatia

Duas Tasks. A primeira prende uma coisa que o spec de arquitetura afirma e nenhum teste sustenta: o app é produtor e consumidor do mesmo formato de addon, e esta fatia mexeu no formato. A segunda é o critério de aceitação da fatia inteira.

### Task 26: o RTS continua alimentando o app

**Files:**
- Test: `test/rts_addon_contract_test.dart`

Nenhum arquivo de produção. Esta Task só escreve teste, e é de propósito.

A seção 6.4 do spec de arquitetura diz que o **Retro Tools Server** monta um catálogo de pastas locais e serve em `http://host:porta/consoles.json`, que é exatamente o endereço que a instalação de addon consome. Produtor e consumidor são o mesmo binário. E ela tira a consequência: "qualquer extensão do formato tem que ser emitida pelo RTS também. Se o addon passar a declarar `auth` e o RTS continuar emitindo o formato antigo, o app deixa de conseguir se alimentar".

Esta fatia mexeu no formato: `harvestAuthTokens` tira `auth.token` e põe `requires_token`, a fusão passou a carregar `ConsoleSource` por console, e o id do addon virou chave de cofre. Nada disso quebra o RTS, que nunca emitiu `auth`. O que não existe é um teste que caia no dia em que quebrar, e o custo de escrevê-lo é cinco casos sem uma linha de produção.

`RtsServerService.consoleJson` e `buildConsolesJson` são estáticos e puros (`rts_server_service.dart:13-23`), então o teste liga o produtor no consumidor sem subir servidor.

- [ ] **Step 1: Escreva os testes**

Crie `test/rts_addon_contract_test.dart`:

```dart
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
    // O RTS emite `name` e o consumidor deriva o id com
    // `CatalogService.consoleId(name)`. Se as duas regras divergirem, a pasta
    // compartilhada vira um console com id que nenhuma outra fonte casa, e o
    // MODO PACK para de reconhecer a pasta local como fonte do mesmo jogo.
    for (final pasta in _pastas) {
      expect(CatalogService.parseConsoles(_emitido()).containsKey(CatalogService.consoleId(pasta.name)), isTrue);
    }
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
```

O último caso fixa o id por extenso, e não por `Addon.idFromUrl(...)` dos dois lados, porque uma asserção que chama a mesma função que produziu o valor passa mesmo quando a função está errada. `192_168_0_10_8080_consoles_json` é feio e é o ponto: esse é o nome do arquivo que vai para `config/addons/`, e vê-lo escrito uma vez no teste é o que impede alguém de "melhorar" o slug sem perceber que ele é chave de cofre.

`_pastas` aparece nos três casos de laço de propósito: a lista de pastas é a entrada do produtor, então varrer ela é varrer exatamente o que o RTS emitiu, sem depender de o consumidor ter parseado certo.

- [ ] **Step 2: Rode**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/rts_addon_contract_test.dart
```

Esperado: `+5`, zero falha. **Sem passo de "ver falhar":** esta Task não tem produção, e os cinco casos passam na primeira. Um teste de contrato que já está verde é o normal dele; o valor está em cair quando a próxima fatia mexer no formato.

Se algum cair aqui, **não conserte o teste**. Ele está dizendo que o produtor e o consumidor divergiram nesta fatia, e o conserto é do lado que divergiu.

- [ ] **Step 3: Rode a suíte inteira**

```bash
flutter test
```

Esperado: `+578`, zero falha.

- [ ] **Step 4: Analise**

```bash
flutter analyze
```

Esperado: `22 issues found`, e nenhum deles em `rts_addon_contract_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add test/rts_addon_contract_test.dart
git commit -m "test(rts): contrato entre o servidor que emite catalogo e o app que instala"
```

---

### Task 27: a varredura da fatia

**Files:** nenhum. Esta Task não escreve código: ela mede.

O critério de aceitação da fatia inteira, contra o commit **`ef5ee57`**, que é o HEAD de antes da fatia 4. Esse hash é carga: ele está escrito aqui e em nenhum outro lugar, então nada de rebase, amend ou filter-branch que o alcance enquanto a fatia não fechar.

Um aviso que custou duas medições inteiras numa fatia anterior: **não encadeie `git checkout <ref> && <comando>; git checkout -` numa chamada só.** Para inspecionar histórico, use `git show <ref>:<caminho>` e `git diff <refA> <refB> -- <caminho>`, que não mexem em HEAD.

- [ ] **Step 1: O que a fatia não podia tocar**

```bash
git diff --stat ef5ee57 -- \
  lib/services/tinfoil_server_service.dart \
  lib/services/jdkv_server_service.dart \
  lib/services/rts_server_service.dart \
  lib/services/smb_service.dart \
  lib/services/webdav_server_service.dart \
  lib/services/metadata_pack_service.dart \
  lib/services/pack_matcher.dart \
  lib/models/metadata_pack_model.dart \
  lib/models/pack_index_model.dart
```

Esperado: saída vazia.

Os cinco servidores de arquivo estão aí porque a seção 6.4 diz, em letras: "os outros cinco servidores (Tinfoil, JDKV, FBI, SMB, FTP) são outra categoria: servem **arquivo** para um console ou outro aparelho, não **catálogo** para o app. Nada neste documento os afeta". O `rts_server_service.dart` está aí porque a Task 26 escreveu teste para ele **sem** mudá-lo, e um diff não-vazio aqui quer dizer que alguém consertou o produtor em vez de consertar quem divergiu. O resto é fatia 1, que esta fatia não tinha por que alcançar.

- [ ] **Step 2: O que a fatia tocou em `lib/`**

```bash
git diff --name-only ef5ee57 -- lib/ | sort
```

Esperado: exatamente estes 39 arquivos.

```
lib/models/addon_model.dart
lib/models/console_model.dart
lib/models/game_model.dart
lib/models/secret_ref.dart
lib/models/settings_model.dart
lib/models/source_pick_model.dart
lib/providers/addon_provider.dart
lib/providers/catalog_provider.dart
lib/providers/download_provider.dart
lib/providers/fbi_server_provider.dart
lib/providers/pack_grid_provider.dart
lib/providers/settings_provider.dart
lib/providers/tinfoil_server_provider.dart
lib/providers/vault_provider.dart
lib/screens/addon_detail_screen.dart
lib/screens/addons_screen.dart
lib/screens/game_detail_screen.dart
lib/screens/home_screen.dart
lib/screens/menu_screen.dart
lib/screens/setup_wizard_screen.dart
lib/screens/tinfoil_server_screen.dart
lib/services/addon_install.dart
lib/services/addon_store.dart
lib/services/catalog_service.dart
lib/services/console_merge.dart
lib/services/prefs_vault.dart
lib/services/secret_migration.dart
lib/services/secret_vault.dart
lib/services/secure_storage_vault.dart
lib/services/settings_service.dart
lib/services/source_pick_service.dart
lib/services/task_queue_service.dart
lib/utils/console_auth.dart
lib/utils/network.dart
lib/widgets/settings/accounts_setting.dart
lib/widgets/settings/catalog_source_setting.dart
lib/widgets/settings/console_auth_setting.dart
lib/widgets/settings/settings_content.dart
lib/widgets/settings/vault_warning.dart
```

Confira item por item, não só o total: o número bate por acaso quando um arquivo esperado sumiu e um inesperado entrou. O `39` é derivado desta lista, então uma ressalva de QA que crie arquivo novo atualiza os dois na mesma ação.

- [ ] **Step 3: O que a fatia tocou em `test/`**

```bash
git diff --name-only ef5ee57 -- test/ | sort
```

Esperado: exatamente estes 32 arquivos.

```
test/accounts_setting_test.dart
test/addon_coverage_test.dart
test/addon_detail_screen_test.dart
test/addon_install_test.dart
test/addon_model_test.dart
test/addon_provider_test.dart
test/addon_store_test.dart
test/addon_token_test.dart
test/addons_screen_test.dart
test/catalog_addons_test.dart
test/catalog_auth_token_test.dart
test/console_auth_setting_test.dart
test/console_auth_test.dart
test/console_merge_test.dart
test/game_detail_screen_test.dart
test/game_source_id_test.dart
test/menu_grid_test.dart
test/pack_grid_provider_test.dart
test/pack_grid_test.dart
test/prefs_vault_test.dart
test/rts_addon_contract_test.dart
test/secret_migration_test.dart
test/secret_ref_test.dart
test/secret_vault_test.dart
test/secure_storage_vault_test.dart
test/settings_model_secrets_test.dart
test/settings_service_test.dart
test/source_pick_service_test.dart
test/support/fake_addon_store.dart
test/vault_contract.dart
test/vault_provider_test.dart
test/vault_warning_test.dart
```

Cinco deles são **antigos** e foram modificados, não criados: `test/game_detail_screen_test.dart`, `test/menu_grid_test.dart`, `test/pack_grid_provider_test.dart`, `test/pack_grid_test.dart` e `test/source_pick_service_test.dart`. Qualquer outro arquivo antigo nesta lista é achado, não ruído: quer dizer que a fatia mudou comportamento que ela não declarou mudar. `test/settings_service_test.dart` **não** é antigo: o repositório não tinha teste do `SettingsService` antes desta fatia.

`test/vault_contract.dart` e `test/support/fake_addon_store.dart` não terminam em `_test.dart` de propósito: são ajuda compartilhada e não têm `main`, então o runner não os executa sozinhos.

- [ ] **Step 4: `pubspec`**

```bash
git diff ef5ee57 -- pubspec.yaml
```

Esperado: uma linha acrescentada, `flutter_secure_storage`, e nada mais. `pubspec.lock` muda junto e isso é esperado.

- [ ] **Step 5: Analise**

```bash
flutter analyze
```

Esperado: **`22 issues found`**.

Cuidado com esse número: são **21 `info` e um `warning`**, e o `warning` é o `unnecessary_non_null_assertion` de `test/webdav_server_test.dart:69`, que é pré-existente e não é de arquivo desta fatia. O critério **não** é "zero warning", é: 22 findings, zero `error`, e **zero finding em arquivo tocado pela fatia**. Cruze a saída com as duas listas dos Steps 2 e 3.

- [ ] **Step 6: A suíte**

```bash
flutter test
```

Esperado: `+578`, zero falha.

Não existe mais "a falha de sempre": o único teste vermelho do repositório (`test/rar_decompress_screen_test.dart`) foi consertado em `5d21b14`, antes desta fatia começar. Qualquer falha aqui é regressão.

- [ ] **Step 7: O app compila inteiro**

```bash
flutter build linux --debug
```

Esperado: build ok.

**Isto não é conferência visual, e não adianta fingir que é.** A VM é headless: não tem `DISPLAY` nem `Xvfb`, então `flutter run -d linux` não roda. O build compila o app inteiro e pega regressão de compilação no caminho de GUI, que é a maior parte desta fatia, e não prova nada sobre o que aparece na tela. A tela de addons, o arrasto, o Accounts consolidado e o aviso do cofre ficam conferidos por teste de widget e por leitura. Diga isso no relatório em vez de escrever "conferido visualmente".

- [ ] **Step 8: A varredura da 6.3, e as duas metades separadas**

Esta é a razão de ser da fatia, e é o passo que mais dá vontade de resumir errado.

Primeiro, os sítios que leem o token de dentro do arquivo compartilhável. O grep que acha os quatro **não** é por `buildConsoleAuthHeaders`, que só acha os chamadores dele:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

O `-E` é obrigatório, e se você rodar a versão BRE deste mesmo grep a varredura mente para você: sem `-E` o `\?` vira quantificador e o segundo `?` vira literal, o padrão passa a exigir uma `?` depois de `auth`, e o único dos quatro que escreve `auth['token']` sem `?` é justamente `network.dart:41`, o sítio que a 6.3 lista. Medido antes da Task 7 rodar: BRE achou três, `-E` achou quatro.

Esperado: duas classes de linha, e nenhuma outra. Primeira, dentro de `harvestAuthTokens`, que é quem **tira** o token. Segunda, **o comentário em `lib/utils/network.dart:41`**, que cita `` `?? auth['token']` `` entre crases para registrar o que havia ali antes; é texto, não leitura, e confirmado por inspeção da linha. Qualquer terceira linha é sítio vivo. Os quatro sítios de partida eram `lib/utils/network.dart:41`, `lib/services/task_queue_service.dart:20`, `lib/screens/tinfoil_server_screen.dart:91` e `lib/screens/setup_wizard_screen.dart:392`. Os dois últimos não montavam header: decidiam se o console "tem auth configurada" com `(c.auth?['token'] as String?)?.isNotEmpty ?? false`, e por isso passam despercebidos num grep por `buildConsoleAuthHeaders`. Se eles sobrarem, o app continua dizendo "este console tem auth" com base num campo que ninguém mais lê para autenticar. Não é vazamento, é mentira de interface.

Depois, o arquivo compartilhável em si:

```bash
grep -rn "'token'" lib/services/catalog_service.dart lib/models/settings_model.dart
```

Esperado: só as ocorrências dentro de `harvestAuthTokens`.

E então **escreva o relatório com as duas metades separadas**. Elas não fecharam juntas, e reportar "6.3 corrigida" sem separá-las é maquiagem:

1. **Tirar o token do JSON compartilhável: fechado, incondicional, em toda plataforma.** É o arquivo que o usuário manda para outra pessoa, e `harvestAuthTokens` tira o token dele na instalação, em qualquer sistema operacional, com chaveiro ou sem. Provado pelos casos da Task 8 e pelos greps acima. A metade da **exportação** que a 6.3 também pede não foi feita porque não há o que fazer: o app não exporta catálogo em `ef5ee57`. Diga isso com essas palavras, e não "exportação corrigida".
2. **Cifrar o segredo em repouso: melhor-esforço, e não acontece em toda máquina.** Depende de `flutter_secure_storage` abrir, e no Linux isso exige `gnome-keyring` ou KWallet vivo no D-Bus. Num Linux de servidor não há, `chooseVault` cai no `PrefsVault` e o segredo fica em texto puro, como sempre esteve. O que a fatia entrega nesse caso é o aviso na tela onde o segredo é digitado (Task 24), não a cifra.

Diga em qual dos dois casos **esta** máquina caiu:

```bash
flutter test test/vault_provider_test.dart
```

Os casos da Task 4 dizem o que `chooseVault` faz com um backend que responde e com um que não responde; o que eles não dizem é qual dos dois é o D-Bus desta VM. Se quiser essa resposta, ela vem do app rodando, não da suíte, e numa VM headless ela fica em aberto. Reporte em aberto em vez de supor.

- [ ] **Step 9: O relatório**

Sem commit. O que sai daqui é o texto de fechamento da fatia, e ele tem que conter, nesta ordem: o resultado literal de cada um dos oito Steps, a separação das duas metades da 6.3, a dívida declarada da Task 22 (a cobertura não conta itens por console), e o que ficou conferido só por leitura (a ordem dentro de `invalidateForAddonChange`, na Task 14, e a aparência das duas telas novas e do Accounts refeito).

---
