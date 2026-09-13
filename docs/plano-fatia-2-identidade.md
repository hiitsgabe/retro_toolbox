# Slice 2, Identity: implementation plan

> **For whoever executes this:** MANDATORY SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute task by task. The steps use checkboxes (`- [ ]`) for tracking.

**Goal:** give the app the ability to say, for any file name coming from a remote source or from the user's disk, which game of the metadata pack it is, and with what degree of certainty.

**Architecture:** three axes, exactly as section 5 of the spec describes. The name axis is a Dart port of the builder's `norm`/`canon` plus a three tier matcher, and it is free. The CRC axis over HTTP Range reads the central directory of the remote ZIP in two requests and confirms or corrects the name axis before any download. The local axis applies the "name first, CRC only when in doubt" rule of section 5.7 to the files that are already on disk. None of this appears on screen: slice 3 is the consumer.

**Tech Stack:** pure Dart in the utilities (no Flutter import, so they can run under `dart run`), `package:rapidfuzz` for tier 3, `getCrc32` from `package:archive` which is already a dependency, `dart:io HttpClient` with a `Range` header, Riverpod for the wiring, `flutter_test` with no mock, constructor injection.

---

## Before you start: read these three things

1. **`docs/stremio-de-jogos-design.md`, the whole of section 5.** Especially 5.3 (the silent error floor), 5.5 (the final design), 5.7 (the local axis), 5.8 (the mandatory Range guards) and 5.9 (the remeasured numbers). This plan implements section 5 and nothing more.
2. **`tool/build_metadata_pack.py`, lines 169 to 219.** These are the `strip_ext`, `norm`, `display_title` and `canon` functions. Task 1 and Task 2 are the Dart port of them. Do not invent a new normalization: any difference breaks the match with the `id` values that have already been published.
3. **`lib/models/metadata_pack_model.dart`.** This is the matcher's input. `PackGame.dumps` is a list of `PackDump`, and `PackDump.name` is the name of the DAT `game` block, with the region and revision tags preserved. `MetadataPack.byCrc` already exists and is already memoized.

### Commands for this repository

`flutter` is not on the PATH. Every command line in this plan assumes:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
cd /home/exedev/Workspace/retro_toolbox
```

- Dart suite: `flutter test`
- A single file: `flutter test test/pack_naming_test.dart`
- Python suite: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
- Analysis: `flutter analyze`

**Baseline before this slice:** `flutter test` exits with `+100 -1`. The failure is `test/rar_decompress_screen_test.dart`, with a `StateError`, and it predates slice 1. It is not yours. Do not try to fix it. At the end of this slice the expected number is `+176 -1`.

---

## File structure

Eight new production files, one per responsibility. No existing production file is modified, and `pubspec.yaml` does not change: `rapidfuzz`, `archive` and `path` are already dependencies. On the test side, `test/pack_matcher_test.dart` is modified once, in Task 12, so that it imports the shared fixture.

| File | Responsibility | Depends on |
| --- | --- | --- |
| `lib/utils/pack_naming.dart` | `norm`, `displayTitle`, `canon`, and the extension lists. Pure Dart. | nothing |
| `lib/models/game_match_model.dart` | `MatchTier`, `MatchConfidence`, `GameMatch`. | `metadata_pack_model.dart` |
| `lib/services/pack_matcher.dart` | Pack indices and the three name tiers, plus `matchCrc`. Pure Dart. | naming, model, rapidfuzz |
| `lib/utils/file_crc32.dart` | CRC32 of a local file, in chunks, and CRC formatting. | `package:archive` |
| `lib/services/zip_central_directory.dart` | Reads the central directory of a remote ZIP over Range, with the 5.8 guards. | file_crc32, naming |
| `lib/services/crc_confirm_service.dart` | Joins matcher and central directory: confirms or corrects a name match. | matcher, zip cd |
| `lib/services/local_identity_service.dart` | The 5.7 axis: name first, CRC only when in doubt, with cache. | matcher, file_crc32 |
| `lib/providers/identity_provider.dart` | Riverpod wiring. | everything above, `metadata_pack_provider.dart` |

Plus two test helpers, which are not suites and therefore do not end in `_test.dart`:

| File | Responsibility | Created in |
| --- | --- | --- |
| `test/support/zip_fixture.dart` | Builds ZIP bytes and a fake Range server. | Task 10 |
| `test/support/pack_fixture.dart` | The shared `buildPack()`, extracted from the matcher suite. | Task 12 |

And three command line tools:

| File | Responsibility |
| --- | --- |
| `tool/dump_naming_golden.py` | Generates the Python/Dart parity golden from the real DAT. |
| `tool/probe_zip_cd.dart` | Probe: reads the central directory of a real remote ZIP and prints the entries. |
| `tool/verify_matcher.dart` | Runs the matcher against the real pack and the real listing, and checks the section 5.9 numbers. |

Rule that holds for the three files marked "pure Dart": **no `import 'package:flutter/...'`**. They need to run under `dart run`, which is what Task 15 does. If you need logging, use `print` in the utilities or pass a callback; `debugPrint` is out.

---

### Task 1: `norm` and the extensions

**Files:**
- Create: `lib/utils/pack_naming.dart`
- Test: `test/pack_naming_test.dart`

`norm` is the comparable form of a file name: no extension, no accent, no punctuation, lowercase, **with the region and revision tags preserved**. It is what powers tier 1 of the matcher. The reference is `tool/build_metadata_pack.py:185`.

One implementation difference that needs to be clear: Python does `unicodedata.normalize("NFKD", ...)` and discards the combining characters. Dart has no `unicodedata`, so the port uses a fold table. This is safe and provable: the No-Intro and Redump DAT names are **pure ASCII**. 4268 SNES names, 13592 PlayStation, 7701 Nintendo DS and 3692 Game Boy Advance were checked, and none has a character above U+007F. The fold is only exercised on the **remote file name** side, which can come from anywhere, and for that side a Latin table is enough.

- [ ] **Step 1: Write the failing tests**

Create `test/pack_naming_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

void main() {
  group('stripRomExtension', () {
    test('strips the ROM extension', () {
      expect(stripRomExtension('Crystal Vanguard (USA).sfc'), 'Crystal Vanguard (USA)');
      expect(stripRomExtension('Crystal Vanguard (USA).zip'), 'Crystal Vanguard (USA)');
      expect(stripRomExtension('Crystal Vanguard (USA).ZIP'), 'Crystal Vanguard (USA)');
    });

    test('leaves alone what is not a ROM extension', () {
      expect(stripRomExtension('Crystal Vanguard (USA).txt'), 'Crystal Vanguard (USA).txt');
      expect(stripRomExtension('Vol. 3'), 'Vol. 3');
    });

    test('prefers the longer extension', () {
      // .gbc and .gb both match; the longer one is the right one.
      expect(stripRomExtension('Kaelis.gbc'), 'Kaelis');
    });
  });

  group('norm', () {
    test('lowercases and swaps punctuation for space', () {
      expect(norm('Crystal Vanguard (USA)'), 'crystal vanguard (usa)');
      expect(norm('Reso 4 Kkesv HQ-H (Japan)'), 'reso 4 kkesv hq h (japan)');
    });

    test('expands the ampersand', () {
      expect(norm('Zuf & Lgari'), 'zuf and lgari');
    });

    test('strips accents', () {
      expect(norm('Prismón Rojo'), 'prismon rojo');
      expect(norm('Aqtúveh & Atérap'), 'aqtuveh and aterap');
    });

    test('strips the extension before normalizing', () {
      expect(norm('Crystal Vanguard (USA).sfc'), 'crystal vanguard (usa)');
    });

    test('preserves the region and revision tags', () {
      // `!` is disallowed punctuation and becomes a space, and a single space is
      // not collapsed by `\s+`, so the bracket comes out with the space inside.
      // That is what the builder's `norm` does, checked by running the Python
      // itself. Parity with the builder rules here, even if `[ ]` is uglier than
      // `[]`.
      expect(norm('Crystal Vanguard (USA) (Rev 1) [!]'), 'crystal vanguard (usa) (rev 1) [ ]');
    });

    test('a name that is only punctuation becomes empty', () {
      expect(norm('---'), '');
      expect(norm(''), '');
    });
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_naming_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/utils/pack_naming.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/utils/pack_naming.dart`:

```dart
/// Dart port of the builder's name functions (`tool/build_metadata_pack.py`).
///
/// The builder generates the pack and the app consumes it, but the app also
/// needs to normalize names at runtime, because the file name at the remote
/// source never went through the builder. The two implementations have to agree
/// case by case, and that is what `test/pack_naming_parity_test.dart` proves
/// against a golden generated from the real DAT.
///
/// This file is pure Dart on purpose: `tool/verify_matcher.dart` runs it
/// outside Flutter. Do not add an import of `package:flutter`.
library;

/// Extensions used by No-Intro and Redump, plus the packagers the sources
/// serve. Same list as `ROM_EXTS` in the builder.
const romExtensions = <String>[
  '.zip', '.7z', '.sfc', '.smc', '.fig', '.swc', '.bin', '.rar', '.gz',
  '.nes', '.gb', '.gbc', '.gba', '.nds', '.3ds', '.n64', '.z64', '.v64',
  '.md', '.gen', '.gg', '.iso', '.cue', '.chd', '.col', '.int',
];

/// The ones that are a container and not a ROM. This matters for section 5.8 of
/// the spec: the central directory CRC is only comparable with the pack when the
/// entry is the ROM itself. If the entry is another compressed file, the CRC is
/// of the compressed file and matches nothing.
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

/// Accent fold table. Lowercase only, because `norm` already lowercased before
/// folding. Covers Latin-1 and the pieces of Latin Extended that appear in
/// European game titles.
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

/// Comparable form of the name: no extension, no accent, no punctuation, but
/// **with** the region and revision tags. It is the tier 1 axis of the matcher.
String norm(String value) {
  var v = stripRomExtension(value).toLowerCase();
  v = _stripDiacritics(v);
  v = v.replaceAll('&', ' and ');
  v = v.replaceAll(_disallowed, ' ');
  return v.replaceAll(_spaces, ' ').trim();
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_naming_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/pack_naming.dart test/pack_naming_test.dart
git commit -m "feat(identidade): norm e as listas de extensao em Dart"
```

---

### Task 2: `displayTitle` and `canon`

**Files:**
- Modify: `lib/utils/pack_naming.dart`
- Test: `test/pack_naming_test.dart`

`canon` is the grouping key: the title with no region tag, no revision tag, with the article back in front, run through `norm`. It is what powers tier 2.

The detail that cannot be inverted: the article swap happens on the **raw** name, before `norm`, because `norm` eats the comma that separates `Legend of Kaelis` from `The`. The builder does it in this order (`tool/build_metadata_pack.py:196`) and the PoC did it the opposite way. Section 5.9 of the spec records that across the 4122 measured files the two produce the same result, but the builder is what generated the published `id` values, so the builder rules.

- [ ] **Step 1: Write the failing tests**

Append to the end of `test/pack_naming_test.dart`, inside `main`, after `group('norm', ...)`:

```dart
  group('displayTitle', () {
    test('preserves the original case', () {
      expect(displayTitle('Crystal Vanguard (USA)'), 'Crystal Vanguard');
    });

    test('moves the article from the end to the front without touching the rest', () {
      expect(displayTitle('Legend of Kaelis, The (USA)'), 'The Legend of Kaelis');
      expect(displayTitle('Zxia Gztqfevzem, The (Japan)'), 'The Zxia Gztqfevzem');
    });

    test('preserves accent and punctuation', () {
      expect(displayTitle('Prismón Rojo (Spain).gb'), 'Prismón Rojo');
      expect(displayTitle('Super Pixel World 2 - Yuki\'s Island (USA)'),
          'Super Pixel World 2 - Yuki\'s Island');
    });

    test('a name that is only a tag becomes empty', () {
      expect(displayTitle('(USA)'), '');
    });

    test('strips a trailing comma', () {
      expect(displayTitle('Awsoht Dupalj, (USA)'), 'Awsoht Dupalj');
    });
  });

  group('canon', () {
    test('discards region and revision tags', () {
      expect(canon('Crystal Vanguard (USA) (Rev 1)'), 'crystal vanguard');
      expect(canon('Crystal Vanguard (Japan) [T+Eng]'), 'crystal vanguard');
    });

    test('moves the article before normalizing', () {
      expect(canon('Legend of Kaelis, The (USA)'), 'the legend of kaelis');
    });

    test('different regions of the same game give the same key', () {
      expect(canon('Super Pixel World (USA)'), canon('Super Pixel World (Europe)'));
    });

    test('a name that is only a tag becomes an empty key', () {
      expect(canon('(USA)'), '');
    });
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_naming_test.dart`
Expected: compile FAILURE, `The function 'displayTitle' isn't defined`.

- [ ] **Step 3: Write the minimal implementation**

Append to the end of `lib/utils/pack_naming.dart`:

```dart
final _tags = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _trailingArticle = RegExp(
  r'^(.*?), (the|a|an|le|la|les|el|los|das|der|die)$',
  caseSensitive: false,
);

/// Equivalent of Python's `.strip().strip(",").strip()`: trim space, then a
/// comma off both ends, then space again.
String _trimSpaceThenComma(String value) {
  var v = value.trim();
  var start = 0;
  var end = v.length;
  while (start < end && v[start] == ',') start++;
  while (end > start && v[end - 1] == ',') end--;
  return v.substring(start, end).trim();
}

/// Display title from the DAT name: no extension, no tags, with the article back
/// in front, and with the original case and accents intact.
String displayTitle(String datName) {
  var v = stripRomExtension(datName).replaceAll(_tags, ' ');
  v = _trimSpaceThenComma(v.replaceAll(_spaces, ' '));
  final match = _trailingArticle.firstMatch(v);
  if (match != null) v = '${match.group(2)} ${match.group(1)}';
  return v;
}

/// Canonical title: the grouping key of a game. It is the display title run
/// through [norm].
String canon(String value) => norm(displayTitle(value));
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_naming_test.dart`
Expected: PASS, 18 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/pack_naming.dart test/pack_naming_test.dart
git commit -m "feat(identidade): displayTitle e canon em Dart"
```

---

### Task 3: the Python/Dart parity golden

**Files:**
- Create: `tool/dump_naming_golden.py`
- Create: `test/fixtures/naming_golden.json` (generated, and committed)
- Create: `test/pack_naming_parity_test.dart`

Tasks 1 and 2 were written against handmade fixtures. That proves the Dart does what you thought the Python does. The golden proves it does what the Python **actually** does, over real names that nobody cherry picked.

The generator is Python, runs against the real SNES DAT, takes one name every 50 and adds a list of hard, handwritten cases the DAT does not have (extension, underscore, accent, article, trailing comma). The resulting file is committed, so the Dart test needs no network.

- [ ] **Step 1: Write the generator**

Create `tool/dump_naming_golden.py`:

```python
#!/usr/bin/env python3
"""Generate the parity golden between the builder's norm/canon and the app's.

The app reimplements norm, display_title and canon in Dart, because it needs
to normalize at runtime names that never went through the builder. The two
implementations have to agree case by case. This script freezes what the
Python answers, and test/pack_naming_parity_test.dart holds the Dart to it.

Usage:
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

# Cases the DAT does not produce: filename with extension, underscore source,
# accent, inverted article, dangling comma, tag-only name. Already pseudonymized,
# so used verbatim; do not pass through pseudonymize (it is not idempotent).
HANDPICKED = [
    "Crystal Vanguard (USA).sfc",
    "Crystal Vanguard (USA).zip",
    "Crystal_Vanguard_(USA).zip",
    "crystal vanguard (usa)",
    "Legend of Kaelis, The (USA).smc",
    "Zxia Gztqfevzem, The (Japan)",
    "Awsoht Dupalj, (USA)",
    "Prismón Moso (Spain).gb",
    "Aqtúveh & Atérap (Europe)",
    "Zuf & Lgari Lozbillesh (USA)",
    "Super Pixel World 2 - Yuki's Island (USA)",
    "Reso 4 Kkesv HQ-H (Japan)",
    "Nigfseu Wugezcal Kze Zosbue - Miqed Rew '98 (Japan)",
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
    inputs = [pseudonymize(n) for n in sampled] + HANDPICKED
    if len(set(inputs)) != len(inputs):
        raise SystemExit("pseudonymizer collapsed distinct inputs")
    cases = []
    for name in inputs:
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
    print("{} cases in {}".format(len(cases), OUT))


if __name__ == "__main__":
    main()
```

`b.urllib.parse.quote` works because `build_metadata_pack.py` imports `urllib.parse` at the top of the module. Same URL construction as the builder's `main`, line 476.

- [ ] **Step 2: Run the generator**

Run: `python3 tool/dump_naming_golden.py`
Expected: `103 cases in /home/exedev/Workspace/retro_toolbox/test/fixtures/naming_golden.json`. That is 86 sampled (4268 divided by 50, rounded up) plus 17 handwritten. If the DAT has changed size the first number changes, and that is not a problem.

- [ ] **Step 3: Write the parity test**

Create `test/pack_naming_parity_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Proves that the Dart port of `norm`, `displayTitle` and `canon` agrees with
/// the Python builder case by case, over real SNES DAT names plus a list of
/// hard cases. The golden is generated by `tool/dump_naming_golden.py`.
///
/// If this test breaks after you touch the builder, the right answer is almost
/// always to regenerate the golden and align the Dart, not to relax the test.
void main() {
  late List<Map<String, dynamic>> cases;

  setUpAll(() {
    final raw = File('test/fixtures/naming_golden.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    cases = (decoded['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(50), reason: 'golden empty or truncated');
  });

  test('norm agrees with the builder on every golden case', () {
    for (final c in cases) {
      expect(norm(c['input'] as String), c['norm'],
          reason: 'norm diverged on "${c['input']}"');
    }
  });

  test('displayTitle agrees with the builder on every golden case', () {
    for (final c in cases) {
      expect(displayTitle(c['input'] as String), c['displayTitle'],
          reason: 'displayTitle diverged on "${c['input']}"');
    }
  });

  test('canon agrees with the builder on every golden case', () {
    for (final c in cases) {
      expect(canon(c['input'] as String), c['canon'],
          reason: 'canon diverged on "${c['input']}"');
    }
  });
}
```

- [ ] **Step 4: Run and resolve the divergences**

Run: `flutter test test/pack_naming_parity_test.dart`
Expected: PASS, 3 tests.

If any case diverges, the message says which input and which function. **Fix the Dart, not the golden.** The likely divergences, in order of probability:

- an accented character outside the `_fold` table. Add the missing line.
- ordering in `_trimSpaceThenComma`. The Python is `.strip()`, `.strip(",")`, `.strip()`, in that order.
- the article regex with `caseSensitive: true` by mistake.

- [ ] **Step 5: Commit**

```bash
git add tool/dump_naming_golden.py test/fixtures/naming_golden.json test/pack_naming_parity_test.dart
git commit -m "test(identidade): golden de paridade entre o norm do builder e o do app"
```

---

### Task 4: the match model

**Files:**
- Create: `lib/models/game_match_model.dart`
- Test: `test/game_match_model_test.dart`

Section 5.5 of the spec requires that "each match carry a confidence derived from the tier" and that "tier 3 never be presented as certainty". This becomes two enums: the tier, which is how the match was obtained, and the confidence, which is what the UI can assert. Slice 3 reads the confidence and does not need to know what a tier is.

- [ ] **Step 1: Write the failing tests**

Create `test/game_match_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

const _game = PackGame(
  id: 'snes/crystal-vanguard',
  title: 'Crystal Vanguard',
  dumps: [PackDump(name: 'Crystal Vanguard (USA)', crc: '2D206BF7')],
);

void main() {
  test('checksum is the only confirmed confidence', () {
    expect(MatchTier.checksum.confidence, MatchConfidence.confirmed);
  });

  test('the two reliable name tiers are likely, not confirmed', () {
    expect(MatchTier.exactName.confidence, MatchConfidence.likely);
    expect(MatchTier.canonicalName.confidence, MatchConfidence.likely);
  });

  test('fuzzy is a guess', () {
    expect(MatchTier.fuzzyName.confidence, MatchConfidence.guess);
  });

  test('the match exposes its own tier confidence', () {
    const match = GameMatch(
      game: _game,
      tier: MatchTier.fuzzyName,
      sourceName: 'Crystal Vangard (USA).zip',
      score: 93.5,
    );
    expect(match.confidence, MatchConfidence.guess);
    expect(match.score, 93.5);
    expect(match.dump, isNull);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/game_match_model_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/models/game_match_model.dart`:

```dart
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// How the match was obtained. The declaration order is the preference order:
/// the matcher tries top to bottom and stops at the first one that resolves.
enum MatchTier {
  /// The CRC32 matched a pack dump. It is the only tier that does not err.
  checksum,

  /// `norm` of the file name equals `norm` of a dump name.
  exactName,

  /// `canon` of the file name equals `canon` of a pack game. Matches region and
  /// revision variants, which is the common case.
  canonicalName,

  /// Edit similarity above the cutoff. It errs: section 5.9 of the spec measured
  /// at least 4 wrong targets in 26 cases, against a 0.63% coverage gain. It
  /// exists because the gain is free, and it never becomes certainty.
  fuzzyName,
}

/// What the screen can assert. Derives from the tier and exists so slice 3 does
/// not have to redecide this in every widget.
enum MatchConfidence { confirmed, likely, guess }

extension MatchTierConfidence on MatchTier {
  MatchConfidence get confidence => switch (this) {
        MatchTier.checksum => MatchConfidence.confirmed,
        MatchTier.exactName => MatchConfidence.likely,
        MatchTier.canonicalName => MatchConfidence.likely,
        MatchTier.fuzzyName => MatchConfidence.guess,
      };
}

/// A source file attributed to a pack game.
///
/// [dump] is only filled when the tier identifies **which** version, that is on
/// `checksum` and `exactName`. The canonical and fuzzy tiers resolve the game,
/// not the version, and leave [dump] null on purpose.
class GameMatch {
  final PackGame game;
  final MatchTier tier;

  /// The file name at the source, raw, the way the source gave it.
  final String sourceName;

  final PackDump? dump;

  /// 0 to 100. Only the fuzzy tier uses it; the others stay at 100.
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

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/game_match_model_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/game_match_model.dart test/game_match_model_test.dart
git commit -m "feat(identidade): modelo de match com tier e confianca"
```

---

### Task 5: the matcher and tier 1

**Files:**
- Create: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

`PackMatcher` takes a `MetadataPack` and builds three indices once, in the constructor. After that each `match` is a sequence of cheap lookups.

The indices:

- `_byName`: `norm(dump.name)` to the game plus dump pair. It is tier 1.
- `_byCanon`: `canon(dump.name)` to the game. It is tier 2. The first occurrence wins, which is the same rule as the builder's `collapse`.
- `_byHead`: the first four characters of the first token of the canonical key to the list of canonical keys. It exists so tier 3 does not compare against the 2415 pack keys on every miss. It is the same optimization as the PoC.

All fixtures in this test file come from the same small pack, built at the top. The names are not invented: they are real SNES DAT cases chosen because each one exercises a tier.

- [ ] **Step 1: Write the failing tests**

Create `test/pack_matcher_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// Test pack with a real case for each tier:
/// - Crystal Vanguard has two regions, so it exercises tier 1 against tier 2.
/// - Zxia Gztqfevzem has the article at the end, which is the case `canon` fixes.
/// - CopperBolt Grappling is the fuzzy pair the PoC resolved correctly.
/// - Duo Vector Recoil MK3 is the fuzzy pair the PoC resolved **wrong**.
/// - Reso 4 Kkesv HQ and HQ-H are two fuzzy candidates in the same bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/crystal-vanguard',
          'title': 'Crystal Vanguard',
          'dumps': [
            {'name': 'Crystal Vanguard (USA)', 'crc': '2D206BF7'},
            {'name': 'Crystal Vanguard (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-zxia-gztqfevzem',
          'title': 'The Zxia Gztqfevzem',
          'dumps': [
            {'name': 'Zxia Gztqfevzem, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/copperbolt-grappling',
          'title': 'CopperBolt Grappling',
          'dumps': [
            {'name': 'CopperBolt Grappling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/duo-vector-recoil-mk3',
          'title': 'Duo Vector Recoil MK3',
          'dumps': [
            {'name': 'Duo Vector Recoil MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-pixel-world',
          'title': 'Super Pixel World',
          'dumps': [
            {'name': 'Super Pixel World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Pixel World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq',
          'title': 'Reso 4 Kkesv HQ',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq-h',
          'title': 'Reso 4 Kkesv HQ-H',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ-H (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));

void main() {
  late PackMatcher matcher;

  setUp(() => matcher = PackMatcher(buildPack()));

  group('tier 1, exact name', () {
    test('matches the dump name letter by letter', () {
      final m = matcher.match('Crystal Vanguard (USA)');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.exactName);
      expect(m.game.id, 'snes/crystal-vanguard');
      expect(m.sourceName, 'Crystal Vanguard (USA)');
    });

    test('matches ignoring the file extension', () {
      expect(matcher.match('Crystal Vanguard (USA).zip')?.tier, MatchTier.exactName);
      expect(matcher.match('Crystal Vanguard (USA).sfc')?.tier, MatchTier.exactName);
    });

    test('matches ignoring case, underscore and punctuation', () {
      final m = matcher.match('crystal_vanguard_(usa).ZIP');
      expect(m?.tier, MatchTier.exactName);
      expect(m?.game.id, 'snes/crystal-vanguard');
    });

    test('the exact tier returns the concrete dump, with that region CRC', () {
      expect(matcher.match('Crystal Vanguard (USA)')?.dump?.crc, '2D206BF7');
      expect(matcher.match('Crystal Vanguard (Japan)')?.dump?.crc, 'ABCD1234');
    });

    test('returns null when nothing matches in any tier', () {
      expect(matcher.match('Something That Does Not Exist (USA).zip'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_matcher_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/services/pack_matcher.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/services/pack_matcher.dart`:

```dart
import 'package:rapidfuzz/rapidfuzz.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Tier 3 cutoff, on the 0 to 100 scale of `rapidfuzz.ratio`.
///
/// The value comes from the PoC, which used `difflib.SequenceMatcher` with a
/// 0.90 cutoff. Section 5.9 of the spec records that the two metrics resolve the
/// same 26 files to the same targets at this cutoff, so swapping libraries does
/// not call for recalibration.
const fuzzyCutoff = 90.0;

/// Matches a file name to a metadata pack game.
///
/// Three name tiers, in the order of section 5.5 of the spec: exact name,
/// canonical title, edit similarity. Plus a fourth axis, `matchCrc`, which is
/// the only one that does not err.
///
/// Pure Dart on purpose: `tool/verify_matcher.dart` runs this class outside
/// Flutter. Do not add an import of `package:flutter`.
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

  /// The first four characters of the first token. Same bucket as the PoC:
  /// it only serves to keep tier 3 from scanning the whole pack on every miss.
  static String _head(String canonKey) {
    final first = canonKey.split(' ').first;
    return first.length <= 4 ? first : first.substring(0, 4);
  }

  /// How many games and how many canonical keys the matcher indexed. Serves
  /// `tool/verify_matcher.dart` and diagnostics.
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

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): PackMatcher com indices e o tier de nome exato"
```

---

### Task 6: tier 2, canonical title

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

Tier 2 matches variants: another region, another revision, beta, prototype. It resolves the **game**, not the version, and for that reason leaves `dump` null. This is the tier that grows the most when the source is not a No-Intro mirror, and it accounts for 10.77% of the files in the section 5.9 measurement.

- [ ] **Step 1: Write the failing tests**

Append to `main` in `test/pack_matcher_test.dart`, after `group('tier 1, exact name', ...)`:

```dart
  group('tier 2, canonical title', () {
    test('matches when only region and revision differ', () {
      final m = matcher.match('Crystal Vanguard (Europe) (Rev 1).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/crystal-vanguard');
    });

    test('matches when the article is inverted on both sides', () {
      // In the pack the dump is "Zxia Gztqfevzem, The (Japan)". The source
      // writes the article in front. `canon` puts both in the same form.
      final m = matcher.match('The Zxia Gztqfevzem (Japan).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/the-zxia-gztqfevzem');
    });

    test('the canonical tier resolves the game not the version, so no dump', () {
      expect(matcher.match('Crystal Vanguard (Europe) (Rev 1).zip')?.dump, isNull);
    });

    test('the exact tier beats the canonical when both would match', () {
      // "Super Pixel World (Europe)" matches exact on the second dump and would
      // match canonical on the whole game. The exact one has to win, because
      // only it knows which of the two regions it is.
      final m = matcher.match('Super Pixel World (Europe).sfc');
      expect(m!.tier, MatchTier.exactName);
      expect(m.dump?.crc, 'A31BEAD4');
    });
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FAILURE. The first three tests of the new group fail with `Expected: not null, Actual: <null>`. The fourth passes, because tier 1 already resolves it.

- [ ] **Step 3: Write the minimal implementation**

In `lib/services/pack_matcher.dart`, replace the body of `match` with:

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

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): tier de titulo canonico no PackMatcher"
```

---

### Task 7: tier 3, similarity, and the error it carries

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

Tier 3 yields 0.63% coverage and errs on at least 15% of what it resolves. It exists because the gain is free and because the alternative, showing nothing, is also bad. What cannot happen is the screen saying it is certain. The `Duo Vector Recoil MK2` test exists precisely to freeze that behavior: the match comes out wrong **and** comes out marked as a guess.

- [ ] **Step 1: Write the failing tests**

Append to `main` in `test/pack_matcher_test.dart`:

```dart
  group('tier 3, similarity', () {
    test('matches above the cutoff', () {
      // "Copper Bolt" against "CopperBolt", one space of difference: 97.56.
      final m = matcher.match('Copper Bolt Grappling (USA).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/copperbolt-grappling');
    });

    test('does not match below the cutoff', () {
      // 47.46 against "crystal vanguard".
      expect(
        matcher.match('Crystal Vanguard 2 - Ressurection of the Ancients (USA).zip'),
        isNull,
      );
    });

    test('the score stays between the cutoff and one hundred', () {
      final m = matcher.match('Copper Bolt Grappling (USA).zip')!;
      expect(m.score, greaterThanOrEqualTo(fuzzyCutoff));
      expect(m.score, lessThan(100));
    });

    test('picks the highest scoring candidate, not the first in the bucket', () {
      // The "reso" bucket has "reso 4 kkesv hq" (90.32) before
      // "reso 4 kkesv hq h" (96.97). The second one is the right one.
      final m = matcher.match('Reso4 Kkesv HQ-H (Japan).zip');
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/reso-4-kkesv-hq-h');
    });

    test('tier 3 errs, and the model says it is a guess', () {
      // Real PoC case: MK2 resolves to MK3 with 95.24. The digit at the end of
      // the title is exactly what edit distance does not see. See section 5.9 of
      // the spec.
      final m = matcher.match('Duo Vector Recoil MK2 (Europe) (Unl) [b].zip');
      expect(m!.game.id, 'snes/duo-vector-recoil-mk3');
      expect(m.confidence, MatchConfidence.guess);
    });

    test('scans the whole pack when the first token bucket does not exist', () {
      // "ropperbolt" falls in the "ropp" bucket, which does not exist. Without
      // the fallback the 95.00 match against "copperbolt grappling" would be lost.
      final m = matcher.match('Ropperbolt Grappling.zip');
      expect(m!.game.id, 'snes/copperbolt-grappling');
      expect(m.tier, MatchTier.fuzzyName);
    });
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_matcher_test.dart`
Expected: FAILURE. Five of the six new tests fail with null. The `does not match below the cutoff` one passes, because today everything that reaches there returns null.

- [ ] **Step 3: Write the minimal implementation**

In `lib/services/pack_matcher.dart`, replace the final `return null;` of `match` with:

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

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): tier de similaridade com corte em 90"
```

---

### Task 8: the checksum axis

**Files:**
- Modify: `lib/services/pack_matcher.dart`
- Test: `test/pack_matcher_test.dart`

The only tier that does not err. The index already exists: `MetadataPack.byCrc` was built in slice 1 and is memoized. What is missing is wrapping it in a `GameMatch` and normalizing the hexadecimal case, because the caller may come from the central directory of a ZIP, from the CRC of a local file, or from an API, and each writes in its own case.

- [ ] **Step 1: Write the failing tests**

Append to `main` in `test/pack_matcher_test.dart`:

```dart
  group('checksum axis', () {
    test('matches the uppercase CRC and brings the right dump', () {
      final m = matcher.matchCrc('A31BEAD4', sourceName: 'anything.zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.checksum);
      expect(m.confidence, MatchConfidence.confirmed);
      expect(m.game.id, 'snes/super-pixel-world');
      expect(m.dump?.name, 'Super Pixel World (Europe)');
      expect(m.sourceName, 'anything.zip');
    });

    test('matches the lowercase CRC', () {
      expect(matcher.matchCrc('a31bead4')?.game.id, 'snes/super-pixel-world');
    });

    test('returns null for a CRC that is not in the pack', () {
      expect(matcher.matchCrc('DEADBEEF'), isNull);
    });
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/pack_matcher_test.dart`
Expected: compile FAILURE, `The method 'matchCrc' isn't defined for the type 'PackMatcher'`.

- [ ] **Step 3: Write the minimal implementation**

Append to `PackMatcher`, after `match`:

```dart
  /// The axis that does not err. [crc] can come in any case.
  ///
  /// Caller beware: the CRC has to be the one of the **ROM**, not of the file
  /// the source serves. A ZIP has its own CRC, and it is not in the pack. See
  /// section 5.8 of the spec, limit 1.
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

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 18 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pack_matcher.dart test/pack_matcher_test.dart
git commit -m "feat(identidade): matchCrc, o eixo que nao erra"
```

---
### Task 9: CRC32 of a local file, in chunks

**Files:**
- Create: `lib/utils/file_crc32.dart`
- Test: `test/file_crc32_test.dart`

Two small functions, but they come before the next three tasks because all of them use `formatCrc`. `getCrc32` from `package:archive`, which is already an app dependency, accepts a previous CRC precisely so it can be chained. This matters: a GameCube ISO is 1.4 GB, and reading it all into memory to compute four bytes of hash crashes the app on a phone.

- [ ] **Step 1: Write the failing tests**

Create `test/file_crc32_test.dart`:

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

  test('formatCrc gives eight uppercase digits with leading zeros', () {
    expect(formatCrc(0), '00000000');
    expect(formatCrc(0xABCDE), '000ABCDE');
    expect(formatCrc(0xA31BEAD4), 'A31BEAD4');
  });

  test('crc32OfFile matches the CRC of the whole content', () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final file = File('${tmp.path}/small.sfc')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });

  test('chains correctly on a file large enough to span several chunks',
      () async {
    // 512 KB forces openRead to deliver more than one chunk. If the getCrc32
    // chaining were wrong, this test would be the only one to catch it.
    final bytes = Uint8List.fromList(List.generate(512 * 1024, (i) => i % 253));
    final file = File('${tmp.path}/large.iso')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/file_crc32_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/utils/file_crc32.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/utils/file_crc32.dart`:

```dart
import 'dart:io';

import 'package:archive/archive.dart';

/// CRC32 of a local file, read in chunks.
///
/// `getCrc32` takes the previous CRC as its second argument and continues from
/// where it left off, so we never need the whole file in memory.
Future<String> crc32OfFile(File file) async {
  var crc = 0;
  await for (final chunk in file.openRead()) {
    crc = getCrc32(chunk, crc);
  }
  return formatCrc(crc);
}

/// Eight hexadecimal digits in uppercase, which is how the DAT writes it and how
/// `PackDump.crc` stores it. Without this the comparison becomes a case lottery.
String formatCrc(int crc) =>
    (crc & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/file_crc32_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/file_crc32.dart test/file_crc32_test.dart
git commit -m "feat(identidade): CRC32 de arquivo local em pedacos"
```

---

### Task 10: the central directory over Range, and the 5.8 guards

**Files:**
- Create: `lib/services/zip_central_directory.dart`
- Create: `test/support/zip_fixture.dart`
- Test: `test/zip_central_directory_test.dart`

This is the piece that lets the app confirm a file's identity **before** downloading 800 KB of it. The trick is old and is the same one remote `unzip -l` uses: the ZIP keeps an index at the end, and you can fetch only the end.

The path has two requests:

1. `Range: bytes=-256`. The last 256 bytes contain the *end of central directory*, the EOCD, which has 22 fixed bytes and says where the central directory starts and how much it takes.
2. `Range: bytes=<offset>-<offset+size-1>`. The central directory itself.

It was checked against a real archive.org file, `'96 Zenith Cup Soccer (Japan).zip`, of 840120 bytes: the first request comes back `206` with `content-range: bytes 839864-840119/840120`, the EOCD is at offset 212 of the 256 bytes, the central directory is 93 bytes starting at 839983, and the CRC inside it is `05FBB855`, which is exactly the CRC of the dump `'96 Zenith Cup Soccer (Japan)` in the published SNES pack. The whole path works on real data.

The layout the parser reads, all little-endian:

| Structure | Field | Offset |
| --- | --- | --- |
| EOCD | signature `PK\x05\x06`, `0x06054b50` | +0 |
| EOCD | central directory size | +12 |
| EOCD | central directory offset | +16 |
| EOCD | comment size | +20 |
| Entry | signature `PK\x01\x02`, `0x02014b50` | +0 |
| Entry | CRC32 | +16 |
| Entry | name size | +28 |
| Entry | extra size | +30 |
| Entry | comment size | +32 |
| Entry | the name | +46 |

**The guards are the point of this task, not the parser.** Section 5.8 of the spec records that a server may ignore the `Range` header and return `200` with the whole file, or worse, an HTML page. Myrient does this. If the code trusts the status, it will try to find an EOCD inside HTML and, best case, not find it; worst case, download the whole file to find out. So: **the status has to be exactly 206, and the `Content-Range` has to exist and match the format**. Without both, the return is null and the caller carries on with the name.

This task delivers up to the raw bytes of the central directory. Task 11 turns them into entries.

- [ ] **Step 1: Write the zip fixture**

Create `test/support/zip_fixture.dart`. It is not a test file, it is a helper: `flutter test` only runs `*_test.dart`, so it does not become an empty suite.

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:roms_downloader/services/zip_central_directory.dart';

/// A central directory entry: 46 fixed bytes, the name, and the extra and
/// comment if requested. Only the fields the parser reads are filled, which is
/// what a real zip also does with most of them.
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

/// Builds a whole zip: a block of zeros in place of the local entries, the
/// central directory, the EOCD, and a comment after it.
///
/// The comment after the EOCD is not a test invention: TorrentZip, which is the
/// format archive.org serves, writes `TORRENTZIPPED-xxxxxxxx` there. If the
/// parser assumed the EOCD were the last 22 bytes of the file, it would break
/// across all of the archive.org collection.
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

/// Fake Range server. Keeps what was asked, so the test can confirm there were
/// two short requests and not the whole file.
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

- [ ] **Step 2: Write the failing tests**

Create `test/zip_central_directory_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/zip_fixture.dart';

void main() {
  final uri = Uri.parse('https://example/file.zip');
  final entry = cdEntry('Crystal Vanguard (USA).sfc', 0x2D206BF7);

  test('returns exactly the central directory bytes', () async {
    final server = FakeRangeServer(buildZip([entry]));
    final raw = await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(raw, isNotNull);
    expect(raw, orderedEquals(entry));
  });

  test('makes two requests: the suffix and the exact range', () async {
    final server = FakeRangeServer(buildZip([entry], localBytes: 500));
    await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(server.asked, [
      'bytes=-256',
      'bytes=500-${500 + entry.length - 1}',
    ]);
  });

  test('finds the EOCD even with the TorrentZip comment after it', () async {
    final server = FakeRangeServer(
        buildZip([entry], comment: 'TORRENTZIPPED-58A7B7DC'));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch),
        orderedEquals(entry));
  });

  test('returns null when the server ignores the Range and answers 200', () async {
    // The Myrient case, section 5.8 limit 2. Without this guard the parser would
    // try to find an EOCD inside an HTML page.
    final server = FakeRangeServer(buildZip([entry]), status: 200);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when no Content-Range comes', () async {
    final server =
        FakeRangeServer(buildZip([entry]), sendContentRange: false);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('returns null on zip64', () async {
    final server = FakeRangeServer(buildZip([entry], zip64: true));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when the central directory falls outside the file', () async {
    final server = FakeRangeServer(buildZip([entry], forcedCdOffset: 900000));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when the EOCD does not fit in the last 256 bytes', () async {
    final server =
        FakeRangeServer(buildZip([entry], comment: 'x' * 300));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('returns null when the network throws', () async {
    Future<RangeResponse> explode(Uri uri, String range) async =>
        throw const SocketException('no network');
    expect(await ZipCentralDirectory.readRaw(uri, explode), isNull);
  });
}
```

- [ ] **Step 3: Run and watch it fail**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/services/zip_central_directory.dart'`.

- [ ] **Step 4: Write the minimal implementation**

Create `lib/services/zip_central_directory.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

/// The response of a request with a `Range` header, reduced to what the parser
/// needs. Exists so the test can respond without network.
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

/// Fetches a byte range. [range] comes ready, in the header format:
/// `bytes=-256` or `bytes=100-199`.
typedef RangeFetch = Future<RangeResponse> Function(Uri uri, String range);

/// Reads the central directory of a remote ZIP in two short requests.
///
/// Pure Dart on purpose: `tool/probe_zip_cd.dart` runs this outside Flutter.
/// Do not add an import of `package:flutter`.
class ZipCentralDirectory {
  /// How many bytes from the end to fetch to find the EOCD. 256 covers the 22
  /// EOCD bytes plus a short comment, including the 22 character
  /// `TORRENTZIPPED-xxxxxxxx` that archive.org writes. A zip with a longer
  /// comment falls out, and that is acceptable: turning one request in three
  /// into two does not pay off.
  static const tailBytes = 256;

  /// Ceiling of what we accept to buffer. A central directory above this is a
  /// zip with tens of thousands of entries, which is not the use case, and
  /// accepting it means letting a hostile server fill the app's memory.
  static const maxDirectoryBytes = 8 * 1024 * 1024;

  /// The raw bytes of the central directory, or null when it did not work.
  ///
  /// Null is never a fatal error: the caller simply keeps the name guess. This
  /// method does not throw.
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

    // 0xFFFFFFFF in both fields is the zip64 marker: the real value is in a
    // separate record, before the EOCD. No ROM source serves zip64, and
    // implementing it for completeness would be dead code.
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

  /// The total file size, extracted from the `Content-Range`, or null if the
  /// response is not a real partial response.
  ///
  /// The two conditions together are the guard of section 5.8, limit 2. A `200`
  /// means the server ignored the `Range` and is sending the whole file, or an
  /// error page dressed up as success.
  static int? _totalFrom(RangeResponse response) {
    if (response.statusCode != HttpStatus.partialContent) return null;
    final header = response.contentRange;
    if (header == null) return null;
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header.trim());
    if (m == null) return null;
    return int.parse(m.group(3)!);
  }

  /// Scans backwards looking for `PK\x05\x06`. Backwards because the EOCD is the
  /// last record, but not necessarily the last bytes: the comment comes after
  /// it.
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

  /// The production fetch.
  ///
  /// Line order matters: **check the status before consuming the body**. Reading
  /// first and checking later means downloading the whole file, which is exactly
  /// what reading by Range exists to avoid.
  ///
  /// `HttpClient` follows redirects on its own and preserves the `Range` header
  /// when it does, which was checked against archive.org, which answers 302
  /// before the 206.
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
              'partial response above $maxDirectoryBytes bytes',
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

- [ ] **Step 5: Run and watch it pass**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/services/zip_central_directory.dart test/support/zip_fixture.dart test/zip_central_directory_test.dart
git commit -m "feat(identidade): diretorio central por Range com as guardas da 5.8"
```

---

### Task 11: the entries, and the extension rule that avoids the wrong CRC

**Files:**
- Modify: `lib/services/zip_central_directory.dart`
- Create: `tool/probe_zip_cd.dart`
- Test: `test/zip_central_directory_test.dart`

Now the bytes become entries. The part that deserves attention is not the parser, it is `crcMatchesRom`.

Section 5.8 of the spec, limit 1: **an entry's CRC is only comparable with the pack when that entry is the ROM.** If the source serves a zip that contains another zip, or a `.7z`, the CRC there is that of the inner compressed file, and does not match anything in the DAT. Accepting that CRC would be worse than not looking, because best case it does not match and worst case it matches another game's CRC by accident.

- [ ] **Step 1: Write the failing tests**

Append to `main` in `test/zip_central_directory_test.dart`:

```dart
  group('entries', () {
    test('reads name and CRC of an entry', () {
      final entries = ZipCentralDirectory.parse(entry);
      expect(entries, hasLength(1));
      expect(entries!.single.name, 'Crystal Vanguard (USA).sfc');
      expect(entries.single.crc, '2D206BF7');
    });

    test('reads several entries even with extra and comment between them', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001, extraLen: 9))
        ..add(cdEntry('b.sfc', 0x000000FF, commentLen: 5))
        ..add(cdEntry('c.sfc', 0xA31BEAD4));
      final entries = ZipCentralDirectory.parse(blob.toBytes());
      expect(entries?.map((e) => e.name), ['a.sfc', 'b.sfc', 'c.sfc']);
      expect(entries?.map((e) => e.crc),
          ['00000001', '000000FF', 'A31BEAD4']);
    });

    test('crcMatchesRom only accepts the ROM itself', () {
      bool rom(String name) =>
          ZipCentralDirectory.parse(cdEntry(name, 1))!.single.crcMatchesRom;
      expect(rom('Crystal Vanguard (USA).sfc'), isTrue);
      expect(rom('Crystal Vanguard (USA).iso'), isTrue);
      // Container within container: the CRC is of the compressed file, not the ROM.
      expect(rom('Crystal Vanguard (USA).zip'), isFalse);
      expect(rom('Crystal Vanguard (USA).7z'), isFalse);
      // Not a ROM at all.
      expect(rom('readme.txt'), isFalse);
    });

    test('stops at garbage and returns what it had already read', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001))
        ..add(Uint8List.fromList(List.filled(60, 0x41)));
      expect(ZipCentralDirectory.parse(blob.toBytes())?.map((e) => e.name),
          ['a.sfc']);
    });

    test('read joins the two halves and delivers the entries', () async {
      final server = FakeRangeServer(buildZip([
        cdEntry('Super Pixel World (Europe).sfc', 0xA31BEAD4),
        cdEntry('readme.txt', 0x00000009),
      ]));
      final entries = await ZipCentralDirectory.read(uri, server.fetch);
      expect(entries?.map((e) => e.name),
          ['Super Pixel World (Europe).sfc', 'readme.txt']);
      expect(entries?.where((e) => e.crcMatchesRom).single.crc, 'A31BEAD4');
    });
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: compile FAILURE, `The method 'parse' isn't defined for the type 'ZipCentralDirectory'`.

- [ ] **Step 3: Write the minimal implementation**

At the top of `lib/services/zip_central_directory.dart`, add to the imports:

```dart
import 'dart:convert';

import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';
```

Add the class, before `ZipCentralDirectory`:

```dart
/// A central directory entry. [crc] uppercase, eight digits, in the same format
/// as `PackDump.crc`.
class ZipEntry {
  final String name;
  final String crc;

  const ZipEntry({required this.name, required this.crc});

  /// True when this CRC can be compared with that of a pack dump.
  ///
  /// A zip inside a zip has its own CRC, which is that of the compressed file
  /// and not of the ROM. Comparing that CRC with the pack is worse than not
  /// comparing: best case it does not match, worst case it matches by accident.
  /// See section 5.8 of the spec, limit 1.
  bool get crcMatchesRom => hasRomExtension(name) && !hasArchiveExtension(name);

  @override
  String toString() => 'ZipEntry($name, $crc)';
}
```

And the two methods, inside `ZipCentralDirectory`:

```dart
  /// The entries of a remote ZIP, or null when it could not be read.
  static Future<List<ZipEntry>?> read(Uri uri, RangeFetch fetch) async {
    final raw = await readRaw(uri, fetch);
    if (raw == null) return null;
    return parse(raw);
  }

  /// Breaks the central directory bytes into entries. Stops at the first record
  /// that does not start with `PK\x01\x02` and returns what it already read,
  /// because half a read is still useful and an error here should not cost the
  /// whole guess.
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
        // The name may be CP437 or UTF-8, and the zip only distinguishes them by
        // a flag bit that almost nobody writes correctly. `allowMalformed` turns
        // a wrong accented byte into U+FFFD instead of throwing, and the
        // matcher's `norm` eats U+FFFD as punctuation.
        name: utf8.decode(directory.sublist(pos + 46, nameEnd),
            allowMalformed: true),
        crc: formatCrc(crc),
      ));
      pos = nameEnd + extraLen + commentLen;
    }
    return entries.isEmpty ? null : entries;
  }
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/zip_central_directory_test.dart`
Expected: PASS, 14 tests.

- [ ] **Step 5: Write the real data probe**

The unit test proves the parser against bytes the test itself built. That does not prove that a real server cooperates. Create `tool/probe_zip_cd.dart`:

```dart
// Reads the central directory of a remote ZIP over Range and prints the entries.
// Runs outside Flutter:
//   dart run tool/probe_zip_cd.dart <url>
import 'dart:io';

import 'package:roms_downloader/services/zip_central_directory.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/probe_zip_cd.dart <url>');
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(args.single);
  final entries =
      await ZipCentralDirectory.read(uri, ZipCentralDirectory.httpRangeFetch);
  if (entries == null) {
    stderr.writeln('could not read the central directory of $uri');
    exitCode = 1;
    return;
  }
  for (final entry in entries) {
    final mark = entry.crcMatchesRom ? 'ROM ' : '    ';
    print('$mark${entry.crc}  ${entry.name}');
  }
}
```

- [ ] **Step 6: Run the probe against archive.org**

```bash
dart run tool/probe_zip_cd.dart "https://archive.org/download/ef_nintendo_snes_no-intro_2024-04-20/%2796%20Zenith%20Cup%20Soccer%20%28Japan%29.zip"
```

Expected, exactly one line:

```
ROM 05FBB855  '96 Zenith Cup Soccer (Japan).sfc
```

That `05FBB855` is the CRC of the dump `'96 Zenith Cup Soccer (Japan)` in the published SNES pack. If the line comes out like that, the whole path is proven on real data: 302, 206, EOCD behind the TorrentZip comment, a second request of 93 bytes, and a CRC that matches the pack.

If it comes out `could not read`, do not touch the guards to "make it work". Run `curl -sSL -D - -o /dev/null -H 'Range: bytes=-256' <url>` and see what the server actually answered before changing anything.

- [ ] **Step 7: Commit**

```bash
git add lib/services/zip_central_directory.dart test/zip_central_directory_test.dart tool/probe_zip_cd.dart
git commit -m "feat(identidade): entradas do diretorio central e a regra de extensao"
```

---
### Task 12: confirm or correct the name with the remote ZIP CRC

**Files:**
- Create: `lib/services/crc_confirm_service.dart`
- Create: `test/support/pack_fixture.dart`
- Modify: `test/pack_matcher_test.dart`
- Test: `test/crc_confirm_service_test.dart`

Here the two axes meet. The name axis made a guess; the central directory of the remote ZIP says whether the guess is right, and sometimes says what the answer was.

The decision rule is conservative on purpose:

- If the file name does not end in `.zip`, **do not even go to the network**. We have no `.7z` or `.rar` reader over Range, and spending two requests to find that out is a waste.
- If the central directory did not come, keep the name guess.
- Consider only the entries where `crcMatchesRom` is true.
- If those entries point to **exactly one** pack game, that is the result, with tier `checksum`. Zero games or two different games means the zip is inconclusive, and the name guess still holds.

Note that "exactly one game" is not the same as "exactly one entry": a zip with the three discs of the same game resolves to a single game, and that counts.

- [ ] **Step 1: Extract the pack fixture to a shared place**

From here on two suites need the same test pack. Create `test/support/pack_fixture.dart` with the content below, which is the `buildPack()` that today is at the top of `test/pack_matcher_test.dart`, with no change at all:

```dart
import 'dart:convert';

import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Test pack with a real case for each tier:
/// - Crystal Vanguard has two regions, so it exercises tier 1 against tier 2.
/// - Zxia Gztqfevzem has the article at the end, which is the case `canon` fixes.
/// - CopperBolt Grappling is the fuzzy pair the PoC resolved correctly.
/// - Duo Vector Recoil MK3 is the fuzzy pair the PoC resolved **wrong**.
/// - Reso 4 Kkesv HQ and HQ-H are two fuzzy candidates in the same bucket.
MetadataPack buildPack() => MetadataPack.decode(jsonEncode({
      'pack': 'snes',
      'system': 'Nintendo - Super Nintendo Entertainment System',
      'built': '2026-09-10',
      'games': [
        {
          'id': 'snes/crystal-vanguard',
          'title': 'Crystal Vanguard',
          'dumps': [
            {'name': 'Crystal Vanguard (USA)', 'crc': '2D206BF7'},
            {'name': 'Crystal Vanguard (Japan)', 'crc': 'ABCD1234'},
          ],
        },
        {
          'id': 'snes/the-zxia-gztqfevzem',
          'title': 'The Zxia Gztqfevzem',
          'dumps': [
            {'name': 'Zxia Gztqfevzem, The (Japan)', 'crc': '777C7B18'},
          ],
        },
        {
          'id': 'snes/copperbolt-grappling',
          'title': 'CopperBolt Grappling',
          'dumps': [
            {'name': 'CopperBolt Grappling (USA)', 'crc': '0F0F0F0F'},
          ],
        },
        {
          'id': 'snes/duo-vector-recoil-mk3',
          'title': 'Duo Vector Recoil MK3',
          'dumps': [
            {'name': 'Duo Vector Recoil MK3 (Europe) (Unl)', 'crc': '11112222'},
          ],
        },
        {
          'id': 'snes/super-pixel-world',
          'title': 'Super Pixel World',
          'dumps': [
            {'name': 'Super Pixel World (USA)', 'crc': 'B19ED489'},
            {'name': 'Super Pixel World (Europe)', 'crc': 'A31BEAD4'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq',
          'title': 'Reso 4 Kkesv HQ',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ (Japan)', 'crc': '33334444'},
          ],
        },
        {
          'id': 'snes/reso-4-kkesv-hq-h',
          'title': 'Reso 4 Kkesv HQ-H',
          'dumps': [
            {'name': 'Reso 4 Kkesv HQ-H (Japan)', 'crc': '55556666'},
          ],
        },
      ],
    }));
```

Now in `test/pack_matcher_test.dart`: delete the comment and the whole `buildPack()` function, delete the `import 'dart:convert';` and the `import 'package:roms_downloader/models/metadata_pack_model.dart';` that only it used, and add after the package imports:

```dart
import 'support/pack_fixture.dart';
```

- [ ] **Step 2: Confirm the extraction broke nothing**

Run: `flutter test test/pack_matcher_test.dart`
Expected: PASS, 18 tests. If `flutter analyze` complains about an unused import in `pack_matcher_test.dart`, it is because one of the two old imports is left over. Remove it.

- [ ] **Step 3: Commit the extraction on its own**

```bash
git add test/pack_matcher_test.dart test/support/pack_fixture.dart
git commit -m "refactor(identidade): fixture do pacote em test/support"
```

- [ ] **Step 4: Write the failing tests**

Create `test/crc_confirm_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/crc_confirm_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs of the test pack, in the numeric form the central directory writes.
const crystalUsa = 0x2D206BF7;
const smwEurope = 0xA31BEAD4;

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://example/file.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  CrcConfirmService serving(Uint8List zip) => CrcConfirmService(
        matcher: matcher,
        fetch: FakeRangeServer(zip).fetch,
      );

  test('does not go to the network when the name does not end in .zip', () async {
    var calls = 0;
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: (u, r) async {
        calls++;
        throw StateError('should not have gone to the network');
      },
    );
    final byName = matcher.match('Crystal Vanguard (USA).sfc');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).sfc', byName);
    expect(calls, 0);
    expect(out, same(byName));
  });

  test('confirms the name guess when the CRC points to the same game', () async {
    final service = serving(
        buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out!.game.id, 'snes/crystal-vanguard');
    expect(out.tier, MatchTier.checksum);
    expect(out.confidence, MatchConfidence.confirmed);
    expect(out.dump?.name, 'Crystal Vanguard (USA)');
  });

  test('corrects the name guess when the CRC points to another game', () async {
    // The file is called Crystal Vanguard but contains Super Pixel World. The
    // name lies, the CRC does not.
    final service = serving(
        buildZip([cdEntry('rom.sfc', smwEurope)]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    expect(byName!.game.id, 'snes/crystal-vanguard');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out!.game.id, 'snes/super-pixel-world');
    expect(out.tier, MatchTier.checksum);
    expect(out.dump?.name, 'Super Pixel World (Europe)');
  });

  test('keeps the name when the server does not speak Range', () async {
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('rom.sfc', smwEurope)]),
        status: 200,
      ).fetch,
    );
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out, same(byName));
  });

  test('keeps the name when the zip has two different games inside',
      () async {
    final service = serving(buildZip([
      cdEntry('Crystal Vanguard (USA).sfc', crystalUsa),
      cdEntry('Super Pixel World (Europe).sfc', smwEurope),
    ]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out, same(byName));
  });

  test('ignores what is not a ROM and decides by the only one that is', () async {
    // If the extension filter did not exist, bonus.zip would come in with the
    // Super Pixel World CRC, become two games, and the zip would be discarded as
    // inconclusive. See 5.8, limit 1.
    final service = serving(buildZip([
      cdEntry('readme.txt', 0x00000009),
      cdEntry('bonus.zip', smwEurope),
      cdEntry('Crystal Vanguard (USA).sfc', crystalUsa),
    ]));
    final byName = matcher.match('random thing.zip');
    expect(byName, isNull);
    final out = await service.confirm(uri, 'random thing.zip', byName);
    expect(out!.game.id, 'snes/crystal-vanguard');
    expect(out.tier, MatchTier.checksum);
    expect(out.sourceName, 'random thing.zip');
  });
}
```

- [ ] **Step 5: Run and watch it fail**

Run: `flutter test test/crc_confirm_service_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/services/crc_confirm_service.dart'`.

- [ ] **Step 6: Write the minimal implementation**

Create `lib/services/crc_confirm_service.dart`:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Confirms or corrects a name guess by reading the ROM CRC from inside the
/// remote ZIP, before any download. It is the middle axis of section 5.5 of the
/// spec.
///
/// Pure Dart on purpose. Do not add an import of `package:flutter`.
class CrcConfirmService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const CrcConfirmService({required this.matcher, required this.fetch});

  /// [byName] is what the name axis found, and can be null.
  ///
  /// Returns a match of tier [MatchTier.checksum] when the ZIP was conclusive,
  /// and [byName] untouched in all other cases. Never throws: a network failure
  /// here just means keeping the guess we already had.
  Future<GameMatch?> confirm(
      Uri uri, String sourceName, GameMatch? byName) async {
    // No 7z or rar reader over Range, so do not even spend the request.
    if (!sourceName.toLowerCase().endsWith('.zip')) return byName;

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return byName;

    final hits = <String, GameMatch>{};
    for (final entry in entries) {
      if (!entry.crcMatchesRom) continue;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null) hits[hit.game.id] = hit;
    }

    // A single game is conclusive, and three discs of the same game are still a
    // single game. Zero or two decide nothing, and inventing a tie breaker here
    // would be trading a certainty for a guess.
    if (hits.length != 1) return byName;
    return hits.values.first;
  }
}
```

- [ ] **Step 7: Run and watch it pass**

Run: `flutter test test/crc_confirm_service_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 8: Commit**

```bash
git add lib/services/crc_confirm_service.dart test/crc_confirm_service_test.dart
git commit -m "feat(identidade): confirmar ou corrigir o nome pelo CRC do zip remoto"
```

---

### Task 13: the local axis, name first and CRC only when in doubt

**Files:**
- Create: `lib/services/local_identity_service.dart`
- Test: `test/local_identity_service_test.dart`

Section 5.7 of the spec deals with a case different from the previous two: the file **is already on disk**. There is no network involved and the CRC is really computable, byte by byte. Except computing costs: a 1.4 GB ISO takes seconds, and a library of a thousand files takes minutes.

The 5.7 rule resolves this: **name first, CRC only when in doubt.**

- Tier `exactName` or `canonicalName`: accept it and move on. Do not read the file.
- Tier `fuzzyName` or nothing: then yes, compute the CRC. It is the rare case.

Two more decisions that need to be explicit:

1. **A container does not enter the CRC.** If the local file is `.zip` or `.7z`, the file CRC is that of the container and does not match the pack, for the same reason as 5.8 limit 1. For those the name is all we have. Reading the central directory of a **local** zip would resolve it, and it is a natural extension, but it is not part of this slice.
2. **The cache is per session.** The key is `size|mtime|path`: if any of the three changes, the file is another and the CRC is recomputed. The service accepts an initial cache and exposes what it accumulated, for whoever wants to persist it later. Actually persisting is not part of this slice, because in this slice nobody calls the service in a loop yet.

- [ ] **Step 1: Write the failing tests**

Create `test/local_identity_service_test.dart`:

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
  late List<String> reads;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_identity_test');
    matcher = PackMatcher(buildPack());
    reads = [];
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File write(String name) =>
      File('${tmp.path}/$name')..writeAsStringSync('content');

  /// Service with a fake CRC, so the test controls what the disk "has" and
  /// counts how many times the file was read.
  LocalIdentityService serviceReturning(String crc) => LocalIdentityService(
        matcher: matcher,
        crcOfFile: (file) async {
          reads.add(file.path);
          return crc;
        },
      );

  test('accepts the exact name and does not touch the file', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('Crystal Vanguard (USA).sfc'));
    expect(m!.tier, MatchTier.exactName);
    expect(m.game.id, 'snes/crystal-vanguard');
    expect(reads, isEmpty);
  });

  test('accepts the canonical name and does not touch the file', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('The Zxia Gztqfevzem.sfc'));
    expect(m!.tier, MatchTier.canonicalName);
    expect(m.game.id, 'snes/the-zxia-gztqfevzem');
    expect(reads, isEmpty);
  });

  test('on a fuzzy guess it computes the CRC and corrects the game', () async {
    // The name looks like CopperBolt Grappling, but the bytes are Duo Vector
    // Replay MK3. The CRC wins.
    final service = serviceReturning('11112222');
    final file = write('Copper Bolt Grappling (USA).sfc');
    expect(matcher.match('Copper Bolt Grappling (USA).sfc')!.tier,
        MatchTier.fuzzyName);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/duo-vector-recoil-mk3');
    expect(reads, [file.path]);
  });

  test('with no name guess at all, the CRC resolves on its own', () async {
    final service = serviceReturning('A31BEAD4');
    final file = write('unknown rom 0042.sfc');
    expect(matcher.match('unknown rom 0042.sfc'), isNull);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/super-pixel-world');
  });

  test('a CRC not in the pack returns the name guess untouched',
      () async {
    final service = serviceReturning('DEADBEEF');
    final m = await service.identify(write('Copper Bolt Grappling (USA).sfc'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/copperbolt-grappling');
  });

  test('does not compute the CRC of a container, because it would not be comparable', () async {
    final service = serviceReturning('11112222');
    final m = await service.identify(write('Copper Bolt Grappling (USA).zip'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/copperbolt-grappling');
    expect(reads, isEmpty);
  });

  test('the cache avoids the second read of the same file', () async {
    final service = serviceReturning('11112222');
    final file = write('Copper Bolt Grappling (USA).sfc');
    await service.identify(file);
    await service.identify(file);
    expect(reads, hasLength(1));
    expect(service.cache.values, ['11112222']);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/local_identity_service_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/services/local_identity_service.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/services/local_identity_service.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

typedef FileCrc = Future<String> Function(File file);

/// The axis of section 5.7 of the spec: identifies a file that is already on
/// disk.
///
/// Name first, CRC only when in doubt. Computing a CRC is the expensive
/// operation of this slice, and the name tier resolves the vast majority of
/// cases for free.
///
/// Pure Dart on purpose. Do not add an import of `package:flutter`.
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

  /// What has already been computed this session. Key `size|mtime|path`, value
  /// the uppercase CRC. Exposed for whoever wants to persist it; in this slice
  /// nobody persists.
  Map<String, String> get cache => Map.unmodifiable(_cache);

  Future<GameMatch?> identify(File file) async {
    final name = p.basename(file.path);
    final byName = matcher.match(name);
    if (byName != null &&
        (byName.tier == MatchTier.exactName ||
            byName.tier == MatchTier.canonicalName)) {
      return byName;
    }

    // A container has its own CRC, which is not the ROM's, so computing it would
    // spend seconds to compare against the wrong index. See 5.8, limit 1.
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
      // File with no permission, half copied, or on a thumb drive that vanished.
      // None of that justifies bringing down the sweep of the whole library.
      return null;
    }
  }
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/local_identity_service_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_identity_service.dart test/local_identity_service_test.dart
git commit -m "feat(identidade): eixo local com nome primeiro e CRC so na duvida"
```

---

### Task 14: the Riverpod wiring

**Files:**
- Create: `lib/providers/identity_provider.dart`
- Test: `test/identity_provider_test.dart`

Two thin providers on top of what already exists. What they buy is memoization: building the three `PackMatcher` indices costs a pass over all of the console's dumps, 4267 on the SNES, and redoing that on every widget rebuild would be expensive for nothing. A `FutureProvider.family` keeps the result alive while someone is watching.

Both follow the same null contract as `metadataPackProvider`: a console with no pack in the index returns null, and the consumer treats that as "this console has no metadata", not as an error.

- [ ] **Step 1: Write the failing tests**

Create `test/identity_provider_test.dart`. It overrides `metadataPackServiceProvider`, which is the same entry point `test/metadata_pack_provider_test.dart` already uses, so the pack comes from a fake fetch and nothing touches the network or the user's disk.

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
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/crystal-vanguard","title":"Crystal Vanguard","dumps":[{"name":"Crystal Vanguard (USA)","crc":"2D206BF7"}]}]}';

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

  test('builds the matcher from the console pack', () async {
    final matcher = await container().read(packMatcherProvider(snes).future);
    expect(matcher, isNotNull);
    expect(matcher!.match('Crystal Vanguard (USA).zip')?.tier,
        MatchTier.exactName);
  });

  test('a console with no pack returns null instead of an error', () async {
    final c = container();
    expect(await c.read(packMatcherProvider(switchTarget).future), isNull);
    expect(
        await c.read(localIdentityServiceProvider(switchTarget).future), isNull);
  });

  test('the local service reuses the same memoized matcher', () async {
    final c = container();
    final matcher = await c.read(packMatcherProvider(snes).future);
    final service = await c.read(localIdentityServiceProvider(snes).future);
    expect(service!.matcher, same(matcher));
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/identity_provider_test.dart`
Expected: compile FAILURE, `Target of URI doesn't exist: 'package:roms_downloader/providers/identity_provider.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/providers/identity_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// The matcher of a console. Null when the console has no pack, which is the
/// same contract as `metadataPackProvider`.
///
/// It exists to memoize: the three indices cost a pass over all of the console's
/// dumps, and redoing that on every rebuild makes no sense.
final packMatcherProvider =
    FutureProvider.family<PackMatcher?, PackTarget>((ref, target) async {
  final pack = await ref.watch(metadataPackProvider(target).future);
  if (pack == null) return null;
  return PackMatcher(pack);
});

/// The local axis of a console, on top of the same memoized matcher.
final localIdentityServiceProvider =
    FutureProvider.family<LocalIdentityService?, PackTarget>(
        (ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return LocalIdentityService(matcher: matcher);
});
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/identity_provider_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run the whole suite and the analysis**

Run: `flutter test`
Expected: `+176 -1`. The only failure is still `test/rar_decompress_screen_test.dart`, which predates this slice.

Run: `flutter analyze`
Expected: no new problems.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/identity_provider.dart test/identity_provider_test.dart
git commit -m "feat(identidade): providers do matcher e do eixo local"
```

---

### Task 15: run the matcher against the real collection

**Files:**
- Create: `tool/verify_matcher.dart`

The tests of the previous tasks prove the behavior over seven cherry picked games. This task proves the **number**: the matcher, running over the published SNES pack and over the real listing of an archive.org item with 4122 files, has to reproduce the table of section 5.9 of the spec.

This is not decoration. Section 5.9 is the quality contract of the name axis, and if the Dart diverges from what was measured in Python, something in the port of `norm` or `canon` came out different and slice 3 will show a wrong badge at scale.

- [ ] **Step 1: Gather the two inputs**

The pack, built with the slice 1 tool:

```bash
python3 tool/build_metadata_pack.py --out /tmp/packs-verify --built 2026-09-10 \
  --only nintendo_super_nintendo_entertainment_system
gunzip -c /tmp/packs-verify/nintendo_super_nintendo_entertainment_system.json.gz \
  > /tmp/snes-pack.json
```

The listing, straight from archive.org:

```bash
curl -sL https://archive.org/metadata/ef_nintendo_snes_no-intro_2024-04-20 \
  -o /tmp/snes-listing.json
```

- [ ] **Step 2: Write the tool**

Create `tool/verify_matcher.dart`:

```dart
// Runs the matcher over a real pack and a real listing, and prints the table
// of section 5.9 of the spec. Runs outside Flutter:
//   dart run tool/verify_matcher.dart <pack.json> <listing.json>
import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
        'usage: dart run tool/verify_matcher.dart <pack.json> <listing.json>');
    exitCode = 64;
    return;
  }
  final pack = MetadataPack.decode(await File(args[0]).readAsString());
  final matcher = PackMatcher(pack);
  final files = listingNames(
      jsonDecode(await File(args[1]).readAsString()) as Map<String, dynamic>);
  if (files.isEmpty) {
    stderr.writeln('the listing has no file with a ROM extension');
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

  print('pack ${pack.pack}: ${matcher.indexedGames} games, '
      '${matcher.indexedCanonKeys} canonical keys');
  print('listing: $total files');
  print(line('tier 1 exact name     ', tiers[MatchTier.exactName]!));
  print(line('tier 2 canonical title', tiers[MatchTier.canonicalName]!));
  print(line('tier 3 similarity     ', tiers[MatchTier.fuzzyName]!));
  print(line('tier 4 no guess       ', misses.length));
  print('file coverage $attributed/$total = ${pct(attributed)}%');
  print('game coverage ${hitGames.length}/${matcher.indexedGames} = '
      '${(hitGames.length / matcher.indexedGames * 100).toStringAsFixed(2)}%');
  print('');
  print('first misses:');
  for (final miss in misses.take(15)) {
    print('  $miss');
  }
}

/// ROM names from an `archive.org/metadata/<item>` response. Derivatives are
/// left out: they are the covers and indices that archive.org itself generates.
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

- [ ] **Step 3: Run and check against section 5.9**

Run: `dart run tool/verify_matcher.dart /tmp/snes-pack.json /tmp/snes-listing.json`

Expected, number by number:

```
pack nintendo_super_nintendo_entertainment_system: 2415 games, 2415 canonical keys
listing: 4122 files
tier 1 exact name       3584  86.95%
tier 2 canonical title   444  10.77%
tier 3 similarity         26   0.63%
tier 4 no guess           68   1.65%
file coverage 4054/4122 = 98.35%
game coverage 2342/2415 = 96.98%
```

These numbers are not an estimate: they were measured over this same pack and this same listing before this plan was written, and they are the ones section 5.9 of the spec records.

**If they diverge, the problem is the port of `norm` or `canon`, not the tool.** A large divergence in tier 1 against tier 2 points to `norm`; a divergence between tier 2 and tier 4 points to `canon`, usually the inverted article rule. Go back to `test/pack_naming_parity_test.dart` and add the diverging case to the golden.

A tolerance that is **not** a divergence: if the pack is rebuilt on a date when libretro-database or OpenVGDB changed, the game count changes along with it and the percentages move a little. In that case what matters is the shape: tier 1 in the 87% range, tier 2 in the 11% range, tier 3 below 1%, file coverage above 98%.

- [ ] **Step 4: Commit**

```bash
git add tool/verify_matcher.dart
git commit -m "feat(identidade): ferramenta que roda o matcher contra o acervo real"
```

---

## What this slice does not do

Written for whoever reviews it and misses something. Nothing here is an oversight.

- **No screen.** There is no grid, badge, detail card, or confidence indicator. `MatchConfidence` exists for slice 3 to consume, and it is slice 3 that decides how "confirmed", "likely" and "guess" appear to the user.
- **No source.** `CrcConfirmService` receives a ready `Uri`. Whoever produces that `Uri` from an addon is `SourceResolver`, which is slice 5. Here the source is always a parameter.
- **The local axis cache is not persisted.** It exists and is injectable, but in this slice nobody calls the service in a loop, so persisting would be writing code with no consumer. Slice 3, which sweeps the user's library, is the one that will need it.
- **Serial as key on a disc system.** Section 5.6 of the spec describes matching PlayStation and GameCube by the disc serial, which is more robust than the name. `PackDump.serial` already comes filled by the slice 1 pack, and the matcher does not look at it yet. It waits until a disc console actually arrives.
- **Central directory of a local zip.** It would resolve the gap of item 6 in Task 13, a `.zip` file on the user's disk that only has a name guess. It is the most obvious extension of this slice, and it remains future work.
- **Remote zip64 and 7z.** Zip64 is explicitly refused in Task 10, and `.7z` does not even become a request in Task 12. No known source serves either, and implementing them for completeness would be code with no exercise.
