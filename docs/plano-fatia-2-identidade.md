# Fatia 2, Identidade: plano de implementação

> **Para quem executa:** SUB-SKILL OBRIGATÓRIA: use `superpowers:subagent-driven-development` (recomendado) ou `superpowers:executing-plans` para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Goal:** dar ao app a capacidade de dizer, para um nome de arquivo qualquer vindo de uma fonte remota ou do disco do usuário, qual jogo do metadata pack ele é, e com que grau de certeza.

**Architecture:** três eixos, exatamente como a seção 5 do spec descreve. O eixo de nome é uma porta Dart do `norm`/`canon` do builder mais um matcher em três tiers, e é grátis. O eixo de CRC por HTTP Range lê o diretório central do ZIP remoto em duas requisições e confirma ou corrige o eixo de nome antes de qualquer download. O eixo local aplica a regra "nome primeiro, CRC só na dúvida" da seção 5.7 sobre os arquivos que já estão no disco. Nada disso aparece na tela: a fatia 3 é quem consome.

**Tech Stack:** Dart puro nos utilitários (sem import de Flutter, para poderem rodar em `dart run`), `package:rapidfuzz` para o tier 3, `getCrc32` do `package:archive` que já é dependência, `dart:io HttpClient` com header `Range`, Riverpod para a fiação, `flutter_test` sem mock, injeção por construtor.

---

## Antes de começar: leia estas três coisas

1. **`docs/stremio-de-jogos-design.md`, seção 5 inteira.** Em especial 5.3 (o piso de erro silencioso), 5.5 (o desenho final), 5.7 (o eixo local), 5.8 (as guardas obrigatórias do Range) e 5.9 (os números remedidos). Este plano implementa a seção 5 e nada mais.
2. **`tool/build_metadata_pack.py`, linhas 169 a 219.** São as funções `strip_ext`, `norm`, `display_title` e `canon`. A Task 1 e a Task 2 são a porta Dart delas. Não invente uma normalização nova: qualquer diferença quebra o casamento com os `id` que já foram publicados.
3. **`lib/models/metadata_pack_model.dart`.** É a entrada do matcher. `PackGame.dumps` é uma lista de `PackDump`, e `PackDump.name` é o nome do bloco `game` do DAT, com as tags de região e revisão preservadas. `MetadataPack.byCrc` já existe e já é memoizado.

### Comandos deste repositório

O `flutter` não está no PATH. Toda linha de comando deste plano assume:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
cd /home/exedev/Workspace/retro_toolbox
```

- Suíte Dart: `flutter test`
- Um arquivo só: `flutter test test/pack_naming_test.dart`
- Suíte Python: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
- Análise: `flutter analyze`

**Linha de base antes desta fatia:** `flutter test` sai com `+100 -1`. A falha é `test/rar_decompress_screen_test.dart`, com um `StateError`, e é anterior à fatia 1. Não é sua. Não tente consertar. Ao fim desta fatia o número esperado é `+176 -1`.

---

## Estrutura de arquivos

Oito arquivos de produção novos, um por responsabilidade. Nenhum arquivo de produção existente é modificado, e o `pubspec.yaml` não muda: `rapidfuzz`, `archive` e `path` já são dependências. Do lado do teste, `test/pack_matcher_test.dart` é modificado uma vez, na Task 12, para passar a importar a fixture compartilhada.

| Arquivo | Responsabilidade | Depende de |
| --- | --- | --- |
| `lib/utils/pack_naming.dart` | `norm`, `displayTitle`, `canon`, e as listas de extensão. Dart puro. | nada |
| `lib/models/game_match_model.dart` | `MatchTier`, `MatchConfidence`, `GameMatch`. | `metadata_pack_model.dart` |
| `lib/services/pack_matcher.dart` | Índices do pacote e os três tiers de nome, mais `matchCrc`. Dart puro. | naming, model, rapidfuzz |
| `lib/utils/file_crc32.dart` | CRC32 de um arquivo local, em pedaços, e a formatação de CRC. | `package:archive` |
| `lib/services/zip_central_directory.dart` | Lê o diretório central de um ZIP remoto por Range, com as guardas da 5.8. | file_crc32, naming |
| `lib/services/crc_confirm_service.dart` | Junta matcher e diretório central: confirma ou corrige um match de nome. | matcher, zip cd |
| `lib/services/local_identity_service.dart` | O eixo da 5.7: nome primeiro, CRC só na dúvida, com cache. | matcher, file_crc32 |
| `lib/providers/identity_provider.dart` | Fiação Riverpod. | tudo acima, `metadata_pack_provider.dart` |

Mais dois helpers de teste, que não são suítes e por isso não terminam em `_test.dart`:

| Arquivo | Responsabilidade | Criado na |
| --- | --- | --- |
| `test/support/zip_fixture.dart` | Monta bytes de ZIP e um servidor de Range falso. | Task 10 |
| `test/support/pack_fixture.dart` | O `buildPack()` compartilhado, extraído da suíte do matcher. | Task 12 |

E mais três ferramentas de linha de comando:

| Arquivo | Responsabilidade |
| --- | --- |
| `tool/dump_naming_golden.py` | Gera o golden de paridade Python/Dart a partir do DAT real. |
| `tool/probe_zip_cd.dart` | Sonda: lê o diretório central de um ZIP remoto de verdade e imprime as entradas. |
| `tool/verify_matcher.dart` | Roda o matcher contra o pacote real e a listagem real, e confere os números da seção 5.9. |

Regra que vale para os três arquivos marcados como "Dart puro": **nenhum `import 'package:flutter/...'`**. Eles precisam rodar sob `dart run`, que é o que a Task 15 faz. Se você precisar de log, use `print` nos utilitários ou passe um callback; `debugPrint` está fora.

---

### Task 1: `norm` e as extensões

**Files:**
- Create: `lib/utils/pack_naming.dart`
- Test: `test/pack_naming_test.dart`

O `norm` é a forma comparável do nome de um arquivo: sem extensão, sem acento, sem pontuação, em caixa baixa, **com as tags de região e revisão preservadas**. É ele que faz o tier 1 do matcher. A referência é `tool/build_metadata_pack.py:185`.

Uma diferença de implementação que precisa estar clara: o Python faz `unicodedata.normalize("NFKD", ...)` e descarta os caracteres combinantes. O Dart não tem `unicodedata`, então a porta usa uma tabela de dobra. Isso é seguro e dá para provar: os nomes do DAT do No-Intro e do Redump são **ASCII puro**. Foram conferidos 4268 nomes do SNES, 13592 do PlayStation, 7701 do Nintendo DS e 3692 do Game Boy Advance, e nenhum tem um caractere acima de U+007F. A dobra só é exercida do lado do **nome do arquivo remoto**, que pode vir de qualquer lugar, e para esse lado uma tabela de latim resolve.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_naming_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

void main() {
  group('stripRomExtension', () {
    test('tira a extensão de ROM', () {
      expect(stripRomExtension('Chrono Trigger (USA).sfc'), 'Chrono Trigger (USA)');
      expect(stripRomExtension('Chrono Trigger (USA).zip'), 'Chrono Trigger (USA)');
      expect(stripRomExtension('Chrono Trigger (USA).ZIP'), 'Chrono Trigger (USA)');
    });

    test('não tira o que não é extensão de ROM', () {
      expect(stripRomExtension('Chrono Trigger (USA).txt'), 'Chrono Trigger (USA).txt');
      expect(stripRomExtension('Vol. 3'), 'Vol. 3');
    });

    test('prefere a extensão mais longa', () {
      // .gbc e .gb casam os dois; a mais longa é a certa.
      expect(stripRomExtension('Zelda.gbc'), 'Zelda');
    });
  });

  group('norm', () {
    test('baixa a caixa e troca pontuação por espaço', () {
      expect(norm('Chrono Trigger (USA)'), 'chrono trigger (usa)');
      expect(norm('Zero 4 Champ RR-Z (Japan)'), 'zero 4 champ rr z (japan)');
    });

    test('expande o e comercial', () {
      expect(norm('Dig & Spike'), 'dig and spike');
    });

    test('tira acento', () {
      expect(norm('Pokémon Rojo'), 'pokemon rojo');
      expect(norm('Astérix & Obélix'), 'asterix and obelix');
    });

    test('tira a extensão antes de normalizar', () {
      expect(norm('Chrono Trigger (USA).sfc'), 'chrono trigger (usa)');
    });

    test('preserva as tags de região e revisão', () {
      expect(norm('Chrono Trigger (USA) (Rev 1) [!]'), 'chrono trigger (usa) (rev 1) []');
    });

    test('nome só de pontuação vira vazio', () {
      expect(norm('---'), '');
      expect(norm(''), '');
    });
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_naming_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/utils/pack_naming.dart'`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/utils/pack_naming.dart`:

```dart
/// Porta Dart das funções de nome do builder (`tool/build_metadata_pack.py`).
///
/// O builder gera o pacote e o app consome, mas o app também precisa
/// normalizar nomes em runtime, porque o nome do arquivo na fonte remota nunca
/// passou pelo builder. As duas implementações têm que concordar caso a caso, e
/// é isso que `test/pack_naming_parity_test.dart` prova contra um golden
/// gerado do DAT real.
///
/// Este arquivo é Dart puro de propósito: `tool/verify_matcher.dart` o roda
/// fora do Flutter. Não adicione import de `package:flutter`.
library;

/// Extensões que o No-Intro e o Redump usam, mais os empacotadores que as
/// fontes servem. Mesma lista de `ROM_EXTS` no builder.
const romExtensions = <String>[
  '.zip', '.7z', '.sfc', '.smc', '.fig', '.swc', '.bin', '.rar', '.gz',
  '.nes', '.gb', '.gbc', '.gba', '.nds', '.3ds', '.n64', '.z64', '.v64',
  '.md', '.gen', '.gg', '.iso', '.cue', '.chd', '.col', '.int',
];

/// As que são contêiner e não ROM. Isso importa para a seção 5.8 do spec: o
/// CRC do diretório central só é comparável com o pacote quando a entrada é a
/// ROM em si. Se a entrada for outro arquivo compactado, o CRC é do compactado
/// e não casa com nada.
const archiveExtensions = <String>['.zip', '.7z', '.rar', '.gz'];

final _byLength = [...romExtensions]..sort((a, b) => b.length.compareTo(a.length));

String stripRomExtension(String name) {
  final low = name.toLowerCase();
  for (final ext in _byLength) {
    if (low.endsWith(ext)) return name.substring(0, name.length - ext.length);
  }
  return name;
}

bool hasRomExtension(String name) {
  final low = name.toLowerCase();
  return romExtensions.any(low.endsWith);
}

bool hasArchiveExtension(String name) {
  final low = name.toLowerCase();
  return archiveExtensions.any(low.endsWith);
}

/// Tabela de dobra de acento. Só as minúsculas, porque `norm` já baixou a
/// caixa antes de dobrar. Cobre latim-1 e os pedaços de latim estendido que
/// aparecem em título de jogo europeu.
const _fold = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'ř': 'r',
  'ś': 's', 'š': 's', 'ş': 's',
  'ť': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z',
};

String _stripDiacritics(String value) {
  final out = StringBuffer();
  for (final ch in value.split('')) {
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

final _disallowed = RegExp(r'[^a-z0-9()\[\]]+');
final _spaces = RegExp(r'\s+');

/// Forma comparável do nome: sem extensão, sem acento, sem pontuação, mas
/// **com** as tags de região e revisão. É o eixo do tier 1 do matcher.
String norm(String value) {
  var v = stripRomExtension(value).toLowerCase();
  v = _stripDiacritics(v);
  v = v.replaceAll('&', ' and ');
  v = v.replaceAll(_disallowed, ' ');
  return v.replaceAll(_spaces, ' ').trim();
}
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_naming_test.dart`
Expected: PASS, 9 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/pack_naming.dart test/pack_naming_test.dart
git commit -m "feat(identidade): norm e as listas de extensao em Dart"
```

---

### Task 2: `displayTitle` e `canon`

**Files:**
- Modify: `lib/utils/pack_naming.dart`
- Test: `test/pack_naming_test.dart`

O `canon` é a chave de agrupamento: o título sem tag de região, sem tag de revisão, com o artigo de volta na frente, passado por `norm`. É ele que faz o tier 2.

O detalhe que não pode ser invertido: a troca do artigo acontece no nome **cru**, antes de `norm`, porque `norm` come a vírgula que separa `Legend of Zelda` de `The`. O builder faz nessa ordem (`tool/build_metadata_pack.py:196`) e a PoC fazia na ordem oposta. A seção 5.9 do spec registra que nos 4122 arquivos medidos os dois dão o mesmo resultado, mas o builder é quem gerou os `id` publicados, então é o builder que manda.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao fim de `test/pack_naming_test.dart`, dentro do `main`, depois do `group('norm', ...)`:

```dart
  group('displayTitle', () {
    test('preserva a caixa original', () {
      expect(displayTitle('Chrono Trigger (USA)'), 'Chrono Trigger');
    });

    test('move o artigo do fim para a frente sem mexer no resto', () {
      expect(displayTitle('Legend of Zelda, The (USA)'), 'The Legend of Zelda');
      expect(displayTitle('Blue Crystalrod, The (Japan)'), 'The Blue Crystalrod');
    });

    test('preserva acento e pontuação', () {
      expect(displayTitle('Pokémon Rojo (Spain).gb'), 'Pokémon Rojo');
      expect(displayTitle('Super Mario World 2 - Yoshi\'s Island (USA)'),
          'Super Mario World 2 - Yoshi\'s Island');
    });

    test('nome que é só tag vira vazio', () {
      expect(displayTitle('(USA)'), '');
    });

    test('tira vírgula sobrando na ponta', () {
      expect(displayTitle('Addams Family, (USA)'), 'Addams Family');
    });
  });

  group('canon', () {
    test('descarta tags de região e revisão', () {
      expect(canon('Chrono Trigger (USA) (Rev 1)'), 'chrono trigger');
      expect(canon('Chrono Trigger (Japan) [T+Eng]'), 'chrono trigger');
    });

    test('move o artigo antes de normalizar', () {
      expect(canon('Legend of Zelda, The (USA)'), 'the legend of zelda');
    });

    test('regiões diferentes do mesmo jogo dão a mesma chave', () {
      expect(canon('Super Mario World (USA)'), canon('Super Mario World (Europe)'));
    });

    test('nome que é só tag vira chave vazia', () {
      expect(canon('(USA)'), '');
    });
  });
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_naming_test.dart`
Expected: FALHA de compilação, `The function 'displayTitle' isn't defined`.

- [ ] **Step 3: Escreva a implementação mínima**

Acrescente ao fim de `lib/utils/pack_naming.dart`:

```dart
final _tags = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _trailingArticle = RegExp(
  r'^(.*?), (the|a|an|le|la|les|el|los|das|der|die)$',
  caseSensitive: false,
);

/// Equivalente do `.strip().strip(",").strip()` do Python: apara espaço,
/// depois vírgula das duas pontas, depois espaço de novo.
String _trimSpaceThenComma(String value) {
  var v = value.trim();
  var start = 0;
  var end = v.length;
  while (start < end && v[start] == ',') start++;
  while (end > start && v[end - 1] == ',') end--;
  return v.substring(start, end).trim();
}

/// Título de exibição a partir do nome do DAT: sem extensão, sem tags, com o
/// artigo de volta na frente, e com a caixa e os acentos originais intactos.
String displayTitle(String datName) {
  var v = stripRomExtension(datName).replaceAll(_tags, ' ');
  v = _trimSpaceThenComma(v.replaceAll(_spaces, ' '));
  final match = _trailingArticle.firstMatch(v);
  if (match != null) v = '${match.group(2)} ${match.group(1)}';
  return v;
}

/// Título canônico: a chave de agrupamento de um jogo. É o título de exibição
/// passado por [norm].
String canon(String value) => norm(displayTitle(value));
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_naming_test.dart`
Expected: PASS, 18 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/pack_naming.dart test/pack_naming_test.dart
git commit -m "feat(identidade): displayTitle e canon em Dart"
```

---

### Task 3: o golden de paridade Python/Dart

**Files:**
- Create: `tool/dump_naming_golden.py`
- Create: `test/fixtures/naming_golden.json` (gerado, e commitado)
- Create: `test/pack_naming_parity_test.dart`

As Tasks 1 e 2 foram escritas contra fixtures à mão. Isso prova que o Dart faz o que você achou que o Python faz. O golden prova que ele faz o que o Python **de fato** faz, sobre nomes reais que ninguém escolheu a dedo.

O gerador é Python, roda contra o DAT real do SNES, pega um nome a cada 50 e junta uma lista de casos difíceis escritos à mão que o DAT não tem (extensão, underscore, acento, artigo, vírgula sobrando). O arquivo resultante é commitado, então o teste Dart não precisa de rede.

- [ ] **Step 1: Escreva o gerador**

Crie `tool/dump_naming_golden.py`:

```python
#!/usr/bin/env python3
"""Gera o golden de paridade entre o norm/canon do builder e o do app.

O app reimplementa norm, display_title e canon em Dart, porque precisa
normalizar em runtime nomes que nunca passaram pelo builder. As duas
implementações têm que concordar caso a caso. Este script congela o que o
Python responde, e test/pack_naming_parity_test.dart cobra o Dart.

Uso:
    python3 tool/dump_naming_golden.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_metadata_pack as b  # noqa: E402

SYSTEM = "Nintendo - Super Nintendo Entertainment System"
STRIDE = 50
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test", "fixtures", "naming_golden.json",
)

# Casos que o DAT não produz e o app vai ver: nome de arquivo com extensão,
# fonte que troca espaço por underscore, título com acento, artigo invertido,
# vírgula sobrando, e o nome que é só tag.
HANDPICKED = [
    "Chrono Trigger (USA).sfc",
    "Chrono Trigger (USA).zip",
    "Chrono_Trigger_(USA).zip",
    "chrono trigger (usa)",
    "Legend of Zelda, The (USA).smc",
    "Blue Crystalrod, The (Japan)",
    "Addams Family, (USA)",
    "Pokémon Rojo (Spain).gb",
    "Astérix & Obélix (Europe)",
    "Dig & Spike Volleyball (USA)",
    "Super Mario World 2 - Yoshi's Island (USA)",
    "Zero 4 Champ RR-Z (Japan)",
    "Jikkyou Powerful Pro Yakyuu - Basic Ban '98 (Japan)",
    "Vol. 3",
    "(USA)",
    "---",
    "",
]


def main():
    url = "{}/metadat/no-intro/{}.dat".format(
        b.LIBRETRO_RAW, b.urllib.parse.quote(SYSTEM)
    )
    names = [e["name"] for e in b.parse_dat(b.fetch_text(url))]
    sampled = names[::STRIDE]
    cases = []
    for name in sampled + HANDPICKED:
        cases.append({
            "input": name,
            "norm": b.norm(name),
            "displayTitle": b.display_title(name),
            "canon": b.canon(name),
        })
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(
            {"system": SYSTEM, "stride": STRIDE, "cases": cases},
            fh, ensure_ascii=False, indent=1, sort_keys=True,
        )
        fh.write("\n")
    print("{} casos em {}".format(len(cases), OUT))


if __name__ == "__main__":
    main()
```

O `b.urllib.parse.quote` funciona porque `build_metadata_pack.py` importa `urllib.parse` no topo do módulo. Mesma construção de URL do `main` do builder, linha 476.

- [ ] **Step 2: Rode o gerador**

Run: `python3 tool/dump_naming_golden.py`
Expected: `103 casos em /home/exedev/Workspace/retro_toolbox/test/fixtures/naming_golden.json`. São 86 amostrados (4268 dividido por 50, arredondando para cima) mais 17 escritos à mão. Se o DAT tiver mudado de tamanho o primeiro número muda, e isso não é problema.

- [ ] **Step 3: Escreva o teste de paridade**

Crie `test/pack_naming_parity_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Prova que a porta Dart de `norm`, `displayTitle` e `canon` concorda com o
/// builder Python caso a caso, sobre nomes reais do DAT do SNES mais uma lista
/// de casos difíceis. O golden é gerado por `tool/dump_naming_golden.py`.
///
/// Se este teste quebrar depois de você mexer no builder, a resposta certa
/// quase sempre é regerar o golden e alinhar o Dart, não relaxar o teste.
void main() {
  late List<Map<String, dynamic>> cases;

  setUpAll(() {
    final raw = File('test/fixtures/naming_golden.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    cases = (decoded['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(50), reason: 'golden vazio ou truncado');
  });

  test('norm concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(norm(c['input'] as String), c['norm'],
          reason: 'norm divergiu em "${c['input']}"');
    }
  });

  test('displayTitle concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(displayTitle(c['input'] as String), c['displayTitle'],
          reason: 'displayTitle divergiu em "${c['input']}"');
    }
  });

  test('canon concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(canon(c['input'] as String), c['canon'],
          reason: 'canon divergiu em "${c['input']}"');
    }
  });
}
```

- [ ] **Step 4: Rode e resolva as divergências**

Run: `flutter test test/pack_naming_parity_test.dart`
Expected: PASS, 3 testes.

Se algum caso divergir, a mensagem diz qual entrada e qual função. **Conserte o Dart, não o golden.** As divergências prováveis, em ordem de probabilidade:

- um caractere acentuado fora da tabela `_fold`. Acrescente a linha que falta.
- ordem de `_trimSpaceThenComma`. O Python é `.strip()`, `.strip(",")`, `.strip()`, nessa ordem.
- a regex de artigo com `caseSensitive: true` por engano.

- [ ] **Step 5: Commit**

```bash
git add tool/dump_naming_golden.py test/fixtures/naming_golden.json test/pack_naming_parity_test.dart
git commit -m "test(identidade): golden de paridade entre o norm do builder e o do app"
```

---

### Task 4: o modelo de match

**Files:**
- Create: `lib/models/game_match_model.dart`
- Test: `test/game_match_model_test.dart`

A seção 5.5 do spec exige que "cada match carregue uma confiança derivada do tier" e que "tier 3 nunca seja apresentado como certeza". Isso vira dois enums: o tier, que é como o match foi obtido, e a confiança, que é o que a UI pode afirmar. A fatia 3 lê a confiança e não precisa saber o que é um tier.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/game_match_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

const _game = PackGame(
  id: 'snes/chrono-trigger',
  title: 'Chrono Trigger',
  dumps: [PackDump(name: 'Chrono Trigger (USA)', crc: '2D206BF7')],
);

void main() {
  test('checksum é a única confiança confirmada', () {
    expect(MatchTier.checksum.confidence, MatchConfidence.confirmed);
  });

  test('os dois tiers de nome confiáveis são prováveis, não confirmados', () {
    expect(MatchTier.exactName.confidence, MatchConfidence.likely);
    expect(MatchTier.canonicalName.confidence, MatchConfidence.likely);
  });

  test('fuzzy é palpite', () {
    expect(MatchTier.fuzzyName.confidence, MatchConfidence.guess);
  });

  test('o match expõe a confiança do próprio tier', () {
    const match = GameMatch(
      game: _game,
      tier: MatchTier.fuzzyName,
      sourceName: 'Chrono Triger (USA).zip',
      score: 93.5,
    );
    expect(match.confidence, MatchConfidence.guess);
    expect(match.score, 93.5);
    expect(match.dump, isNull);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/game_match_model_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/models/game_match_model.dart`:

```dart
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Como o match foi obtido. A ordem da declaração é a ordem de preferência: o
/// matcher tenta de cima para baixo e para no primeiro que resolve.
enum MatchTier {
  /// O CRC32 bateu com um dump do pacote. É o único tier que não erra.
  checksum,

  /// `norm` do nome do arquivo é igual ao `norm` do nome de um dump.
  exactName,

  /// `canon` do nome do arquivo é igual ao `canon` de um jogo do pacote.
  /// Casa variantes de região e revisão, que é o caso comum.
  canonicalName,

  /// Similaridade de edição acima do corte. Erra: a seção 5.9 do spec mediu
  /// pelo menos 4 alvos errados em 26 casos, contra 0.63% de ganho de
  /// cobertura. Existe porque o ganho é de graça, e nunca vira certeza.
  fuzzyName,
}

/// O que a tela pode afirmar. Deriva do tier e existe para a fatia 3 não ter
/// que redecidir isso em cada widget.
enum MatchConfidence { confirmed, likely, guess }

extension MatchTierConfidence on MatchTier {
  MatchConfidence get confidence => switch (this) {
        MatchTier.checksum => MatchConfidence.confirmed,
        MatchTier.exactName => MatchConfidence.likely,
        MatchTier.canonicalName => MatchConfidence.likely,
        MatchTier.fuzzyName => MatchConfidence.guess,
      };
}

/// Um arquivo da fonte atribuído a um jogo do pacote.
///
/// [dump] só vem preenchido quando o tier identifica **qual** versão, ou seja
/// no `checksum` e no `exactName`. Os tiers canônico e fuzzy resolvem o jogo,
/// não a versão, e deixam [dump] nulo de propósito.
class GameMatch {
  final PackGame game;
  final MatchTier tier;

  /// O nome do arquivo na fonte, cru, do jeito que a fonte deu.
  final String sourceName;

  final PackDump? dump;

  /// 0 a 100. Só o tier fuzzy usa; os outros ficam em 100.
  final double score;

  const GameMatch({
    required this.game,
    required this.tier,
    required this.sourceName,
    this.dump,
    this.score = 100,
  });

  MatchConfidence get confidence => tier.confidence;

  @override
  String toString() => 'GameMatch(${game.id}, ${tier.name}, $score)';
}
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/game_match_model_test.dart`
Expected: PASS, 4 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/models/game_match_model.dart test/game_match_model_test.dart
git commit -m "feat(identidade): modelo de match com tier e confianca"
```

---

### Task 5: o matcher e o tier 1

**Files:**
- Create: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

O `PackMatcher` recebe um `MetadataPack` e constrói três índices uma vez só, no construtor. Depois cada `match` é uma sequência de consultas baratas.

Os índices:

- `_byName`: `norm(dump.name)` para o par jogo mais dump. É o tier 1.
- `_byCanon`: `canon(dump.name)` para o jogo. É o tier 2. A primeira ocorrência ganha, que é a mesma regra do `collapse` do builder.
- `_byHead`: os quatro primeiros caracteres do primeiro token da chave canônica para a lista de chaves canônicas. Existe para o tier 3 não comparar contra as 2415 chaves do pacote a cada falha. É a mesma otimização da PoC.

Todas as fixtures deste arquivo de teste saem do mesmo pacote pequeno, montado no topo. Os nomes não são inventados: são casos reais do DAT do SNES escolhidos porque cada um exercita um tier.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/pack_matcher_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// Pacote de teste com um caso real para cada tier:
/// - Chrono Trigger tem duas regiões, então exercita tier 1 contra tier 2.
/// - Blue Crystalrod tem o artigo no fim, que é o caso que o `canon` conserta.
/// - HammerLock Wrestling é o par fuzzy que a PoC resolveu certo.
/// - Pro Action Replay MK3 é o par fuzzy que a PoC resolveu **errado**.
/// - Zero 4 Champ RR e RR-Z são dois candidatos fuzzy do mesmo bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/chrono-trigger',
          'title': 'Chrono Trigger',
          'dumps': [
            {'name': 'Chrono Trigger (USA)', 'crc': '2D206BF7'},
            {'name': 'Chrono Trigger (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-blue-crystalrod',
          'title': 'The Blue Crystalrod',
          'dumps': [
            {'name': 'Blue Crystalrod, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/hammerlock-wrestling',
          'title': 'HammerLock Wrestling',
          'dumps': [
            {'name': 'HammerLock Wrestling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/pro-action-replay-mk3',
          'title': 'Pro Action Replay MK3',
          'dumps': [
            {'name': 'Pro Action Replay MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-mario-world',
          'title': 'Super Mario World',
          'dumps': [
            {'name': 'Super Mario World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Mario World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr',
          'title': 'Zero 4 Champ RR',
          'dumps': [
            {'name': 'Zero 4 Champ RR (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr-z',
          'title': 'Zero 4 Champ RR-Z',
          'dumps': [
            {'name': 'Zero 4 Champ RR-Z (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));

void main() {
  late PackMatcher matcher;

  setUp(() => matcher = PackMatcher(buildPack()));

  group('tier 1, nome exato', () {
    test('casa o nome do dump letra por letra', () {
      final m = matcher.match('Chrono Trigger (USA)');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.exactName);
      expect(m.game.id, 'snes/chrono-trigger');
      expect(m.sourceName, 'Chrono Trigger (USA)');
    });

    test('casa ignorando a extensão do arquivo', () {
      expect(matcher.match('Chrono Trigger (USA).zip')?.tier, MatchTier.exactName);
      expect(matcher.match('Chrono Trigger (USA).sfc')?.tier, MatchTier.exactName);
    });

    test('casa ignorando caixa, underscore e pontuação', () {
      final m = matcher.match('chrono_trigger_(usa).ZIP');
      expect(m?.tier, MatchTier.exactName);
      expect(m?.game.id, 'snes/chrono-trigger');
    });

    test('o tier exato devolve o dump concreto, com o CRC daquela região', () {
      expect(matcher.match('Chrono Trigger (USA)')?.dump?.crc, '2D206BF7');
      expect(matcher.match('Chrono Trigger (Japan)')?.dump?.crc, 'ABCD1234');
    });

    test('devolve null quando não casa em tier nenhum', () {
      expect(matcher.match('Alguma Coisa Que Nao Existe (USA).zip'), isNull);
    });
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/pack_matcher.dart'`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/services/pack_matcher.dart`:

```dart
import 'package:rapidfuzz/rapidfuzz.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Corte do tier 3, na escala 0 a 100 do `rapidfuzz.ratio`.
///
/// O valor vem da PoC, que usou `difflib.SequenceMatcher` com corte 0.90. A
/// seção 5.9 do spec registra que as duas métricas resolvem os mesmos 26
/// arquivos para os mesmos alvos neste corte, então a troca de biblioteca não
/// pede recalibragem.
const fuzzyCutoff = 90.0;

/// Casa um nome de arquivo com um jogo do metadata pack.
///
/// Três tiers de nome, na ordem da seção 5.5 do spec: nome exato, título
/// canônico, similaridade de edição. Mais um quarto eixo, o `matchCrc`, que é
/// o único que não erra.
///
/// Dart puro de propósito: `tool/verify_matcher.dart` roda esta classe fora do
/// Flutter. Não adicione import de `package:flutter`.
class PackMatcher {
  final MetadataPack pack;

  final Map<String, ({PackGame game, PackDump dump})> _byName = {};
  final Map<String, PackGame> _byCanon = {};
  final Map<String, List<String>> _byHead = {};

  PackMatcher(this.pack) {
    for (final game in pack.games) {
      for (final dump in game.dumps) {
        _byName.putIfAbsent(norm(dump.name), () => (game: game, dump: dump));
        final key = canon(dump.name);
        if (key.isEmpty) continue;
        _byCanon.putIfAbsent(key, () => game);
      }
    }
    for (final key in _byCanon.keys) {
      _byHead.putIfAbsent(_head(key), () => <String>[]).add(key);
    }
  }

  /// Os quatro primeiros caracteres do primeiro token. Mesmo balde da PoC:
  /// serve só para o tier 3 não varrer o pacote inteiro a cada falha.
  static String _head(String canonKey) {
    final first = canonKey.split(' ').first;
    return first.length <= 4 ? first : first.substring(0, 4);
  }

  /// Quantos jogos e quantas chaves canônicas o matcher indexou. Serve para o
  /// `tool/verify_matcher.dart` e para diagnóstico.
  int get indexedGames => pack.games.length;
  int get indexedCanonKeys => _byCanon.length;

  GameMatch? match(String sourceName) {
    final exact = _byName[norm(sourceName)];
    if (exact != null) {
      return GameMatch(
        game: exact.game,
        dump: exact.dump,
        tier: MatchTier.exactName,
        sourceName: sourceName,
      );
    }
    return null;
  }
}
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 5 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): PackMatcher com indices e o tier de nome exato"
```

---

### Task 6: o tier 2, título canônico

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

O tier 2 casa variantes: outra região, outra revisão, beta, protótipo. Ele resolve o **jogo**, não a versão, e por isso deixa `dump` nulo. Esse é o tier que mais cresce quando a fonte não é um espelho do No-Intro, e é responsável por 10.77% dos arquivos na medição da seção 5.9.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao `main` de `test/pack_matcher_test.dart`, depois do `group('tier 1, nome exato', ...)`:

```dart
  group('tier 2, título canônico', () {
    test('casa quando só a região e a revisão diferem', () {
      final m = matcher.match('Chrono Trigger (Europe) (Rev 1).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/chrono-trigger');
    });

    test('casa quando o artigo está invertido dos dois lados', () {
      // No pacote o dump é "Blue Crystalrod, The (Japan)". A fonte escreve o
      // artigo na frente. `canon` põe os dois na mesma forma.
      final m = matcher.match('The Blue Crystalrod (Japan).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/the-blue-crystalrod');
    });

    test('o tier canônico resolve o jogo e não a versão, então não traz dump', () {
      expect(matcher.match('Chrono Trigger (Europe) (Rev 1).zip')?.dump, isNull);
    });

    test('o tier exato ganha do canônico quando os dois casariam', () {
      // "Super Mario World (Europe)" casa exato no segundo dump e casaria
      // canônico no jogo inteiro. O exato tem que vencer, porque só ele sabe
      // qual das duas regiões é.
      final m = matcher.match('Super Mario World (Europe).sfc');
      expect(m!.tier, MatchTier.exactName);
      expect(m.dump?.crc, 'A31BEAD4');
    });
  });
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FALHA. Os três primeiros testes do grupo novo falham com `Expected: not null, Actual: <null>`. O quarto passa, porque o tier 1 já resolve.

- [ ] **Step 3: Escreva a implementação mínima**

Em `lib/services/pack_matcher.dart`, substitua o corpo de `match` por:

```dart
  GameMatch? match(String sourceName) {
    final exact = _byName[norm(sourceName)];
    if (exact != null) {
      return GameMatch(
        game: exact.game,
        dump: exact.dump,
        tier: MatchTier.exactName,
        sourceName: sourceName,
      );
    }

    final key = canon(sourceName);
    if (key.isEmpty) return null;

    final byCanon = _byCanon[key];
    if (byCanon != null) {
      return GameMatch(
        game: byCanon,
        tier: MatchTier.canonicalName,
        sourceName: sourceName,
      );
    }

    return null;
  }
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 9 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): tier de titulo canonico no PackMatcher"
```

---

### Task 7: o tier 3, similaridade, e o erro que ele carrega

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

O tier 3 rende 0.63% de cobertura e erra em pelo menos 15% do que resolve. Ele existe porque o ganho é de graça e porque a alternativa, não mostrar nada, também é ruim. O que não pode acontecer é a tela dizer que tem certeza. O teste do `Pro Action Replay MK2` existe justamente para congelar esse comportamento: o match sai errado **e** sai marcado como palpite.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao `main` de `test/pack_matcher_test.dart`:

```dart
  group('tier 3, similaridade', () {
    test('casa acima do corte', () {
      // "Hammer Lock" contra "HammerLock", um espaço de diferença: 97.56.
      final m = matcher.match('Hammer Lock Wrestling (USA).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/hammerlock-wrestling');
    });

    test('não casa abaixo do corte', () {
      // 47.46 contra "chrono trigger".
      expect(
        matcher.match('Chrono Trigger 2 - Ressurection of the Ancients (USA).zip'),
        isNull,
      );
    });

    test('o score fica entre o corte e cem', () {
      final m = matcher.match('Hammer Lock Wrestling (USA).zip')!;
      expect(m.score, greaterThanOrEqualTo(fuzzyCutoff));
      expect(m.score, lessThan(100));
    });

    test('escolhe o candidato de maior score, não o primeiro do balde', () {
      // O balde "zero" tem "zero 4 champ rr" (90.32) antes de
      // "zero 4 champ rr z" (96.97). O segundo é o certo.
      final m = matcher.match('Zero4 Champ RR-Z (Japan).zip');
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/zero-4-champ-rr-z');
    });

    test('o tier 3 erra, e o modelo diz que é palpite', () {
      // Caso real da PoC: MK2 resolve para MK3 com 95.24. O dígito no fim do
      // título é exatamente o que a distância de edição não enxerga. Ver a
      // seção 5.9 do spec.
      final m = matcher.match('Pro Action Replay MK2 (Europe) (Unl) [b].zip');
      expect(m!.game.id, 'snes/pro-action-replay-mk3');
      expect(m.confidence, MatchConfidence.guess);
    });

    test('varre o pacote inteiro quando o balde do primeiro token não existe', () {
      // "rammerlock" cai no balde "ramm", que não existe. Sem o fallback o
      // match de 95.00 contra "hammerlock wrestling" se perderia.
      final m = matcher.match('Rammerlock Wrestling.zip');
      expect(m!.game.id, 'snes/hammerlock-wrestling');
      expect(m.tier, MatchTier.fuzzyName);
    });
  });
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FALHA. Cinco dos seis testes novos falham com null. O `não casa abaixo do corte` passa, porque hoje tudo que chega ali devolve null.

- [ ] **Step 3: Escreva a implementação mínima**

Em `lib/services/pack_matcher.dart`, troque o `return null;` final de `match` por:

```dart
    final pool = _byHead[_head(key)] ?? _byCanon.keys.toList();
    String? best;
    var bestScore = 0.0;
    for (final candidate in pool) {
      final score = ratio(key, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best == null || bestScore < fuzzyCutoff) return null;
    return GameMatch(
      game: _byCanon[best]!,
      tier: MatchTier.fuzzyName,
      sourceName: sourceName,
      score: bestScore,
    );
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 15 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): tier de similaridade com corte em 90"
```

---

### Task 8: o eixo do checksum

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

O único tier que não erra. O índice já existe: `MetadataPack.byCrc` foi construído na fatia 1 e é memoizado. O que falta é embrulhar num `GameMatch` e normalizar a caixa do hexadecimal, porque quem chama pode vir do diretório central de um ZIP, do CRC de um arquivo local ou de uma API, e cada um escreve na sua caixa.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao `main` de `test/pack_matcher_test.dart`:

```dart
  group('eixo do checksum', () {
    test('casa o CRC em maiúsculas e traz o dump certo', () {
      final m = matcher.matchCrc('A31BEAD4', sourceName: 'qualquer.zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.checksum);
      expect(m.confidence, MatchConfidence.confirmed);
      expect(m.game.id, 'snes/super-mario-world');
      expect(m.dump?.name, 'Super Mario World (Europe)');
      expect(m.sourceName, 'qualquer.zip');
    });

    test('casa o CRC em minúsculas', () {
      expect(matcher.matchCrc('a31bead4')?.game.id, 'snes/super-mario-world');
    });

    test('devolve null para CRC que não está no pacote', () {
      expect(matcher.matchCrc('DEADBEEF'), isNull);
    });
  });
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FALHA de compilação, `The method 'matchCrc' isn't defined for the type 'PackMatcher'`.

- [ ] **Step 3: Escreva a implementação mínima**

Acrescente a `PackMatcher`, depois de `match`:

```dart
  /// O eixo que não erra. [crc] pode vir em qualquer caixa.
  ///
  /// Cuidado de quem chama: o CRC tem que ser o da **ROM**, não o do arquivo
  /// que a fonte serve. Um ZIP tem CRC próprio, e ele não está no pacote. Ver
  /// a seção 5.8 do spec, limite 1.
  GameMatch? matchCrc(String crc, {String sourceName = ''}) {
    final upper = crc.toUpperCase();
    final game = pack.byCrc[upper];
    if (game == null) return null;
    PackDump? dump;
    for (final candidate in game.dumps) {
      if (candidate.crc == upper) {
        dump = candidate;
        break;
      }
    }
    return GameMatch(
      game: game,
      dump: dump,
      tier: MatchTier.checksum,
      sourceName: sourceName,
    );
  }
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 18 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): matchCrc, o eixo que nao erra"
```

---
### Task 9: CRC32 de arquivo local, em pedaços

**Files:**
- Create: `lib/utils/file_crc32.dart`
- Test: `test/file_crc32_test.dart`

Duas funções pequenas, mas elas vêm antes das próximas três tarefas porque todas usam o `formatCrc`. O `getCrc32` do `package:archive`, que já é dependência do app, aceita um CRC anterior justamente para poder ser encadeado. Isso importa: um ISO de GameCube tem 1,4 GB, e ler tudo na memória para calcular quatro bytes de hash derruba o app no celular.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/file_crc32_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/file_crc32.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('file_crc32_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('formatCrc dá oito dígitos em maiúsculas com zero à esquerda', () {
    expect(formatCrc(0), '00000000');
    expect(formatCrc(0xABCDE), '000ABCDE');
    expect(formatCrc(0xA31BEAD4), 'A31BEAD4');
  });

  test('crc32OfFile bate com o CRC do conteúdo inteiro', () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final file = File('${tmp.path}/pequeno.sfc')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });

  test('encadeia certo em arquivo grande o bastante para virar vários pedaços',
      () async {
    // 512 KB força o openRead a entregar mais de um chunk. Se o encadeamento
    // do getCrc32 estivesse errado, este teste seria o único a pegar.
    final bytes = Uint8List.fromList(List.generate(512 * 1024, (i) => i % 253));
    final file = File('${tmp.path}/grande.iso')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/file_crc32_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/utils/file_crc32.dart'`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/utils/file_crc32.dart`:

```dart
import 'dart:io';

import 'package:archive/archive.dart';

/// CRC32 de um arquivo local, lido em pedaços.
///
/// O `getCrc32` recebe o CRC anterior como segundo argumento e continua de
/// onde parou, então nunca precisamos do arquivo inteiro na memória.
Future<String> crc32OfFile(File file) async {
  var crc = 0;
  await for (final chunk in file.openRead()) {
    crc = getCrc32(chunk, crc);
  }
  return formatCrc(crc);
}

/// Oito dígitos hexadecimais em maiúsculas, que é como o DAT escreve e como o
/// `PackDump.crc` guarda. Sem isso a comparação vira uma loteria de caixa.
String formatCrc(int crc) =>
    (crc & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/file_crc32_test.dart`
Expected: PASS, 3 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/file_crc32.dart test/file_crc32_test.dart
git commit -m "feat(identidade): CRC32 de arquivo local em pedacos"
```

---

### Task 10: o diretório central por Range, e as guardas da 5.8

**Files:**
- Create: `lib/services/zip_central_directory.dart`
- Create: `test/support/zip_fixture.dart`
- Test: `test/zip_central_directory_test.dart`

Esta é a peça que deixa o app confirmar a identidade de um arquivo **antes** de baixar 800 KB dele. O truque é velho e é o mesmo que o `unzip -l` remoto usa: o ZIP guarda um índice no fim, e dá para pegar só o fim.

O caminho tem duas requisições:

1. `Range: bytes=-256`. Os últimos 256 bytes contêm o *end of central directory*, o EOCD, que tem 22 bytes fixos e diz onde o diretório central começa e quanto ele ocupa.
2. `Range: bytes=<offset>-<offset+size-1>`. O diretório central em si.

Foi conferido contra um arquivo real do archive.org, `'96 Zenkoku Koukou Soccer Senshuken (Japan).zip`, de 840120 bytes: a primeira requisição volta `206` com `content-range: bytes 839864-840119/840120`, o EOCD está no deslocamento 212 dos 256 bytes, o diretório central tem 93 bytes a partir de 839983, e o CRC lá dentro é `05FBB855`, que é exatamente o CRC do dump `'96 Zenkoku Koukou Soccer Senshuken (Japan)` no pacote publicado do SNES. O caminho inteiro funciona em dado real.

O layout que o parser lê, todo em little-endian:

| Estrutura | Campo | Deslocamento |
| --- | --- | --- |
| EOCD | assinatura `PK\x05\x06`, `0x06054b50` | +0 |
| EOCD | tamanho do diretório central | +12 |
| EOCD | deslocamento do diretório central | +16 |
| EOCD | tamanho do comentário | +20 |
| Entrada | assinatura `PK\x01\x02`, `0x02014b50` | +0 |
| Entrada | CRC32 | +16 |
| Entrada | tamanho do nome | +28 |
| Entrada | tamanho do extra | +30 |
| Entrada | tamanho do comentário | +32 |
| Entrada | o nome | +46 |

**As guardas são o ponto desta tarefa, não o parser.** A seção 5.8 do spec registra que um servidor pode ignorar o header `Range` e devolver `200` com o arquivo inteiro, ou pior, uma página HTML. O Myrient faz isso. Se o código confiar no status, ele vai tentar achar um EOCD dentro de um HTML e, na melhor das hipóteses, não achar; na pior, baixar o arquivo inteiro para descobrir. Por isso: **status tem que ser exatamente 206, e o `Content-Range` tem que existir e casar o formato**. Sem os dois, o retorno é null e o chamador segue com o nome.

Esta tarefa entrega até os bytes crus do diretório central. A Task 11 os transforma em entradas.

- [ ] **Step 1: Escreva a fixture de zip**

Crie `test/support/zip_fixture.dart`. Não é um arquivo de teste, é um helper: o `flutter test` só executa `*_test.dart`, então ele não vira uma suíte vazia.

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:roms_downloader/services/zip_central_directory.dart';

/// Uma entrada de diretório central: 46 bytes fixos, o nome, e o extra e o
/// comentário se pedidos. Só os campos que o parser lê são preenchidos, que é
/// o que um zip real também faz com a maioria deles.
Uint8List cdEntry(String name, int crc, {int extraLen = 0, int commentLen = 0}) {
  final nameBytes = utf8.encode(name);
  final head = ByteData(46);
  head.setUint32(0, 0x02014b50, Endian.little);
  head.setUint32(16, crc, Endian.little);
  head.setUint16(28, nameBytes.length, Endian.little);
  head.setUint16(30, extraLen, Endian.little);
  head.setUint16(32, commentLen, Endian.little);
  final out = BytesBuilder();
  out.add(head.buffer.asUint8List());
  out.add(nameBytes);
  out.add(Uint8List(extraLen));
  out.add(Uint8List(commentLen));
  return out.toBytes();
}

/// Monta um zip inteiro: um bloco de zeros no lugar das entradas locais, o
/// diretório central, o EOCD, e um comentário depois dele.
///
/// O comentário depois do EOCD não é invenção de teste: o TorrentZip, que é o
/// formato que o archive.org serve, grava `TORRENTZIPPED-xxxxxxxx` ali. Se o
/// parser assumisse que o EOCD são os últimos 22 bytes do arquivo, ele
/// quebraria em cima de todo o acervo do archive.org.
Uint8List buildZip(
  List<Uint8List> entries, {
  int localBytes = 64,
  String comment = '',
  bool zip64 = false,
  int? forcedCdOffset,
  int? forcedCdSize,
}) {
  final cd = BytesBuilder();
  for (final entry in entries) {
    cd.add(entry);
  }
  final cdBytes = cd.toBytes();
  final commentBytes = utf8.encode(comment);
  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(8, entries.length, Endian.little);
  eocd.setUint16(10, entries.length, Endian.little);
  eocd.setUint32(12, forcedCdSize ?? (zip64 ? 0xFFFFFFFF : cdBytes.length),
      Endian.little);
  eocd.setUint32(16, forcedCdOffset ?? (zip64 ? 0xFFFFFFFF : localBytes),
      Endian.little);
  eocd.setUint16(20, commentBytes.length, Endian.little);
  final out = BytesBuilder();
  out.add(Uint8List(localBytes));
  out.add(cdBytes);
  out.add(eocd.buffer.asUint8List());
  out.add(commentBytes);
  return out.toBytes();
}

/// Servidor falso de Range. Guarda o que foi pedido, para o teste conferir que
/// foram duas requisições curtas e não o arquivo inteiro.
class FakeRangeServer {
  final Uint8List body;
  final int status;
  final bool sendContentRange;
  final List<String> asked = [];

  FakeRangeServer(this.body, {this.status = 206, this.sendContentRange = true});

  Future<RangeResponse> fetch(Uri uri, String range) async {
    asked.add(range);
    final total = body.length;
    int start;
    int end;
    final suffix = RegExp(r'^bytes=-(\d+)$').firstMatch(range);
    if (suffix != null) {
      final n = int.parse(suffix.group(1)!);
      start = total - n < 0 ? 0 : total - n;
      end = total - 1;
    } else {
      final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
      start = int.parse(m.group(1)!);
      end = int.parse(m.group(2)!);
      if (end >= total) end = total - 1;
    }
    return RangeResponse(
      statusCode: status,
      contentRange: sendContentRange ? 'bytes $start-$end/$total' : null,
      bytes: Uint8List.sublistView(body, start, end + 1),
    );
  }
}
```

- [ ] **Step 2: Escreva os testes que falham**

Crie `test/zip_central_directory_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/zip_fixture.dart';

void main() {
  final uri = Uri.parse('https://exemplo/arquivo.zip');
  final entry = cdEntry('Chrono Trigger (USA).sfc', 0x2D206BF7);

  test('devolve exatamente os bytes do diretório central', () async {
    final server = FakeRangeServer(buildZip([entry]));
    final raw = await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(raw, isNotNull);
    expect(raw, orderedEquals(entry));
  });

  test('faz duas requisições: o sufixo e o intervalo exato', () async {
    final server = FakeRangeServer(buildZip([entry], localBytes: 500));
    await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(server.asked, [
      'bytes=-256',
      'bytes=500-${500 + entry.length - 1}',
    ]);
  });

  test('acha o EOCD mesmo com o comentário do TorrentZip depois dele', () async {
    final server = FakeRangeServer(
        buildZip([entry], comment: 'TORRENTZIPPED-58A7B7DC'));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch),
        orderedEquals(entry));
  });

  test('devolve null quando o servidor ignora o Range e responde 200', () async {
    // O caso do Myrient, seção 5.8 limite 2. Sem esta guarda o parser tentaria
    // achar um EOCD dentro de uma página HTML.
    final server = FakeRangeServer(buildZip([entry]), status: 200);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando não vem Content-Range', () async {
    final server =
        FakeRangeServer(buildZip([entry]), sendContentRange: false);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('devolve null em zip64', () async {
    final server = FakeRangeServer(buildZip([entry], zip64: true));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando o diretório central cai fora do arquivo', () async {
    final server = FakeRangeServer(buildZip([entry], forcedCdOffset: 900000));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando o EOCD não cabe nos 256 bytes finais', () async {
    final server =
        FakeRangeServer(buildZip([entry], comment: 'x' * 300));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('devolve null quando a rede levanta exceção', () async {
    Future<RangeResponse> explode(Uri uri, String range) async =>
        throw const SocketException('sem rede');
    expect(await ZipCentralDirectory.readRaw(uri, explode), isNull);
  });
}
```

- [ ] **Step 3: Rode e veja falhar**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/zip_central_directory.dart'`.

- [ ] **Step 4: Escreva a implementação mínima**

Crie `lib/services/zip_central_directory.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

/// A resposta de uma requisição com header `Range`, reduzida ao que o parser
/// precisa. Existe para o teste poder responder sem rede.
class RangeResponse {
  final int statusCode;
  final String? contentRange;
  final Uint8List bytes;

  const RangeResponse({
    required this.statusCode,
    required this.bytes,
    this.contentRange,
  });
}

/// Busca um intervalo de bytes. [range] já vem pronto, no formato do header:
/// `bytes=-256` ou `bytes=100-199`.
typedef RangeFetch = Future<RangeResponse> Function(Uri uri, String range);

/// Lê o diretório central de um ZIP remoto em duas requisições curtas.
///
/// Dart puro de propósito: `tool/probe_zip_cd.dart` roda isto fora do Flutter.
/// Não adicione import de `package:flutter`.
class ZipCentralDirectory {
  /// Quantos bytes do fim buscar para achar o EOCD. 256 cobre os 22 bytes do
  /// EOCD mais um comentário curto, incluindo o `TORRENTZIPPED-xxxxxxxx` de
  /// 22 caracteres que o archive.org grava. Zip com comentário maior sai fora,
  /// e isso é aceitável: virar duas requisições em três não paga o ganho.
  static const tailBytes = 256;

  /// Teto do que aceitamos bufferizar. Um diretório central acima disso é um
  /// zip com dezenas de milhares de entradas, que não é o caso de uso, e
  /// aceitar significa deixar um servidor hostil encher a memória do app.
  static const maxDirectoryBytes = 8 * 1024 * 1024;

  /// Os bytes crus do diretório central, ou null quando não deu.
  ///
  /// Null nunca é erro fatal: quem chama simplesmente fica com o palpite de
  /// nome. Este método não levanta.
  static Future<Uint8List?> readRaw(Uri uri, RangeFetch fetch) async {
    final RangeResponse tail;
    try {
      tail = await fetch(uri, 'bytes=-$tailBytes');
    } catch (_) {
      return null;
    }
    final total = _totalFrom(tail);
    if (total == null) return null;

    final eocd = _findEocd(tail.bytes);
    if (eocd == null) return null;

    final view = ByteData.sublistView(tail.bytes);
    final size = view.getUint32(eocd + 12, Endian.little);
    final offset = view.getUint32(eocd + 16, Endian.little);

    // 0xFFFFFFFF nos dois campos é o marcador de zip64: o valor real está num
    // registro separado, antes do EOCD. Nenhuma fonte de ROM serve zip64, e
    // implementar isso por completude seria código morto.
    if (size == 0xFFFFFFFF || offset == 0xFFFFFFFF) return null;
    if (size == 0 || size > maxDirectoryBytes) return null;
    if (offset + size > total) return null;

    final RangeResponse body;
    try {
      body = await fetch(uri, 'bytes=$offset-${offset + size - 1}');
    } catch (_) {
      return null;
    }
    if (_totalFrom(body) == null) return null;
    if (body.bytes.length != size) return null;
    return body.bytes;
  }

  /// O tamanho total do arquivo, extraído do `Content-Range`, ou null se a
  /// resposta não for uma resposta parcial de verdade.
  ///
  /// As duas condições juntas são a guarda da seção 5.8, limite 2. Um `200`
  /// significa que o servidor ignorou o `Range` e está mandando o arquivo
  /// inteiro, ou uma página de erro com cara de sucesso.
  static int? _totalFrom(RangeResponse response) {
    if (response.statusCode != HttpStatus.partialContent) return null;
    final header = response.contentRange;
    if (header == null) return null;
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header.trim());
    if (m == null) return null;
    return int.parse(m.group(3)!);
  }

  /// Varre de trás para frente atrás de `PK\x05\x06`. De trás para frente
  /// porque o EOCD é o último registro, mas não necessariamente os últimos
  /// bytes: o comentário vem depois dele.
  static int? _findEocd(Uint8List bytes) {
    if (bytes.length < 22) return null;
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    return null;
  }

  /// O fetch de produção.
  ///
  /// A ordem das linhas importa: **confira o status antes de consumir o
  /// corpo**. Ler primeiro e checar depois significa baixar o arquivo inteiro,
  /// que é exatamente o que a leitura por Range existe para evitar.
  ///
  /// O `HttpClient` segue redirect sozinho e preserva o header `Range` ao
  /// fazê-lo, o que foi conferido contra o archive.org, que responde 302 antes
  /// do 206.
  static Future<RangeResponse> httpRangeFetch(Uri uri, String range) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        return RangeResponse(
          statusCode: response.statusCode,
          bytes: Uint8List(0),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxDirectoryBytes) {
          throw HttpException(
              'resposta parcial acima de $maxDirectoryBytes bytes',
              uri: uri);
        }
      }
      return RangeResponse(
        statusCode: response.statusCode,
        contentRange: response.headers.value(HttpHeaders.contentRangeHeader),
        bytes: builder.toBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
```

- [ ] **Step 5: Rode e veja passar**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: PASS, 9 testes.

- [ ] **Step 6: Commit**

```bash
git add lib/services/zip_central_directory.dart test/support/zip_fixture.dart test/zip_central_directory_test.dart
git commit -m "feat(identidade): diretorio central por Range com as guardas da 5.8"
```

---

### Task 11: as entradas, e a regra de extensão que evita o CRC errado

**Files:**
- Modify: `lib/services/zip_central_directory.dart`
- Create: `tool/probe_zip_cd.dart`
- Test: `test/zip_central_directory_test.dart`

Agora os bytes viram entradas. A parte que merece atenção não é o parser, é o `crcMatchesRom`.

A seção 5.8 do spec, limite 1: **o CRC de uma entrada só é comparável com o pacote quando aquela entrada é a ROM.** Se a fonte servir um zip que contém outro zip, ou um `.7z`, o CRC ali é o do arquivo comprimido interno, e não bate com nada do DAT. Aceitar esse CRC seria pior que não olhar, porque no melhor caso não casa e no pior casa por acidente com o CRC de outro jogo.

- [ ] **Step 1: Escreva os testes que falham**

Acrescente ao `main` de `test/zip_central_directory_test.dart`:

```dart
  group('entradas', () {
    test('lê nome e CRC de uma entrada', () {
      final entries = ZipCentralDirectory.parse(entry);
      expect(entries, hasLength(1));
      expect(entries!.single.name, 'Chrono Trigger (USA).sfc');
      expect(entries.single.crc, '2D206BF7');
    });

    test('lê várias entradas mesmo com extra e comentário entre elas', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001, extraLen: 9))
        ..add(cdEntry('b.sfc', 0x000000FF, commentLen: 5))
        ..add(cdEntry('c.sfc', 0xA31BEAD4));
      final entries = ZipCentralDirectory.parse(blob.toBytes());
      expect(entries?.map((e) => e.name), ['a.sfc', 'b.sfc', 'c.sfc']);
      expect(entries?.map((e) => e.crc),
          ['00000001', '000000FF', 'A31BEAD4']);
    });

    test('crcMatchesRom só aceita a ROM em si', () {
      bool rom(String name) =>
          ZipCentralDirectory.parse(cdEntry(name, 1))!.single.crcMatchesRom;
      expect(rom('Chrono Trigger (USA).sfc'), isTrue);
      expect(rom('Chrono Trigger (USA).iso'), isTrue);
      // Contêiner dentro de contêiner: o CRC é do comprimido, não da ROM.
      expect(rom('Chrono Trigger (USA).zip'), isFalse);
      expect(rom('Chrono Trigger (USA).7z'), isFalse);
      // Não é ROM nenhuma.
      expect(rom('leiame.txt'), isFalse);
    });

    test('para no lixo e devolve o que já tinha lido', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001))
        ..add(Uint8List.fromList(List.filled(60, 0x41)));
      expect(ZipCentralDirectory.parse(blob.toBytes())?.map((e) => e.name),
          ['a.sfc']);
    });

    test('read junta as duas metades e entrega as entradas', () async {
      final server = FakeRangeServer(buildZip([
        cdEntry('Super Mario World (Europe).sfc', 0xA31BEAD4),
        cdEntry('leiame.txt', 0x00000009),
      ]));
      final entries = await ZipCentralDirectory.read(uri, server.fetch);
      expect(entries?.map((e) => e.name),
          ['Super Mario World (Europe).sfc', 'leiame.txt']);
      expect(entries?.where((e) => e.crcMatchesRom).single.crc, 'A31BEAD4');
    });
  });
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: FALHA de compilação, `The method 'parse' isn't defined for the type 'ZipCentralDirectory'`.

- [ ] **Step 3: Escreva a implementação mínima**

No topo de `lib/services/zip_central_directory.dart`, acrescente aos imports:

```dart
import 'dart:convert';

import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';
```

Acrescente a classe, antes de `ZipCentralDirectory`:

```dart
/// Uma entrada do diretório central. [crc] em maiúsculas, oito dígitos, no
/// mesmo formato de `PackDump.crc`.
class ZipEntry {
  final String name;
  final String crc;

  const ZipEntry({required this.name, required this.crc});

  /// Verdadeiro quando este CRC pode ser comparado com o de um dump do pacote.
  ///
  /// Um zip dentro de um zip tem CRC próprio, que é o do comprimido e não o da
  /// ROM. Comparar esse CRC com o pacote é pior que não comparar: no melhor
  /// caso não casa, no pior casa por acidente. Ver a seção 5.8 do spec,
  /// limite 1.
  bool get crcMatchesRom => hasRomExtension(name) && !hasArchiveExtension(name);

  @override
  String toString() => 'ZipEntry($name, $crc)';
}
```

E os dois métodos, dentro de `ZipCentralDirectory`:

```dart
  /// As entradas de um ZIP remoto, ou null quando não deu para ler.
  static Future<List<ZipEntry>?> read(Uri uri, RangeFetch fetch) async {
    final raw = await readRaw(uri, fetch);
    if (raw == null) return null;
    return parse(raw);
  }

  /// Quebra os bytes do diretório central em entradas. Para no primeiro
  /// registro que não começa com `PK\x01\x02` e devolve o que já leu, porque
  /// meia leitura ainda é útil e um erro aqui não deve custar o palpite todo.
  static List<ZipEntry>? parse(Uint8List directory) {
    final view = ByteData.sublistView(directory);
    final entries = <ZipEntry>[];
    var pos = 0;
    while (pos + 46 <= directory.length) {
      if (view.getUint32(pos, Endian.little) != 0x02014b50) break;
      final crc = view.getUint32(pos + 16, Endian.little);
      final nameLen = view.getUint16(pos + 28, Endian.little);
      final extraLen = view.getUint16(pos + 30, Endian.little);
      final commentLen = view.getUint16(pos + 32, Endian.little);
      final nameEnd = pos + 46 + nameLen;
      if (nameEnd > directory.length) break;
      entries.add(ZipEntry(
        // O nome pode ser CP437 ou UTF-8, e o zip só distingue por um bit de
        // flag que quase ninguém grava direito. `allowMalformed` faz o
        // acentuado errado virar U+FFFD em vez de levantar, e o `norm` do
        // matcher come o U+FFFD como pontuação.
        name: utf8.decode(directory.sublist(pos + 46, nameEnd),
            allowMalformed: true),
        crc: formatCrc(crc),
      ));
      pos = nameEnd + extraLen + commentLen;
    }
    return entries.isEmpty ? null : entries;
  }
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: PASS, 14 testes.

- [ ] **Step 5: Escreva a sonda de dado real**

O teste unitário prova o parser contra bytes que o próprio teste montou. Isso não prova que um servidor de verdade coopera. Crie `tool/probe_zip_cd.dart`:

```dart
// Lê o diretório central de um ZIP remoto por Range e imprime as entradas.
// Roda fora do Flutter:
//   dart run tool/probe_zip_cd.dart <url>
import 'dart:io';

import 'package:roms_downloader/services/zip_central_directory.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('uso: dart run tool/probe_zip_cd.dart <url>');
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(args.single);
  final entries =
      await ZipCentralDirectory.read(uri, ZipCentralDirectory.httpRangeFetch);
  if (entries == null) {
    stderr.writeln('nao deu para ler o diretorio central de $uri');
    exitCode = 1;
    return;
  }
  for (final entry in entries) {
    final marca = entry.crcMatchesRom ? 'ROM ' : '    ';
    print('$marca${entry.crc}  ${entry.name}');
  }
}
```

- [ ] **Step 6: Rode a sonda contra o archive.org**

```bash
dart run tool/probe_zip_cd.dart "https://archive.org/download/ef_nintendo_snes_no-intro_2024-04-20/%2796%20Zenkoku%20Koukou%20Soccer%20Senshuken%20%28Japan%29.zip"
```

Expected, exatamente uma linha:

```
ROM 05FBB855  '96 Zenkoku Koukou Soccer Senshuken (Japan).sfc
```

Esse `05FBB855` é o CRC do dump `'96 Zenkoku Koukou Soccer Senshuken (Japan)` no pacote publicado do SNES. Se a linha sair assim, o caminho inteiro está provado em dado real: 302, 206, EOCD atrás do comentário do TorrentZip, segunda requisição de 93 bytes, e um CRC que casa com o pacote.

Se sair `nao deu para ler`, não mexa nas guardas para "fazer funcionar". Rode `curl -sSL -D - -o /dev/null -H 'Range: bytes=-256' <url>` e veja o que o servidor respondeu de verdade antes de mudar qualquer coisa.

- [ ] **Step 7: Commit**

```bash
git add lib/services/zip_central_directory.dart test/zip_central_directory_test.dart tool/probe_zip_cd.dart
git commit -m "feat(identidade): entradas do diretorio central e a regra de extensao"
```

---
### Task 12: confirmar ou corrigir o nome com o CRC do ZIP remoto

**Files:**
- Create: `lib/services/crc_confirm_service.dart`
- Create: `test/support/pack_fixture.dart`
- Modify: `test/pack_matcher_test.dart`
- Test: `test/crc_confirm_service_test.dart`

Aqui os dois eixos se encontram. O eixo de nome deu um palpite; o diretório central do ZIP remoto diz se o palpite está certo, e às vezes diz qual era a resposta.

A regra de decisão é conservadora de propósito:

- Se o nome do arquivo não termina em `.zip`, **nem vá à rede**. Não temos leitor de `.7z` nem de `.rar` por Range, e gastar duas requisições para descobrir isso é desperdício.
- Se o diretório central não veio, fique com o palpite de nome.
- Considere só as entradas em que `crcMatchesRom` é verdadeiro.
- Se essas entradas apontam para **exatamente um** jogo do pacote, esse é o resultado, com tier `checksum`. Zero jogos ou dois jogos diferentes significa que o zip não é conclusivo, e o palpite de nome continua valendo.

Note que "exatamente um jogo" não é o mesmo que "exatamente uma entrada": um zip com os três discos do mesmo jogo resolve para um jogo só, e isso conta.

- [ ] **Step 1: Extraia a fixture do pacote para um lugar compartilhado**

A partir daqui duas suítes precisam do mesmo pacote de teste. Crie `test/support/pack_fixture.dart` com o conteúdo abaixo, que é o `buildPack()` que hoje está no topo de `test/pack_matcher_test.dart`, sem alteração nenhuma:

```dart
import 'dart:convert';

import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Pacote de teste com um caso real para cada tier:
/// - Chrono Trigger tem duas regiões, então exercita tier 1 contra tier 2.
/// - Blue Crystalrod tem o artigo no fim, que é o caso que o `canon` conserta.
/// - HammerLock Wrestling é o par fuzzy que a PoC resolveu certo.
/// - Pro Action Replay MK3 é o par fuzzy que a PoC resolveu **errado**.
/// - Zero 4 Champ RR e RR-Z são dois candidatos fuzzy do mesmo bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/chrono-trigger',
          'title': 'Chrono Trigger',
          'dumps': [
            {'name': 'Chrono Trigger (USA)', 'crc': '2D206BF7'},
            {'name': 'Chrono Trigger (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-blue-crystalrod',
          'title': 'The Blue Crystalrod',
          'dumps': [
            {'name': 'Blue Crystalrod, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/hammerlock-wrestling',
          'title': 'HammerLock Wrestling',
          'dumps': [
            {'name': 'HammerLock Wrestling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/pro-action-replay-mk3',
          'title': 'Pro Action Replay MK3',
          'dumps': [
            {'name': 'Pro Action Replay MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-mario-world',
          'title': 'Super Mario World',
          'dumps': [
            {'name': 'Super Mario World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Mario World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr',
          'title': 'Zero 4 Champ RR',
          'dumps': [
            {'name': 'Zero 4 Champ RR (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/zero-4-champ-rr-z',
          'title': 'Zero 4 Champ RR-Z',
          'dumps': [
            {'name': 'Zero 4 Champ RR-Z (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));
```

Agora em `test/pack_matcher_test.dart`: apague o comentário e a função `buildPack()` inteira, apague o `import 'dart:convert';` e o `import 'package:roms_downloader/models/metadata_pack_model.dart';` que só ela usava, e acrescente depois dos imports de pacote:

```dart
import 'support/pack_fixture.dart';
```

- [ ] **Step 2: Confirme que a extração não quebrou nada**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 18 testes. Se `flutter analyze` reclamar de import não usado em `pack_matcher_test.dart`, é porque sobrou um dos dois imports antigos. Tire.

- [ ] **Step 3: Commit a extração sozinha**

```bash
git add test/pack_matcher_test.dart test/support/pack_fixture.dart
git commit -m "refactor(identidade): fixture do pacote em test/support"
```

- [ ] **Step 4: Escreva os testes que falham**

Crie `test/crc_confirm_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/crc_confirm_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs do pacote de teste, na forma numérica que o diretório central grava.
const chronoUsa = 0x2D206BF7;
const smwEurope = 0xA31BEAD4;

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://exemplo/arquivo.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  CrcConfirmService serving(Uint8List zip) => CrcConfirmService(
        matcher: matcher,
        fetch: FakeRangeServer(zip).fetch,
      );

  test('não vai à rede quando o nome não termina em .zip', () async {
    var chamadas = 0;
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: (u, r) async {
        chamadas++;
        throw StateError('não deveria ter ido à rede');
      },
    );
    final byName = matcher.match('Chrono Trigger (USA).sfc');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).sfc', byName);
    expect(chamadas, 0);
    expect(out, same(byName));
  });

  test('confirma o palpite de nome quando o CRC aponta o mesmo jogo', () async {
    final service = serving(
        buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out!.game.id, 'snes/chrono-trigger');
    expect(out.tier, MatchTier.checksum);
    expect(out.confidence, MatchConfidence.confirmed);
    expect(out.dump?.name, 'Chrono Trigger (USA)');
  });

  test('corrige o palpite de nome quando o CRC aponta outro jogo', () async {
    // O arquivo se chama Chrono Trigger mas contém Super Mario World. O nome
    // mente, o CRC não.
    final service = serving(
        buildZip([cdEntry('rom.sfc', smwEurope)]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    expect(byName!.game.id, 'snes/chrono-trigger');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out!.game.id, 'snes/super-mario-world');
    expect(out.tier, MatchTier.checksum);
    expect(out.dump?.name, 'Super Mario World (Europe)');
  });

  test('fica com o nome quando o servidor não fala Range', () async {
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('rom.sfc', smwEurope)]),
        status: 200,
      ).fetch,
    );
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out, same(byName));
  });

  test('fica com o nome quando o zip tem dois jogos diferentes dentro',
      () async {
    final service = serving(buildZip([
      cdEntry('Chrono Trigger (USA).sfc', chronoUsa),
      cdEntry('Super Mario World (Europe).sfc', smwEurope),
    ]));
    final byName = matcher.match('Chrono Trigger (USA).zip');
    final out = await service.confirm(uri, 'Chrono Trigger (USA).zip', byName);
    expect(out, same(byName));
  });

  test('ignora o que não é ROM e decide pela única que é', () async {
    // Se o filtro de extensão não existisse, o bonus.zip entraria com o CRC do
    // Super Mario World, viraria dois jogos, e o zip seria descartado como
    // inconclusivo. Ver 5.8, limite 1.
    final service = serving(buildZip([
      cdEntry('leiame.txt', 0x00000009),
      cdEntry('bonus.zip', smwEurope),
      cdEntry('Chrono Trigger (USA).sfc', chronoUsa),
    ]));
    final byName = matcher.match('qualquer coisa.zip');
    expect(byName, isNull);
    final out = await service.confirm(uri, 'qualquer coisa.zip', byName);
    expect(out!.game.id, 'snes/chrono-trigger');
    expect(out.tier, MatchTier.checksum);
    expect(out.sourceName, 'qualquer coisa.zip');
  });
}
```

- [ ] **Step 5: Rode e veja falhar**

Run: `flutter test test/crc_confirm_service_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/crc_confirm_service.dart'`.

- [ ] **Step 6: Escreva a implementação mínima**

Crie `lib/services/crc_confirm_service.dart`:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Confirma ou corrige um palpite de nome lendo o CRC da ROM de dentro do ZIP
/// remoto, antes de qualquer download. É o eixo do meio da seção 5.5 do spec.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
class CrcConfirmService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const CrcConfirmService({required this.matcher, required this.fetch});

  /// [byName] é o que o eixo de nome achou, e pode ser null.
  ///
  /// Devolve um match de tier [MatchTier.checksum] quando o ZIP foi
  /// conclusivo, e [byName] intocado em todos os outros casos. Nunca levanta:
  /// falha de rede aqui só significa ficar com o palpite que já se tinha.
  Future<GameMatch?> confirm(
      Uri uri, String sourceName, GameMatch? byName) async {
    // Sem leitor de 7z ou rar por Range, então nem gaste a requisição.
    if (!sourceName.toLowerCase().endsWith('.zip')) return byName;

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return byName;

    final hits = <String, GameMatch>{};
    for (final entry in entries) {
      if (!entry.crcMatchesRom) continue;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null) hits[hit.game.id] = hit;
    }

    // Um jogo só é conclusivo, e três discos do mesmo jogo continuam sendo um
    // jogo só. Zero ou dois não decidem nada, e inventar um critério de
    // desempate aqui seria trocar uma certeza por um palpite.
    if (hits.length != 1) return byName;
    return hits.values.first;
  }
}
```

- [ ] **Step 7: Rode e veja passar**

Run: `flutter test test/crc_confirm_service_test.dart`
Expected: PASS, 6 testes.

- [ ] **Step 8: Commit**

```bash
git add lib/services/crc_confirm_service.dart test/crc_confirm_service_test.dart
git commit -m "feat(identidade): confirmar ou corrigir o nome pelo CRC do zip remoto"
```

---

### Task 13: o eixo local, nome primeiro e CRC só na dúvida

**Files:**
- Create: `lib/services/local_identity_service.dart`
- Test: `test/local_identity_service_test.dart`

A seção 5.7 do spec trata de um caso diferente dos dois anteriores: o arquivo **já está no disco**. Não há rede envolvida e o CRC é calculável de verdade, byte a byte. Só que calcular custa: um ISO de 1,4 GB leva segundos, e uma biblioteca de mil arquivos leva minutos.

A regra da 5.7 resolve isso: **nome primeiro, CRC só na dúvida.**

- Tier `exactName` ou `canonicalName`: aceite e vá embora. Não leia o arquivo.
- Tier `fuzzyName` ou nada: aí sim, calcule o CRC. É o caso raro.

Mais duas decisões que precisam ficar explícitas:

1. **Contêiner não entra no CRC.** Se o arquivo local é `.zip` ou `.7z`, o CRC do arquivo é o do contêiner e não bate com o pacote, pelo mesmo motivo da 5.8 limite 1. Para esses o nome é tudo que temos. Ler o diretório central de um zip **local** resolveria, e é uma extensão natural, mas não é desta fatia.
2. **O cache é da sessão.** A chave é `tamanho|mtime|caminho`: se qualquer um dos três mudar, o arquivo é outro e o CRC é recalculado. O serviço aceita um cache inicial e expõe o que acumulou, para quem quiser persistir depois. Persistir de fato não é desta fatia, porque nesta fatia ninguém ainda chama o serviço em loop.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/local_identity_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';

void main() {
  late Directory tmp;
  late PackMatcher matcher;
  late List<String> lidos;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_identity_test');
    matcher = PackMatcher(buildPack());
    lidos = [];
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File write(String name) =>
      File('${tmp.path}/$name')..writeAsStringSync('conteudo');

  /// Serviço com um CRC falso, para o teste controlar o que o disco "tem" e
  /// contar quantas vezes o arquivo foi lido.
  LocalIdentityService serviceReturning(String crc) => LocalIdentityService(
        matcher: matcher,
        crcOfFile: (file) async {
          lidos.add(file.path);
          return crc;
        },
      );

  test('aceita o nome exato e nem toca no arquivo', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('Chrono Trigger (USA).sfc'));
    expect(m!.tier, MatchTier.exactName);
    expect(m.game.id, 'snes/chrono-trigger');
    expect(lidos, isEmpty);
  });

  test('aceita o nome canônico e nem toca no arquivo', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('The Blue Crystalrod.sfc'));
    expect(m!.tier, MatchTier.canonicalName);
    expect(m.game.id, 'snes/the-blue-crystalrod');
    expect(lidos, isEmpty);
  });

  test('no palpite fuzzy calcula o CRC e corrige o jogo', () async {
    // O nome parece HammerLock Wrestling, mas os bytes são do Pro Action
    // Replay MK3. O CRC ganha.
    final service = serviceReturning('11112222');
    final file = write('Hammer Lock Wrestling (USA).sfc');
    expect(matcher.match('Hammer Lock Wrestling (USA).sfc')!.tier,
        MatchTier.fuzzyName);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/pro-action-replay-mk3');
    expect(lidos, [file.path]);
  });

  test('sem palpite de nome nenhum, o CRC resolve sozinho', () async {
    final service = serviceReturning('A31BEAD4');
    final file = write('rom desconhecida 0042.sfc');
    expect(matcher.match('rom desconhecida 0042.sfc'), isNull);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/super-mario-world');
  });

  test('CRC que não está no pacote devolve o palpite de nome intocado',
      () async {
    final service = serviceReturning('DEADBEEF');
    final m = await service.identify(write('Hammer Lock Wrestling (USA).sfc'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/hammerlock-wrestling');
  });

  test('não calcula CRC de contêiner, porque não seria comparável', () async {
    final service = serviceReturning('11112222');
    final m = await service.identify(write('Hammer Lock Wrestling (USA).zip'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/hammerlock-wrestling');
    expect(lidos, isEmpty);
  });

  test('o cache evita a segunda leitura do mesmo arquivo', () async {
    final service = serviceReturning('11112222');
    final file = write('Hammer Lock Wrestling (USA).sfc');
    await service.identify(file);
    await service.identify(file);
    expect(lidos, hasLength(1));
    expect(service.cache.values, ['11112222']);
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/local_identity_service_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/services/local_identity_service.dart'`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/services/local_identity_service.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

typedef FileCrc = Future<String> Function(File file);

/// O eixo da seção 5.7 do spec: identifica um arquivo que já está no disco.
///
/// Nome primeiro, CRC só na dúvida. Calcular CRC é a operação cara desta
/// fatia, e o tier de nome resolve a esmagadora maioria dos casos de graça.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
class LocalIdentityService {
  final PackMatcher matcher;
  final FileCrc crcOfFile;
  final Map<String, String> _cache;

  LocalIdentityService({
    required this.matcher,
    FileCrc? crcOfFile,
    Map<String, String>? initialCache,
  })  : crcOfFile = crcOfFile ?? crc32OfFile,
        _cache = {...?initialCache};

  /// O que já foi calculado nesta sessão. Chave `tamanho|mtime|caminho`, valor
  /// o CRC em maiúsculas. Exposto para quem quiser persistir; nesta fatia
  /// ninguém persiste.
  Map<String, String> get cache => Map.unmodifiable(_cache);

  Future<GameMatch?> identify(File file) async {
    final name = p.basename(file.path);
    final byName = matcher.match(name);
    if (byName != null &&
        (byName.tier == MatchTier.exactName ||
            byName.tier == MatchTier.canonicalName)) {
      return byName;
    }

    // Um contêiner tem CRC próprio, que não é o da ROM, então calcular seria
    // gastar segundos para comparar com o índice errado. Ver 5.8, limite 1.
    if (hasArchiveExtension(name)) return byName;

    final crc = await _crcOf(file);
    if (crc == null) return byName;
    return matcher.matchCrc(crc, sourceName: name) ?? byName;
  }

  Future<String?> _crcOf(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) return null;
    final key =
        '${stat.size}|${stat.modified.millisecondsSinceEpoch}|${file.path}';
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final crc = await crcOfFile(file);
      _cache[key] = crc;
      return crc;
    } catch (_) {
      // Arquivo sem permissão, meio copiado, ou num pendrive que sumiu. Nada
      // disso justifica derrubar a varredura da biblioteca inteira.
      return null;
    }
  }
}
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/local_identity_service_test.dart`
Expected: PASS, 7 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_identity_service.dart test/local_identity_service_test.dart
git commit -m "feat(identidade): eixo local com nome primeiro e CRC so na duvida"
```

---

### Task 14: a fiação Riverpod

**Files:**
- Create: `lib/providers/identity_provider.dart`
- Test: `test/identity_provider_test.dart`

Dois providers finos por cima do que já existe. O que eles compram é a memoização: construir os três índices do `PackMatcher` custa uma passada por todos os dumps do console, 4267 no SNES, e refazer isso a cada rebuild de widget seria caro à toa. Um `FutureProvider.family` mantém o resultado vivo enquanto alguém observa.

Os dois seguem o mesmo contrato de null do `metadataPackProvider`: console sem pacote no índice devolve null, e quem consome trata isso como "esse console não tem metadados", não como erro.

- [ ] **Step 1: Escreva os testes que falham**

Crie `test/identity_provider_test.dart`. Ele sobrescreve o `metadataPackServiceProvider`, que é o mesmo ponto de entrada que `test/metadata_pack_provider_test.dart` já usa, então o pacote vem de um fetch falso e nada toca a rede nem o disco do usuário.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

const indexJson =
    '{"built":"2026-09-10","packs":[{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","games":1,"aliases":["super_nintendo"]}]}';
const packJson =
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/chrono-trigger","title":"Chrono Trigger","dumps":[{"name":"Chrono Trigger (USA)","crc":"2D206BF7"}]}]}';

const snes = PackTarget('super_nintendo', 'Super Nintendo');
const switchTarget = PackTarget('nintendo_switch', 'Nintendo Switch');

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_provider_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer container() {
    final service = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        if (uri.path.endsWith('index.json')) return utf8.encode(indexJson);
        return gzip.encode(utf8.encode(packJson));
      },
    );
    final c = ProviderContainer(overrides: [
      metadataPackServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('constrói o matcher a partir do pacote do console', () async {
    final matcher = await container().read(packMatcherProvider(snes).future);
    expect(matcher, isNotNull);
    expect(matcher!.match('Chrono Trigger (USA).zip')?.tier,
        MatchTier.exactName);
  });

  test('console sem pacote devolve null em vez de erro', () async {
    final c = container();
    expect(await c.read(packMatcherProvider(switchTarget).future), isNull);
    expect(
        await c.read(localIdentityServiceProvider(switchTarget).future), isNull);
  });

  test('o serviço local reusa o mesmo matcher memoizado', () async {
    final c = container();
    final matcher = await c.read(packMatcherProvider(snes).future);
    final service = await c.read(localIdentityServiceProvider(snes).future);
    expect(service!.matcher, same(matcher));
  });
}
```

- [ ] **Step 2: Rode e veja falhar**

Run: `flutter test test/identity_provider_test.dart`
Expected: FALHA de compilação, `Target of URI doesn't exist: 'package:roms_downloader/providers/identity_provider.dart'`.

- [ ] **Step 3: Escreva a implementação mínima**

Crie `lib/providers/identity_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// O matcher de um console. Null quando o console não tem pacote, que é o
/// mesmo contrato do `metadataPackProvider`.
///
/// Existe para memoizar: os três índices custam uma passada por todos os dumps
/// do console, e refazer isso a cada rebuild não tem cabimento.
final packMatcherProvider =
    FutureProvider.family<PackMatcher?, PackTarget>((ref, target) async {
  final pack = await ref.watch(metadataPackProvider(target).future);
  if (pack == null) return null;
  return PackMatcher(pack);
});

/// O eixo local de um console, por cima do mesmo matcher memoizado.
final localIdentityServiceProvider =
    FutureProvider.family<LocalIdentityService?, PackTarget>(
        (ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return LocalIdentityService(matcher: matcher);
});
```

- [ ] **Step 4: Rode e veja passar**

Run: `flutter test test/identity_provider_test.dart`
Expected: PASS, 3 testes.

- [ ] **Step 5: Rode a suíte inteira e a análise**

Run: `flutter test`
Expected: `+176 -1`. A única falha continua sendo `test/rar_decompress_screen_test.dart`, que é anterior a esta fatia.

Run: `flutter analyze`
Expected: nenhum problema novo.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/identity_provider.dart test/identity_provider_test.dart
git commit -m "feat(identidade): providers do matcher e do eixo local"
```

---

### Task 15: rodar o matcher contra o acervo real

**Files:**
- Create: `tool/verify_matcher.dart`

Os testes das tarefas anteriores provam o comportamento em cima de sete jogos escolhidos a dedo. Esta tarefa prova o **número**: o matcher, rodando sobre o pacote publicado do SNES e sobre a listagem real de um item do archive.org com 4122 arquivos, tem que reproduzir a tabela da seção 5.9 do spec.

Isso não é enfeite. A seção 5.9 é o contrato de qualidade do eixo de nome, e se o Dart divergir do que foi medido em Python, alguma coisa na porta do `norm` ou do `canon` saiu diferente e a fatia 3 vai exibir badge errado em escala.

- [ ] **Step 1: Junte os dois insumos**

O pacote, construído com a ferramenta da fatia 1:

```bash
python3 tool/build_metadata_pack.py --out /tmp/packs-verify --built 2026-09-10 \
  --only nintendo_super_nintendo_entertainment_system
gunzip -c /tmp/packs-verify/nintendo_super_nintendo_entertainment_system.json.gz \
  > /tmp/snes-pack.json
```

A listagem, direto do archive.org:

```bash
curl -sL https://archive.org/metadata/ef_nintendo_snes_no-intro_2024-04-20 \
  -o /tmp/snes-listing.json
```

- [ ] **Step 2: Escreva a ferramenta**

Crie `tool/verify_matcher.dart`:

```dart
// Roda o matcher sobre um pacote real e uma listagem real, e imprime a tabela
// da secao 5.9 do spec. Roda fora do Flutter:
//   dart run tool/verify_matcher.dart <pacote.json> <listagem.json>
import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
        'uso: dart run tool/verify_matcher.dart <pacote.json> <listagem.json>');
    exitCode = 64;
    return;
  }
  final pack = MetadataPack.decode(await File(args[0]).readAsString());
  final matcher = PackMatcher(pack);
  final files = listingNames(
      jsonDecode(await File(args[1]).readAsString()) as Map<String, dynamic>);
  if (files.isEmpty) {
    stderr.writeln('a listagem nao tem nenhum arquivo com extensao de ROM');
    exitCode = 1;
    return;
  }

  final tiers = <MatchTier, int>{for (final t in MatchTier.values) t: 0};
  final hitGames = <String>{};
  final misses = <String>[];
  for (final name in files) {
    final match = matcher.match(name);
    if (match == null) {
      misses.add(name);
      continue;
    }
    tiers[match.tier] = tiers[match.tier]! + 1;
    hitGames.add(match.game.id);
  }

  final total = files.length;
  final attributed = total - misses.length;
  String pct(int n) => (n / total * 100).toStringAsFixed(2);
  String line(String label, int n) =>
      '$label ${n.toString().padLeft(5)}  ${pct(n).padLeft(5)}%';

  print('pacote ${pack.pack}: ${matcher.indexedGames} jogos, '
      '${matcher.indexedCanonKeys} chaves canonicas');
  print('listagem: $total arquivos');
  print(line('tier 1 nome exato     ', tiers[MatchTier.exactName]!));
  print(line('tier 2 titulo canonico', tiers[MatchTier.canonicalName]!));
  print(line('tier 3 similaridade   ', tiers[MatchTier.fuzzyName]!));
  print(line('tier 4 sem palpite    ', misses.length));
  print('cobertura de arquivo $attributed/$total = ${pct(attributed)}%');
  print('cobertura de jogo    ${hitGames.length}/${matcher.indexedGames} = '
      '${(hitGames.length / matcher.indexedGames * 100).toStringAsFixed(2)}%');
  print('');
  print('primeiras falhas:');
  for (final miss in misses.take(15)) {
    print('  $miss');
  }
}

/// Nomes de ROM de uma resposta de `archive.org/metadata/<item>`. Derivativos
/// ficam de fora: sao as capas e os indices que o proprio archive.org gera.
List<String> listingNames(Map<String, dynamic> meta) {
  final out = <String>[];
  for (final entry in (meta['files'] as List? ?? const [])) {
    final file = entry as Map<String, dynamic>;
    if (file['source'] == 'derivative') continue;
    final name = (file['name'] as String).split('/').last;
    if (!hasRomExtension(name)) continue;
    out.add(name);
  }
  return out;
}
```

- [ ] **Step 3: Rode e confira contra a seção 5.9**

Run: `dart run tool/verify_matcher.dart /tmp/snes-pack.json /tmp/snes-listing.json`

Expected, número por número:

```
pacote nintendo_super_nintendo_entertainment_system: 2415 jogos, 2415 chaves canonicas
listagem: 4122 arquivos
tier 1 nome exato       3584  86.95%
tier 2 titulo canonico   444  10.77%
tier 3 similaridade       26   0.63%
tier 4 sem palpite        68   1.65%
cobertura de arquivo 4054/4122 = 98.35%
cobertura de jogo    2342/2415 = 96.98%
```

Estes números não são estimativa: foram medidos sobre este mesmo pacote e esta mesma listagem antes de este plano ser escrito, e são os que a seção 5.9 do spec registra.

**Se divergirem, o problema é a porta do `norm` ou do `canon`, não a ferramenta.** Uma divergência grande no tier 1 contra o tier 2 aponta o `norm`; uma divergência entre tier 2 e tier 4 aponta o `canon`, em geral a regra do artigo invertido. Volte para `test/pack_naming_parity_test.dart` e acrescente ao golden o caso que divergiu.

Uma tolerância que **não** é divergência: se o pacote for reconstruído numa data em que o libretro-database ou o OpenVGDB mudaram, a contagem de jogos muda junto e os percentuais andam um pouco. Nesse caso o que vale é a forma: tier 1 na casa dos 87%, tier 2 na dos 11%, tier 3 abaixo de 1%, cobertura de arquivo acima de 98%.

- [ ] **Step 4: Commit**

```bash
git add tool/verify_matcher.dart
git commit -m "feat(identidade): ferramenta que roda o matcher contra o acervo real"
```

---

## O que esta fatia não faz

Escrito para quem for revisar e sentir falta de alguma coisa. Nada aqui é esquecimento.

- **Nenhuma tela.** Não há grade, badge, cartão de detalhe nem indicador de confiança. `MatchConfidence` existe para a fatia 3 consumir, e é ela que decide como "confirmado", "provável" e "palpite" aparecem para o usuário.
- **Nenhuma fonte.** O `CrcConfirmService` recebe uma `Uri` pronta. Quem produz essa `Uri` a partir de um addon é o `SourceResolver`, que é a fatia 5. Aqui a fonte é sempre um parâmetro.
- **O cache do eixo local não é persistido.** Ele existe e é injetável, mas nesta fatia ninguém chama o serviço em loop, então persistir seria escrever código sem consumidor. A fatia 3, que varre a biblioteca do usuário, é quem vai precisar.
- **Serial como chave em sistema de disco.** A seção 5.6 do spec descreve casar PlayStation e GameCube pelo serial do disco, que é mais robusto que o nome. `PackDump.serial` já vem preenchido pelo pacote da fatia 1, e o matcher ainda não olha para ele. Fica para quando um console de disco entrar de verdade.
- **Diretório central de zip local.** Resolveria o buraco do item 6 da Task 13, arquivo `.zip` no disco do usuário que só tem palpite de nome. É a extensão mais óbvia desta fatia, e continua sendo trabalho futuro.
- **Zip64 e 7z remoto.** Zip64 é recusado explicitamente na Task 10, e `.7z` nem chega a virar requisição na Task 12. Nenhuma fonte conhecida serve os dois, e implementar por completude seria código sem exercício.
