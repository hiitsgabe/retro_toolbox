# Slice 1: Metadata Pack, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a per-console metadata pack (canonical title, dumps with CRC/SHA1/serial/region, cover, synopsis, genre, year) and make the app download, cache and resolve that pack for the consoles in the user's catalog, with no login and no server of our own.

**Architecture:** A Python script in `tool/` runs on GitHub Actions, reads the libretro-database DATs (No-Intro and Redump), collapses the dumps into canonical games, enriches with the side files from `metadat/` and with OpenVGDB, checks the cover's existence on libretro-thumbnails and publishes one `<pack>.json.gz` per system plus one `index.json` in a release under the fixed tag `packs`. On the Flutter side, `MetadataPackService` downloads on demand, decompresses with `gzip` from `dart:io`, writes to `getApplicationSupportDirectory()/packs/` and serves from disk on the next launches; `PackIndex.resolve` links the arbitrary console id/name from the user to the pack id.

**Tech Stack:** Python 3 stdlib (`urllib.request`, `sqlite3`, `gzip`, `json`, `re`, `unicodedata`, `difflib`, `unittest`), GitHub Actions, Dart/Flutter with Riverpod, `dart:io` `gzip`, `flutter_test`.

---

## Context the implementer needs

**What already exists in the repository and cannot break:**

- `lib/services/catalog_service.dart` loads `consoles.json` and derives the console id from the name with `_nameToId` (line 59): lowercase, everything that is not `[a-z0-9]` becomes `_`, leading and trailing `_` are dropped. The console id is arbitrary and comes from the user, so the pack can never assume the console id equals the pack id. Hence the `index.json` with aliases.
- `tool/build_gametdb_boxarts.py` and `tool/build_xbox360_boxarts.py` are the precedent for build scripts: Python 3, stdlib only, a module docstring explaining the source, `def main()`, no test framework. This plan keeps stdlib and adds `unittest`, which is also stdlib.
- The tests in `test/` use plain `flutter_test`, no mockito. Dependency injection is done through constructor parameters. See `test/catalog_add_console_test.dart`.
- `assets/catalog/` is git-ignored. Nothing in this plan writes there.

**Format decisions locked in this plan:**

- Release tag: `packs`, fixed, updated in place. The download URL stays stable and the app does not need to call the GitHub API. The build date lives in the `built` field of the JSON. This is a deliberate departure from section 4.4 of the design spec, which suggested `packs-YYYY-MM-DD`.
- Pack file name: `<pack>.json.gz`, where `<pack>` is the libretro system name run through the same normalizer as `_nameToId`. Example: `Nintendo - Super Nintendo Entertainment System` becomes `nintendo_super_nintendo_entertainment_system`.
- Game `id` inside the pack: `<pack>/<slug of the canonical title>`, with suffix `-2`, `-3` and so on on collision, in the order they appear in the DAT.
- The pack stores the cover URL, never the image binary.

**The table of the 24 systems** is in Task 6 and is the single source of truth about which DATs to download, which thumbnails repository to use and which aliases each pack accepts. The Nintendo Switch has no pack on purpose: it falls into the SOURCE MODE described in the UI spec.

---

## File structure

| File | Responsibility |
| --- | --- |
| `lib/models/metadata_pack_model.dart` | `PackDump`, `PackGame`, `MetadataPack`. Data and serialization only. |
| `lib/models/pack_index_model.dart` | `PackIndexEntry`, `PackIndex`, `PackTarget`. The console to pack resolution rule lives here, pure and testable. |
| `lib/services/metadata_pack_service.dart` | Disk cache, download, decompression. Takes a `Directory` and the fetch function through the constructor. |
| `lib/providers/metadata_pack_provider.dart` | Riverpod wiring. Thin on purpose. |
| `tool/build_metadata_pack.py` | The whole builder: parse, collapse, enrichment, output. |
| `tool/test_build_metadata_pack.py` | `unittest` for the builder, no network. |
| `.github/workflows/metadata-packs.yml` | Runs the builder and publishes the release. |
| `test/metadata_pack_model_test.dart` | Tests for Task 1. |
| `test/pack_index_model_test.dart` | Tests for Task 2. |
| `test/metadata_pack_service_test.dart` | Tests for Tasks 3 and 4. |
| `test/metadata_pack_provider_test.dart` | Test for Task 5. |

---

### Task 1: The pack model

**Files:**
- Create: `lib/models/metadata_pack_model.dart`
- Test: `test/metadata_pack_model_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/metadata_pack_model_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

void main() {
  const sample = '''
{
  "pack": "nintendo_super_nintendo_entertainment_system",
  "system": "Nintendo - Super Nintendo Entertainment System",
  "built": "2026-09-10",
  "games": [
    {
      "id": "nintendo_super_nintendo_entertainment_system/crystal-vanguard",
      "title": "Crystal Vanguard",
      "dumps": [
        {"name": "Crystal Vanguard (USA)", "crc": "2d206bf7", "sha1": "abc", "serial": null, "region": "USA"},
        {"name": "Crystal Vanguard (Japan)", "crc": "1f2e3d4c"}
      ],
      "cover": "https://example.invalid/cover.png",
      "synopsis": "An RPG.",
      "genre": "Role-Playing",
      "developer": "Square",
      "publisher": "Square",
      "year": 1995
    },
    {
      "id": "nintendo_super_nintendo_entertainment_system/sparse-entry",
      "title": "Sparse Entry",
      "dumps": []
    }
  ]
}
''';

  test('decode reads the whole pack', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.pack, 'nintendo_super_nintendo_entertainment_system');
    expect(pack.system, 'Nintendo - Super Nintendo Entertainment System');
    expect(pack.built, '2026-09-10');
    expect(pack.games.length, 2);
  });

  test('CRC and SHA1 are uppercased', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.crc, '2D206BF7');
    expect(pack.games.first.dumps.first.sha1, 'ABC');
    expect(pack.games.first.dumps[1].sha1, isNull);
  });

  test('region is read as-is and is optional', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.region, 'USA');
    expect(pack.games.first.dumps[1].region, isNull);
  });

  test('absent optional fields become null and empty dumps is allowed', () {
    final pack = MetadataPack.decode(sample);
    final game = pack.games[1];
    expect(game.cover, isNull);
    expect(game.synopsis, isNull);
    expect(game.year, isNull);
    expect(game.dumps, isEmpty);
  });

  test('toJson omits nulls and survives a round trip', () {
    final pack = MetadataPack.decode(sample);
    final round = MetadataPack.decode(jsonEncode(pack.toJson()));
    expect(round.games[1].toJson().containsKey('cover'), isFalse);
    expect(round.games.first.dumps.first.crc, '2D206BF7');
    expect(round.games.first.year, 1995);
    expect(round.games.length, 2);
  });

  test('byCrc indexes every dump in the pack', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.byCrc['2D206BF7']?.title, 'Crystal Vanguard');
    expect(pack.byCrc['1F2E3D4C']?.title, 'Crystal Vanguard');
    expect(pack.byCrc['DEADBEEF'], isNull);
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/metadata_pack_model_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/models/metadata_pack_model.dart'`.

- [ ] **Step 3: Write the model**

Create `lib/models/metadata_pack_model.dart`:

```dart
import 'dart:convert';

/// A concrete dump of a game, as a No-Intro or Redump DAT describes it.
/// [name] is the DAT name, without extension, with region and revision tags
/// preserved, because the matcher compares it against the remote filename.
///
/// [crc] and [sha1] are uppercased for stable comparison; [serial] is not, as
/// its case and hyphens are part of the value. [region] is the DAT region when
/// present, and is optional because not every dump declares one.
class PackDump {
  final String name;
  final String? crc;
  final String? sha1;
  final String? serial;
  final String? region;

  const PackDump({
    required this.name,
    this.crc,
    this.sha1,
    this.serial,
    this.region,
  });

  factory PackDump.fromJson(Map<String, dynamic> json) => PackDump(
        name: json['name'] as String,
        crc: (json['crc'] as String?)?.toUpperCase(),
        sha1: (json['sha1'] as String?)?.toUpperCase(),
        serial: json['serial'] as String?,
        region: json['region'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (crc != null) 'crc': crc,
        if (sha1 != null) 'sha1': sha1,
        if (serial != null) 'serial': serial,
        if (region != null) 'region': region,
      };
}

/// A canonical game: one title, several versions.
class PackGame {
  final String id;
  final String title;
  final List<PackDump> dumps;
  final String? cover;
  final String? synopsis;
  final String? genre;
  final String? developer;
  final String? publisher;
  final int? year;

  const PackGame({
    required this.id,
    required this.title,
    required this.dumps,
    this.cover,
    this.synopsis,
    this.genre,
    this.developer,
    this.publisher,
    this.year,
  });

  factory PackGame.fromJson(Map<String, dynamic> json) => PackGame(
        id: json['id'] as String,
        title: json['title'] as String,
        dumps: ((json['dumps'] as List?) ?? const [])
            .map((e) => PackDump.fromJson(e as Map<String, dynamic>))
            .toList(),
        cover: json['cover'] as String?,
        synopsis: json['synopsis'] as String?,
        genre: json['genre'] as String?,
        developer: json['developer'] as String?,
        publisher: json['publisher'] as String?,
        year: json['year'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dumps': dumps.map((d) => d.toJson()).toList(),
        if (cover != null) 'cover': cover,
        if (synopsis != null) 'synopsis': synopsis,
        if (genre != null) 'genre': genre,
        if (developer != null) 'developer': developer,
        if (publisher != null) 'publisher': publisher,
        if (year != null) 'year': year,
      };
}

/// The pack for a whole console.
class MetadataPack {
  final String pack;
  final String system;
  final String built;
  final List<PackGame> games;

  MetadataPack({
    required this.pack,
    required this.system,
    required this.built,
    required this.games,
  });

  Map<String, PackGame>? _byCrc;

  /// Uppercase CRC32 to the game owning that dump. Built lazily and cached.
  Map<String, PackGame> get byCrc {
    final cached = _byCrc;
    if (cached != null) return cached;
    final map = <String, PackGame>{};
    for (final game in games) {
      for (final dump in game.dumps) {
        final crc = dump.crc;
        if (crc != null) map[crc] = game;
      }
    }
    return _byCrc = map;
  }

  factory MetadataPack.fromJson(Map<String, dynamic> json) => MetadataPack(
        pack: json['pack'] as String,
        system: json['system'] as String,
        built: json['built'] as String,
        games: ((json['games'] as List?) ?? const [])
            .map((e) => PackGame.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'pack': pack,
        'system': system,
        'built': built,
        'games': games.map((g) => g.toJson()).toList(),
      };

  static MetadataPack decode(String jsonStr) =>
      MetadataPack.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `flutter test test/metadata_pack_model_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/metadata_pack_model.dart test/metadata_pack_model_test.dart
git commit -m "feat(packs): modelo do metadata pack"
```

---

### Task 2: The pack index and the resolution rule

**Files:**
- Create: `lib/models/pack_index_model.dart`
- Test: `test/pack_index_model_test.dart`

The `index.json` is what links the user's console to the pack. The user can call their console "Super Nintendo", "SNES" or "snes_usa_set", and the pack is named `nintendo_super_nintendo_entertainment_system`. Resolution tries, in this order: console id equal to pack id, normalized console name equal to pack id, id or name matching some alias. The order matters: an alias never beats an exact `pack`.

- [ ] **Step 1: Write the failing test**

Create `test/pack_index_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

void main() {
  const sample = '''
{
  "built": "2026-09-10",
  "packs": [
    {
      "pack": "nintendo_super_nintendo_entertainment_system",
      "system": "Nintendo - Super Nintendo Entertainment System",
      "games": 2415,
      "aliases": ["super_nintendo", "snes", "super_famicom", "sfc"]
    },
    {
      "pack": "sony_playstation",
      "system": "Sony - PlayStation",
      "games": 4000,
      "aliases": ["playstation_1", "playstation", "ps1", "psx"]
    }
  ]
}
''';

  test('decode reads the entries', () {
    final index = PackIndex.decode(sample);
    expect(index.built, '2026-09-10');
    expect(index.packs.length, 2);
    expect(index.packs.first.games, 2415);
  });

  test('normalize follows the catalog console-id rule', () {
    expect(PackIndex.normalize('Nintendo - Super Nintendo Entertainment System'),
        'nintendo_super_nintendo_entertainment_system');
    expect(PackIndex.normalize('  PlayStation 1!! '), 'playstation_1');
  });

  test('resolves by pack id', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'nintendo_super_nintendo_entertainment_system', 'Any Name'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolves by the normalized console name', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'acme_catalog', 'Nintendo - Super Nintendo Entertainment System'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolves by alias, from id and from name', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('snes', 'My Set'))?.pack,
        'nintendo_super_nintendo_entertainment_system');
    expect(index.resolve(const PackTarget('any', 'PlayStation 1'))?.pack,
        'sony_playstation');
  });

  test('an exact pack beats another entry alias regardless of order', () {
    const colliding = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "other", "system": "Other", "games": 1, "aliases": ["snes"]},
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []}
  ]
}
''';
    final index = PackIndex.decode(colliding);
    expect(index.resolve(const PackTarget('snes', 'Snes'))?.pack, 'snes');

    // Same assertion with the entries reversed: the guarantee comes from
    // resolve scanning every pack before any alias, not from index order.
    const reversed = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []},
    {"pack": "other", "system": "Other", "games": 1, "aliases": ["snes"]}
  ]
}
''';
    expect(
        PackIndex.decode(reversed).resolve(const PackTarget('snes', 'Snes'))?.pack,
        'snes');
  });

  test('a console without a pack returns null', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('nintendo_switch', 'Nintendo Switch')),
        isNull);
  });

  test('PackTarget has value equality, to serve as a family key', () {
    expect(const PackTarget('a', 'b'), const PackTarget('a', 'b'));
    expect(const PackTarget('a', 'b').hashCode, const PackTarget('a', 'b').hashCode);
    expect(const PackTarget('a', 'b') == const PackTarget('a', 'c'), isFalse);
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/pack_index_model_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/models/pack_index_model.dart'`.

- [ ] **Step 3: Write the model**

Create `lib/models/pack_index_model.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// A console from the user's catalog: an arbitrary id and a free-form name.
/// The pack provider keys on it, so it needs value equality.
@immutable
class PackTarget {
  final String consoleId;
  final String consoleName;

  const PackTarget(this.consoleId, this.consoleName);

  @override
  bool operator ==(Object other) =>
      other is PackTarget &&
      other.consoleId == consoleId &&
      other.consoleName == consoleName;

  @override
  int get hashCode => Object.hash(consoleId, consoleName);

  @override
  String toString() => 'PackTarget($consoleId, $consoleName)';
}

class PackIndexEntry {
  final String pack;
  final String system;
  final int games;
  final List<String> aliases;

  const PackIndexEntry({
    required this.pack,
    required this.system,
    required this.games,
    required this.aliases,
  });

  factory PackIndexEntry.fromJson(Map<String, dynamic> json) => PackIndexEntry(
        pack: json['pack'] as String,
        system: json['system'] as String,
        games: (json['games'] as int?) ?? 0,
        aliases: ((json['aliases'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'pack': pack, 'system': system, 'games': games, 'aliases': aliases};
}

class PackIndex {
  final String built;
  final List<PackIndexEntry> packs;

  const PackIndex({required this.built, required this.packs});

  /// Same rule as `CatalogService._nameToId`.
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Finds the console's pack. Pack id and name always beat an alias.
  PackIndexEntry? resolve(PackTarget target) {
    final candidates = <String>{
      normalize(target.consoleId),
      normalize(target.consoleName),
    };
    for (final entry in packs) {
      if (candidates.contains(entry.pack)) return entry;
      if (candidates.contains(normalize(entry.system))) return entry;
    }
    for (final entry in packs) {
      for (final alias in entry.aliases) {
        if (candidates.contains(normalize(alias))) return entry;
      }
    }
    return null;
  }

  factory PackIndex.fromJson(Map<String, dynamic> json) => PackIndex(
        built: json['built'] as String,
        packs: ((json['packs'] as List?) ?? const [])
            .map((e) => PackIndexEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'built': built, 'packs': packs.map((p) => p.toJson()).toList()};

  static PackIndex decode(String jsonStr) =>
      PackIndex.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `flutter test test/pack_index_model_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/pack_index_model.dart test/pack_index_model_test.dart
git commit -m "feat(packs): indice de pacotes e resolucao console para pacote"
```

---

### Task 3: The service, the disk cache half

**Files:**
- Create: `lib/services/metadata_pack_service.dart`
- Test: `test/metadata_pack_service_test.dart`

The service takes the cache directory and the fetch function through the constructor. No test touches the network or `path_provider`. In this task only the disk side exists; the download comes in Task 4.

- [ ] **Step 1: Write the failing test**

Create `test/metadata_pack_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/metadata_pack_service.dart';

const packJson = '''
{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System",
 "built":"2026-09-10","games":[{"id":"snes/crystal-vanguard","title":"Crystal Vanguard",
 "dumps":[{"name":"Crystal Vanguard (USA)","crc":"2d206bf7"}]}]}
''';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('packs_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  MetadataPackService service() => MetadataPackService(
        cacheDir: tmp,
        fetch: (uri) async => throw StateError('network not allowed in this test'),
      );

  test('readCached returns null when nothing is on disk', () async {
    expect(await service().readCached('snes'), isNull);
  });

  test('writeCache writes and readCached reads it back', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    final pack = await svc.readCached('snes');
    expect(pack, isNotNull);
    expect(pack!.games.single.title, 'Crystal Vanguard');
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('writeCache creates the directory when it does not exist', () async {
    final nested = Directory(p.join(tmp.path, 'a', 'b'));
    final svc = MetadataPackService(
        cacheDir: nested, fetch: (uri) async => throw StateError('no'));
    await svc.writeCache('snes', packJson);
    expect(await File(p.join(nested.path, 'snes.json')).exists(), isTrue);
  });

  test('readCached returns null and deletes the file when the JSON is corrupt',
      () async {
    final svc = service();
    final file = File(p.join(tmp.path, 'snes.json'));
    await file.create(recursive: true);
    await file.writeAsString('{ this is not json');
    expect(await svc.readCached('snes'), isNull);
    expect(await file.exists(), isFalse);
  });

  test('cachedPacks lists the ids on disk', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.writeCache('nes', packJson);
    final ids = await svc.cachedPacks();
    expect(ids..sort(), ['nes', 'snes']);
  });

  test('evict deletes the pack from disk', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.evict('snes');
    expect(await svc.readCached('snes'), isNull);
    expect(await svc.cachedPacks(), isEmpty);
  });

  test('readCachedIndex and writeCacheIndex use index.json', () async {
    final svc = service();
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":[]}]}';
    expect(await svc.readCachedIndex(), isNull);
    await svc.writeCacheIndex(indexJson);
    final index = await svc.readCachedIndex();
    expect(index!.packs.single.pack, 'snes');
    expect(await svc.cachedPacks(), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/services/metadata_pack_service.dart'`.

- [ ] **Step 3: Write the service, only the disk side**

Create `lib/services/metadata_pack_service.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

typedef PackFetch = Future<List<int>> Function(Uri uri);

/// Downloads, decompresses, and caches the metadata packs.
class MetadataPackService {
  final Directory cacheDir;
  final PackFetch fetch;

  MetadataPackService({required this.cacheDir, required this.fetch});

  static const indexFileName = 'index.json';

  File packFile(String packId) => File(p.join(cacheDir.path, '$packId.json'));
  File get indexFile => File(p.join(cacheDir.path, indexFileName));

  Future<void> writeCache(String packId, String jsonStr) async {
    final file = packFile(packId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> writeCacheIndex(String jsonStr) async {
    await indexFile.parent.create(recursive: true);
    await indexFile.writeAsString(jsonStr);
  }

  Future<MetadataPack?> readCached(String packId) async {
    final file = packFile(packId);
    if (!await file.exists()) return null;
    try {
      return MetadataPack.decode(await file.readAsString());
    } catch (e) {
      debugPrint('Pack $packId corrupt on disk, discarding: $e');
      await file.delete();
      return null;
    }
  }

  Future<PackIndex?> readCachedIndex() async {
    if (!await indexFile.exists()) return null;
    try {
      return PackIndex.decode(await indexFile.readAsString());
    } catch (e) {
      debugPrint('Pack index corrupt on disk, discarding: $e');
      await indexFile.delete();
      return null;
    }
  }

  /// Ids of the packs on disk. index.json does not count.
  Future<List<String>> cachedPacks() async {
    if (!await cacheDir.exists()) return [];
    final ids = <String>[];
    await for (final entity in cacheDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == indexFileName || !name.endsWith('.json')) continue;
      ids.add(name.substring(0, name.length - '.json'.length));
    }
    return ids;
  }

  Future<void> evict(String packId) async {
    final file = packFile(packId);
    if (await file.exists()) await file.delete();
  }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/metadata_pack_service.dart test/metadata_pack_service_test.dart
git commit -m "feat(packs): cache em disco dos metadata packs"
```

---

### Task 4: The service, the download half

**Files:**
- Modify: `lib/services/metadata_pack_service.dart`
- Test: `test/metadata_pack_service_test.dart`

Decompression uses the `gzip` from `dart:io`, which is stdlib and does not depend on the `archive` package API. The load policy is cache first; if there is no cache, download; if the download fails, try the cache again before giving up, so the app keeps working offline.

- [ ] **Step 1: Write the failing tests**

Add at the end of `test/metadata_pack_service_test.dart`, inside `main()`, after the last existing `test(...)`:

```dart
  List<int> gz(String s) => gzip.encode(utf8.encode(s));

  test('packUri and indexUri point at the fixed-tag release', () {
    final svc = service();
    expect(svc.packUri('snes').toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/snes.json.gz');
    expect(svc.indexUri().toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/index.json');
  });

  test('download unzips, writes the cache and returns the pack', () async {
    final requests = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        requests.add(uri);
        return gz(packJson);
      },
    );
    final pack = await svc.download('snes');
    expect(pack.games.single.title, 'Crystal Vanguard');
    expect(requests.single.path, endsWith('/packs/snes.json.gz'));
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('load uses the cache and does not hit the network', () async {
    var calls = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        calls++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes');
    expect(pack!.games.single.title, 'Crystal Vanguard');
    expect(calls, 0);
  });

  test('load with forceRefresh hits the network even with a cache', () async {
    var calls = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        calls++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    await svc.load('snes', forceRefresh: true);
    expect(calls, 1);
  });

  test('load falls back to the cache when the network fails', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('no network'),
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes', forceRefresh: true);
    expect(pack!.games.single.title, 'Crystal Vanguard');
  });

  test('load returns null with neither network nor cache', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('no network'),
    );
    expect(await svc.load('snes'), isNull);
  });

  test('loadIndex downloads index.json ungzipped and caches it', () async {
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":["snes"]}]}';
    final requests = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        requests.add(uri);
        return utf8.encode(indexJson);
      },
    );
    final index = await svc.loadIndex(forceRefresh: true);
    expect(index!.packs.single.pack, 'snes');
    expect(requests.single.path, endsWith('/packs/index.json'));
    expect((await svc.readCachedIndex())!.built, '2026-09-10');
  });
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: FAIL, `The method 'download' isn't defined for the class 'MetadataPackService'`.

- [ ] **Step 3: Add the download to the service**

In `lib/services/metadata_pack_service.dart`, replace the imports at the top with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
```

Right after `MetadataPackService({required this.cacheDir, required this.fetch});`, add:

```dart
  /// Fixed-tag release, updated in place by the metadata-packs workflow.
  /// A fixed tag means a stable URL and zero GitHub API calls in the app.
  static const releaseBase =
      'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs';

  /// Default production fetch. Follows the redirect that the GitHub release
  /// always returns.
  static Future<List<int>> httpFetch(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  Uri packUri(String packId) => Uri.parse('$releaseBase/$packId.json.gz');
  Uri indexUri() => Uri.parse('$releaseBase/$indexFileName');

  Future<MetadataPack> download(String packId) async {
    final compressed = await fetch(packUri(packId));
    final jsonStr = utf8.decode(gzip.decode(compressed));
    await writeCache(packId, jsonStr);
    return MetadataPack.decode(jsonStr);
  }

  Future<PackIndex> downloadIndex() async {
    final jsonStr = utf8.decode(await fetch(indexUri()));
    await writeCacheIndex(jsonStr);
    return PackIndex.decode(jsonStr);
  }

  /// Cache first, then network, then cache again if the network fails. Null
  /// only when neither exists.
  Future<MetadataPack?> load(String packId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCached(packId);
      if (cached != null) return cached;
    }
    try {
      return await download(packId);
    } catch (e) {
      debugPrint('Failed to download pack $packId: $e');
      return readCached(packId);
    }
  }

  Future<PackIndex?> loadIndex({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCachedIndex();
      if (cached != null) return cached;
    }
    try {
      return await downloadIndex();
    } catch (e) {
      debugPrint('Failed to download the pack index: $e');
      return readCachedIndex();
    }
  }
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/metadata_pack_service.dart test/metadata_pack_service_test.dart
git commit -m "feat(packs): download e descompressao dos metadata packs"
```

---

### Task 5: Riverpod providers

**Files:**
- Create: `lib/providers/metadata_pack_provider.dart`
- Test: `test/metadata_pack_provider_test.dart`

The providers are thin on purpose: all the decision is in `PackIndex.resolve` from Task 2 and in `MetadataPackService` from Tasks 3 and 4. The test uses `ProviderContainer` with an override of the service, which is where the network and `path_provider` would come in.

- [ ] **Step 1: Write the failing test**

Create `test/metadata_pack_provider_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

const indexJson =
    '{"built":"2026-09-10","packs":[{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","games":1,"aliases":["super_nintendo"]}]}';
const packJson =
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/crystal-vanguard","title":"Crystal Vanguard","dumps":[]}]}';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('packs_provider_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer containerWith(PackFetch fetch) {
    final service = MetadataPackService(cacheDir: tmp, fetch: fetch);
    return ProviderContainer(overrides: [
      metadataPackServiceProvider.overrideWith((ref) async => service),
    ]);
  }

  test('packIndexProvider delivers the downloaded index', () async {
    final container = containerWith((uri) async => utf8.encode(indexJson));
    addTearDown(container.dispose);
    final index = await container.read(packIndexProvider.future);
    expect(index!.packs.single.pack, 'snes');
  });

  test('metadataPackProvider resolves by alias and downloads the pack', () async {
    final container = containerWith((uri) async {
      if (uri.path.endsWith('index.json')) return utf8.encode(indexJson);
      return gzip.encode(utf8.encode(packJson));
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('super_nintendo', 'Super Nintendo'))
            .future);
    expect(pack!.games.single.title, 'Crystal Vanguard');
  });

  test('a console absent from the index returns null without fetching a pack', () async {
    final requests = <Uri>[];
    final container = containerWith((uri) async {
      requests.add(uri);
      return utf8.encode(indexJson);
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('nintendo_switch', 'Nintendo Switch'))
            .future);
    expect(pack, isNull);
    expect(requests.every((u) => u.path.endsWith('index.json')), isTrue);
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/metadata_pack_provider_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/providers/metadata_pack_provider.dart'`.

- [ ] **Step 3: Write the providers**

Create `lib/providers/metadata_pack_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

/// The real service, pointing at `<support>/packs`.
final metadataPackServiceProvider =
    FutureProvider<MetadataPackService>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  return MetadataPackService(
    cacheDir: Directory(p.join(supportDir.path, 'packs')),
    fetch: MetadataPackService.httpFetch,
  );
});

/// The release index.json. Null when it could not be fetched and has no cache.
final packIndexProvider = FutureProvider<PackIndex?>((ref) async {
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.loadIndex();
});

/// A catalog console's pack. Null when the console has no pack, as with the
/// Nintendo Switch and any hand-added console that matches no alias.
final metadataPackProvider =
    FutureProvider.family<MetadataPack?, PackTarget>((ref, target) async {
  final index = await ref.watch(packIndexProvider.future);
  if (index == null) return null;
  final entry = index.resolve(target);
  if (entry == null) return null;
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.load(entry.pack);
});
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `flutter test test/metadata_pack_provider_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: PASS, with every previously existing test intact. This slice adds 31 Dart tests: 6 in Task 1, 8 in Task 2, 7 in Task 3, 7 in Task 4 and 3 here.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/metadata_pack_provider.dart test/metadata_pack_provider_test.dart
git commit -m "feat(packs): providers do metadata pack"
```

---

### Task 6: The builder, DAT parser

**Files:**
- Create: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

The libretro-database publishes two formats. The main DAT (`metadat/no-intro/*.dat` and `metadat/redump/*.dat`) carries `name`, `region` and one or more `rom` lines with `crc`, `md5` and `sha1`. The side files (`metadat/genre/*.dat`, `metadat/developer/*.dat` and company) carry `comment`, the field in question and a `rom ( crc ... )` that is the linking key.

Two verified facts that shape the design:

- The side files only exist for No-Intro systems. `metadat/genre/Sony - PlayStation.dat` responds 404. For Redump systems the enrichment comes only from OpenVGDB, and the builder needs to treat 404 as a normal case.
- On Redump the `serial` comes in the `game` block itself, so it does not depend on a side file. On No-Intro it comes from `metadat/serial/*.dat`.
- Redump disc games have several `rom` lines, one per track. The builder keeps the first, which is the data track. The track CRC does not match a downloaded `.chd`, and this is a known limitation: CRC verification is genuinely useful on cartridge systems.

- [ ] **Step 1: Write the failing test**

Create `tool/test_build_metadata_pack.py`:

```python
#!/usr/bin/env python3
"""Tests for the metadata pack builder. Nothing here touches the network."""
import unittest

import build_metadata_pack as b

NO_INTRO_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
\tdescription "Nintendo - Super Nintendo Entertainment System"
)

game (
\tname "'96 Zenith Cup Soccer (Japan)"
\tregion "Japan"
\trom ( name "'96 Zenith Cup Soccer (Japan).sfc" size 1572864 crc 05FBB855 md5 3369347F7663B133CE445C15200A5AFA sha1 005CCD8362DC41491F89F31FC9326A6688300E0C )
)
game (
\tname "Crystal Vanguard (USA)"
\tregion "USA"
\trom ( name "Crystal Vanguard (USA).sfc" size 4194304 crc 2D206BF7 md5 A2BC447961E52FD2227BAED164F729DC sha1 DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50 )
)
game (
\tname "No Hash (Japan)"
\tregion "Japan"
)
'''

REDUMP_DAT = '''clrmamepro (
\tname "Sony - PlayStation"
)

game (
\tname "'98 Ballpark (Japan)"
\tregion "Japan"
\tserial "SLPS-01204"
\trom ( name "'98 Ballpark (Japan).bin" size 583415952 crc 8ACD8FB1 md5 39A936EA7521157838D4E67B24F62F15 sha1 782C50827BF4CF8FE5530B64B188A2D43C75B0E0 serial "SLPS-01204" )
)
game (
\tname "'99 Ballpark (Japan)"
\tregion "Japan"
\tserial "SLPS-02110"
\trom ( name "'99 Ballpark (Japan) (Track 01).bin" size 314812848 crc 1D91CBAB md5 7BDC7092AEF04C6BEC7E78CDFE3D9A81 sha1 C1B7929C137E885569D30803664B26E496F32BB6 serial "SLPS-02110" )
\trom ( name "'99 Ballpark (Japan) (Track 02).bin" size 12345 crc AAAAAAAA md5 BB sha1 CC serial "SLPS-02110" )
)
'''

GENRE_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
)

game (
\tcomment "'96 Zenith Cup Soccer (Japan)"
\tgenre "Sports"
\trom ( crc 05FBB855 )
)
game (
\tcomment "Crystal Vanguard (USA)"
\tgenre "Role-Playing"
\trom ( crc 2d206bf7 )
)
'''

SERIAL_DAT = '''game (
\tcomment "'96 Zenith Cup Soccer (Japan)"
\tserial "SHVC-AY2J-JPN"
\trom (
\t\tcrc 05FBB855
\t)
)
'''


class ParseDatTest(unittest.TestCase):
    def test_reads_every_game(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[1]["name"], "Crystal Vanguard (USA)")

    def test_reads_the_first_rom_hashes_uppercased(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["crc"], "2D206BF7")
        self.assertEqual(entries[1]["sha1"], "DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50")

    def test_game_without_rom_line_keeps_null_hashes(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[2]["name"], "No Hash (Japan)")
        self.assertIsNone(entries[2]["crc"])
        self.assertIsNone(entries[2]["sha1"])

    def test_redump_serial_comes_from_the_game_block(self):
        entries = b.parse_dat(REDUMP_DAT)
        self.assertEqual(entries[0]["serial"], "SLPS-01204")

    def test_multitrack_redump_keeps_only_the_first_track(self):
        entries = b.parse_dat(REDUMP_DAT)
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[1]["crc"], "1D91CBAB")

    def test_no_intro_has_no_serial_in_the_main_dat(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertIsNone(entries[0]["serial"])

    def test_region_is_read_and_is_optional(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["region"], "USA")
        self.assertEqual(entries[0]["region"], "Japan")
        untagged = b.parse_dat('game (\n\tname "No Region"\n)\n')
        self.assertIsNone(untagged[0]["region"])


class ParseSideDatTest(unittest.TestCase):
    def test_maps_crc_to_value(self):
        side = b.parse_side_dat(GENRE_DAT, "genre")
        self.assertEqual(side["05FBB855"], "Sports")

    def test_crc_key_is_uppercased(self):
        side = b.parse_side_dat(GENRE_DAT, "genre")
        self.assertEqual(side["2D206BF7"], "Role-Playing")

    def test_handles_multiline_rom_blocks(self):
        side = b.parse_side_dat(SERIAL_DAT, "serial")
        self.assertEqual(side["05FBB855"], "SHVC-AY2J-JPN")

    def test_unknown_field_gives_an_empty_map(self):
        self.assertEqual(b.parse_side_dat(GENRE_DAT, "publisher"), {})


class SystemsTableTest(unittest.TestCase):
    def test_has_twenty_four_systems(self):
        self.assertEqual(len(b.SYSTEMS), 24)

    def test_pack_ids_are_unique_and_normalized(self):
        ids = [b.normalize(s["system"]) for s in b.SYSTEMS]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("nintendo_super_nintendo_entertainment_system", ids)

    def test_aliases_do_not_collide_across_systems(self):
        seen = {}
        for s in b.SYSTEMS:
            for alias in s["aliases"]:
                self.assertNotIn(alias, seen, f"{alias} repeated in {s['system']}")
                seen[alias] = s["system"]

    def test_every_system_declares_dat_group_and_thumbs(self):
        for s in b.SYSTEMS:
            self.assertIn(s["group"], ("no-intro", "redump"))
            self.assertTrue(s["thumbs"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py' -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'build_metadata_pack'`.

- [ ] **Step 3: Write the parser and the systems table**

Create `tool/build_metadata_pack.py`:

```python
#!/usr/bin/env python3
"""Builds one metadata pack per console for the app's game grid.

Sources, all public and without accounts:
  - libretro-database (CC BY-SA 4.0): the No-Intro and Redump DATs under
    metadat/, plus the per-field side files (genre, developer, publisher,
    releaseyear, franchise, esrb, serial) that key on CRC32.
  - OpenVGDB v29.0: synopsis and a fallback cover, joined by CRC32.
  - libretro-thumbnails: the preferred cover URL, checked for existence via
    the GitHub tree API so the pack never ships a dead link.

Output: <pack>.json.gz per system plus an index.json, both meant to be
uploaded to a GitHub release with the fixed tag "packs". The pack stores the
cover URL, never the image bytes.
"""
import gzip
import io
import json
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

LIBRETRO_RAW = "https://raw.githubusercontent.com/libretro/libretro-database/master"
THUMBS_API = "https://api.github.com/repos/libretro-thumbnails/{repo}/git/trees/master:Named_Boxarts"
THUMBS_RAW = "https://raw.githubusercontent.com/libretro-thumbnails/{repo}/master/Named_Boxarts/{name}"
OPENVGDB_URL = "https://github.com/OpenVGDB/OpenVGDB/releases/download/v29.0/openvgdb.zip"

SIDE_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "releaseyear": "releaseyear",
    "franchise": "franchise",
    "esrb": "esrb_rating",
    "serial": "serial",
}

SYSTEMS = [
    {"system": "Coleco - ColecoVision", "group": "no-intro",
     "thumbs": "Coleco_-_ColecoVision", "aliases": ["colecovision", "coleco"]},
    {"system": "Mattel - Intellivision", "group": "no-intro",
     "thumbs": "Mattel_-_Intellivision", "aliases": ["intellivision"]},
    {"system": "Nintendo - Game Boy", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy", "aliases": ["game_boy", "gb"]},
    {"system": "Nintendo - Game Boy Color", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy_Color", "aliases": ["game_boy_color", "gbc"]},
    {"system": "Nintendo - Game Boy Advance", "group": "no-intro",
     "thumbs": "Nintendo_-_Game_Boy_Advance", "aliases": ["game_boy_advance", "gba"]},
    {"system": "Nintendo - Nintendo DS", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_DS", "aliases": ["nintendo_ds", "nds", "ds"]},
    {"system": "Nintendo - Nintendo 3DS", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_3DS", "aliases": ["nintendo_3ds", "3ds"]},
    {"system": "Nintendo - Nintendo 64", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_64", "aliases": ["nintendo_64", "n64"]},
    {"system": "Nintendo - Nintendo Entertainment System", "group": "no-intro",
     "thumbs": "Nintendo_-_Nintendo_Entertainment_System",
     "aliases": ["nintendo_entertainment_system", "nes", "famicom"]},
    {"system": "Nintendo - Super Nintendo Entertainment System", "group": "no-intro",
     "thumbs": "Nintendo_-_Super_Nintendo_Entertainment_System",
     "aliases": ["super_nintendo", "snes", "super_famicom", "sfc"]},
    {"system": "Nintendo - Wii U (Digital)", "group": "no-intro",
     "thumbs": "Nintendo_-_Wii_U", "aliases": ["nintendo_wii_u", "wii_u", "wiiu"]},
    {"system": "Sega - Game Gear", "group": "no-intro",
     "thumbs": "Sega_-_Game_Gear", "aliases": ["game_gear", "gamegear", "gg"]},
    {"system": "Sega - Mega Drive - Genesis", "group": "no-intro",
     "thumbs": "Sega_-_Mega_Drive_-_Genesis",
     "aliases": ["sega_genesis", "genesis", "mega_drive", "megadrive"]},
    {"system": "Microsoft - Xbox", "group": "redump",
     "thumbs": "Microsoft_-_Xbox", "aliases": ["xbox"]},
    {"system": "Microsoft - Xbox 360", "group": "redump",
     "thumbs": "Microsoft_-_Xbox_360", "aliases": ["xbox_360", "x360"]},
    {"system": "Nintendo - GameCube", "group": "redump",
     "thumbs": "Nintendo_-_GameCube",
     "aliases": ["nintendo_game_cube", "gamecube", "ngc", "gc"]},
    {"system": "Nintendo - Wii", "group": "redump",
     "thumbs": "Nintendo_-_Wii", "aliases": ["nintendo_wii", "wii"]},
    {"system": "Sega - Dreamcast", "group": "redump",
     "thumbs": "Sega_-_Dreamcast", "aliases": ["sega_dreamcast", "dreamcast", "dc"]},
    {"system": "Sega - Saturn", "group": "redump",
     "thumbs": "Sega_-_Saturn", "aliases": ["sega_saturn", "saturn"]},
    {"system": "Sony - PlayStation", "group": "redump",
     "thumbs": "Sony_-_PlayStation",
     "aliases": ["playstation_1", "playstation", "ps1", "psx"]},
    {"system": "Sony - PlayStation 2", "group": "redump",
     "thumbs": "Sony_-_PlayStation_2", "aliases": ["playstation_2", "ps2"]},
    {"system": "Sony - PlayStation 3", "group": "redump",
     "thumbs": "Sony_-_PlayStation_3", "aliases": ["playstation_3", "ps3"]},
    {"system": "Sony - PlayStation Portable", "group": "redump",
     "thumbs": "Sony_-_PlayStation_Portable", "aliases": ["playstation_portable", "psp"]},
    {"system": "The 3DO Company - 3DO", "group": "redump",
     "thumbs": "The_3DO_Company_-_3DO", "aliases": ["panasonic_3do", "3do"]},
]

GAME_RE = re.compile(r"game \(\s*(.*?)\n\)", re.S)
NAME_RE = re.compile(r'^\s*name "([^"]+)"', re.M)
SERIAL_RE = re.compile(r'^\s*serial "([^"]+)"', re.M)
REGION_RE = re.compile(r'^\s*region "([^"]+)"', re.M)
# md5 is captured only so the sha1 group lands in the right position; it is
# discarded.
ROM_RE = re.compile(
    r'rom \( name "([^"]+)"(?:\s+size \d+)?\s+crc (\w+)'
    r"(?:\s+md5 (\w+))?(?:\s+sha1 (\w+))?"
)
CRC_RE = re.compile(r"crc (\w+)")


def normalize(value):
    """Same rule as CatalogService._nameToId in the app."""
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.lower()))


def parse_dat(text):
    """Parses a No-Intro or Redump main DAT into a list of dumps.

    Only the first rom line of each block is kept; crc and sha1 are uppercased.
    """
    entries = []
    for block in GAME_RE.findall(text):
        name = NAME_RE.search(block)
        if not name:
            continue
        rom = ROM_RE.search(block)
        serial = SERIAL_RE.search(block)
        region = REGION_RE.search(block)
        entries.append({
            "name": name.group(1),
            "crc": rom.group(2).upper() if rom else None,
            "sha1": rom.group(4).upper() if rom and rom.group(4) else None,
            "serial": serial.group(1) if serial else None,
            "region": region.group(1) if region else None,
        })
    return entries


def parse_side_dat(text, field):
    """Parses a per-field side file into an uppercase-CRC32 to value map."""
    field_re = re.compile(field + r' "([^"]+)"')
    out = {}
    for block in GAME_RE.findall(text):
        crc = CRC_RE.search(block)
        value = field_re.search(block)
        if crc and value:
            out[crc.group(1).upper()] = value.group(1)
    return out


def main():
    raise SystemExit("CLI not implemented yet, see Task 10")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py' -v`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): parser de DAT e tabela dos 24 sistemas"
```

---

### Task 7: The builder, collapse into canonical games

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Here lives the reason the pack exists: the SNES DAT has 4268 dumps and the user wants to see 2415 games. `canon` throws away region, revision, language and tags and returns the game title; dumps that share the same `canon` become one `PackGame`. `norm` and `canon` are the port of what the PoC measured, with one fix: in the PoC the trailing-article swap ran after `norm`, which had already eaten the comma in "Legend of Kaelis, The", so it never happened. Here it runs on the raw name, inside `display_title`.

- [ ] **Step 1: Write the failing test**

Add to `tool/test_build_metadata_pack.py`, before the `if __name__` block:

```python
class NormTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(b.norm("Crystal Vanguard (USA)"), "crystal vanguard (usa)")

    def test_expands_ampersand(self):
        self.assertEqual(b.norm("Grip & Slam"), "grip and slam")

    def test_drops_accents(self):
        self.assertEqual(b.norm("Prismón Rojo"), "prismon rojo")

    def test_strips_rom_extensions(self):
        self.assertEqual(b.norm("Crystal Vanguard (USA).sfc"), "crystal vanguard (usa)")
        self.assertEqual(b.norm("Crystal Vanguard (USA).zip"), "crystal vanguard (usa)")


class CanonTest(unittest.TestCase):
    def test_drops_region_and_revision_tags(self):
        self.assertEqual(b.canon("Crystal Vanguard (USA) (Rev 1)"), "crystal vanguard")
        self.assertEqual(b.canon("Crystal Vanguard (Japan) [T+Eng]"), "crystal vanguard")

    def test_moves_the_trailing_article_to_the_front(self):
        self.assertEqual(b.canon("Legend of Kaelis, The (USA)"), "the legend of kaelis")

    def test_different_regions_share_one_canon(self):
        self.assertEqual(
            b.canon("Super Pixel World (USA)"), b.canon("Super Pixel World (Europe)")
        )


class DisplayTitleTest(unittest.TestCase):
    def test_keeps_the_original_casing(self):
        self.assertEqual(b.display_title("Crystal Vanguard (USA)"), "Crystal Vanguard")

    def test_moves_the_article_without_lowercasing_the_rest(self):
        self.assertEqual(
            b.display_title("Legend of Kaelis, The (USA)"), "The Legend of Kaelis"
        )

    def test_keeps_accents_and_punctuation(self):
        self.assertEqual(b.display_title("Prismón Rojo (Spain).gb"), "Prismón Rojo")

    def test_name_that_is_only_tags_becomes_empty(self):
        self.assertEqual(b.display_title("(USA)"), "")


class SlugTest(unittest.TestCase):
    def test_makes_a_url_safe_slug(self):
        self.assertEqual(b.slug("the legend of kaelis"), "the-legend-of-kaelis")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(b.slug("f-blaze  ii!!"), "f-blaze-ii")


class CollapseTest(unittest.TestCase):
    def setUp(self):
        self.entries = [
            {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7", "sha1": "A",
             "serial": None, "region": "USA"},
            {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C", "sha1": "B",
             "serial": None, "region": "Japan"},
            {"name": "Legend of Kaelis, The (USA)", "crc": "AAAAAAAA", "sha1": None,
             "serial": None, "region": None},
        ]

    def test_dumps_of_the_same_game_collapse_into_one_entry(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(len(games), 2)
        self.assertEqual(len(games[0]["dumps"]), 2)

    def test_title_comes_from_the_first_dump_without_its_tags(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["title"], "Crystal Vanguard")
        self.assertEqual(games[1]["title"], "The Legend of Kaelis")

    def test_id_is_pack_slash_slug(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["id"], "snes/crystal-vanguard")
        self.assertEqual(games[1]["id"], "snes/the-legend-of-kaelis")

    def test_dump_order_is_the_dat_order(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(
            [d["name"] for d in games[0]["dumps"]],
            ["Crystal Vanguard (USA)", "Crystal Vanguard (Japan)"],
        )

    def test_hyphen_and_space_spellings_are_the_same_game(self):
        entries = [
            {"name": "Pix-Man (USA)", "crc": "1", "sha1": None, "serial": None},
            {"name": "Pix Man (Japan)", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "nes")
        self.assertEqual(len(games), 1)
        self.assertEqual(games[0]["id"], "nes/pix-man")

    def test_two_titles_with_the_same_slug_get_a_numeric_suffix(self):
        entries = [
            {"name": "Sprint (Beta", "crc": "1", "sha1": None, "serial": None},
            {"name": "Sprint Beta", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "md")
        self.assertEqual(len(games), 2)
        self.assertEqual(games[0]["id"], "md/sprint-beta")
        self.assertEqual(games[1]["id"], "md/sprint-beta-2")

    def test_region_travels_to_the_dump_and_is_omitted_when_absent(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["dumps"][0]["region"], "USA")
        self.assertEqual(games[0]["dumps"][1]["region"], "Japan")
        self.assertNotIn("region", games[1]["dumps"][0])

    def test_entries_without_a_canon_title_are_dropped(self):
        entries = [{"name": "(USA)", "crc": "1", "sha1": None, "serial": None}]
        self.assertEqual(b.collapse(entries, "nes"), [])
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'norm'`.

- [ ] **Step 3: Implement norm, canon, slug and collapse**

In `tool/build_metadata_pack.py`, right after `def parse_side_dat(...)`, add:

```python
ROM_EXTS = (".zip", ".7z", ".sfc", ".smc", ".fig", ".swc", ".bin", ".rar", ".gz",
            ".nes", ".gb", ".gbc", ".gba", ".nds", ".3ds", ".n64", ".z64", ".v64",
            ".md", ".gen", ".gg", ".iso", ".cue", ".chd", ".col", ".int")
ARTICLE_RE = re.compile(
    r"^(.*?), (the|a|an|le|la|les|el|los|das|der|die)$", re.I)
TAG_RE = re.compile(r"\([^)]*\)|\[[^\]]*\]")


def strip_ext(name):
    low = name.lower()
    for ext in sorted(ROM_EXTS, key=len, reverse=True):
        if low.endswith(ext):
            return name[: -len(ext)]
    return name


def norm(value):
    """Comparable form of a filename: no extension, accents, or punctuation,
    but region and revision tags preserved."""
    value = strip_ext(value)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(c for c in value if not unicodedata.combining(c))
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9()\[\]]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def display_title(dat_name):
    """Display title from a DAT name: no extension, no region or revision tags,
    with the trailing article moved to the front."""
    value = TAG_RE.sub(" ", strip_ext(dat_name))
    value = re.sub(r"\s+", " ", value).strip().strip(",").strip()
    match = ARTICLE_RE.match(value)
    if match:
        value = f"{match.group(2)} {match.group(1)}"
    return value


def canon(value):
    """Canonical game title, the grouping key: the display title run through
    norm."""
    return norm(display_title(value))


def slug(value):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", value.lower()))


def collapse(entries, pack_id):
    """Collapses DAT dumps into canonical games, in order of appearance."""
    games = []
    by_canon = {}
    used_slugs = {}
    for entry in entries:
        key = canon(entry["name"])
        if not key:
            continue
        game = by_canon.get(key)
        if game is None:
            base = slug(key)
            count = used_slugs.get(base, 0) + 1
            used_slugs[base] = count
            game_slug = base if count == 1 else f"{base}-{count}"
            game = {
                "id": f"{pack_id}/{game_slug}",
                "title": display_title(entry["name"]),
                "dumps": [],
            }
            by_canon[key] = game
            games.append(game)
        dump = {"name": entry["name"]}
        for field in ("crc", "sha1", "serial", "region"):
            if entry.get(field):
                dump[field] = entry[field]
        game["dumps"].append(dump)
    return games
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 36 tests.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): colapso de dumps em jogos canonicos"
```

---

### Task 8: The builder, enrichment from the side files

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

The side files key on a dump's CRC32. A canonical game has several dumps, so the rule is: the first dump that has a value for the field wins. That favors the region that appears first in the DAT, which is alphabetical order, and it is deterministic.

- [ ] **Step 1: Write the failing test**

Add to `tool/test_build_metadata_pack.py`, before the `if __name__` block:

```python
class EnrichTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/crystal-vanguard",
            "title": "Crystal Vanguard",
            "dumps": [
                {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C"},
                {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"},
            ],
        }]

    def test_fills_the_fields_from_the_side_maps(self):
        games = self.games()
        b.enrich_from_side(games, {
            "genre": {"2D206BF7": "Role-Playing"},
            "developer": {"2D206BF7": "Square"},
            "publisher": {"2D206BF7": "Square"},
            "releaseyear": {"2D206BF7": "1995"},
        })
        self.assertEqual(games[0]["genre"], "Role-Playing")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["publisher"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_the_first_dump_with_a_value_wins(self):
        games = self.games()
        b.enrich_from_side(games, {
            "genre": {"1F2E3D4C": "Action", "2D206BF7": "Role-Playing"},
        })
        self.assertEqual(games[0]["genre"], "Action")

    def test_serial_lands_on_the_dump_not_on_the_game(self):
        games = self.games()
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertNotIn("serial", games[0])
        self.assertEqual(games[0]["dumps"][1]["serial"], "SNS-AC-USA")

    def test_serial_already_on_the_dump_is_not_overwritten(self):
        games = self.games()
        games[0]["dumps"][1]["serial"] = "ALREADY-THERE"
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertEqual(games[0]["dumps"][1]["serial"], "ALREADY-THERE")

    def test_missing_side_maps_leave_the_game_untouched(self):
        games = self.games()
        b.enrich_from_side(games, {})
        self.assertEqual(set(games[0]), {"id", "title", "dumps"})

    def test_non_numeric_year_is_ignored(self):
        games = self.games()
        b.enrich_from_side(games, {"releaseyear": {"2D206BF7": "199x"}})
        self.assertNotIn("year", games[0])

    def test_franchise_and_esrb_are_carried_over(self):
        games = self.games()
        b.enrich_from_side(games, {
            "franchise": {"2D206BF7": "Crystal"},
            "esrb": {"2D206BF7": "E"},
        })
        self.assertEqual(games[0]["franchise"], "Crystal")
        self.assertEqual(games[0]["esrb"], "E")
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'enrich_from_side'`.

- [ ] **Step 3: Implement the enrichment**

In `tool/build_metadata_pack.py`, right after `def collapse(...)`, add:

```python
GAME_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "franchise": "franchise",
    "esrb": "esrb",
}


def enrich_from_side(games, side_maps):
    """Fills game fields from the CRC-to-value maps; the first dump with a
    value for a field wins."""
    for game in games:
        for source, target in GAME_FIELDS.items():
            table = side_maps.get(source)
            if not table:
                continue
            for dump in game["dumps"]:
                value = table.get(dump.get("crc"))
                if value:
                    game[target] = value
                    break
        years = side_maps.get("releaseyear")
        if years:
            for dump in game["dumps"]:
                value = years.get(dump.get("crc"))
                if value and value.isdigit():
                    game["year"] = int(value)
                    break
        serials = side_maps.get("serial")
        if serials:
            for dump in game["dumps"]:
                if dump.get("serial"):
                    continue
                value = serials.get(dump.get("crc"))
                if value:
                    dump["serial"] = value
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 43 tests.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): enriquecimento pelos side files do libretro-database"
```

---

### Task 9: The builder, covers and synopsis

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Two sources, with a preference order. The preferred cover is the libretro-thumbnails one, because the PoC measured 86.8% coverage against 75.6% for OpenVGDB and the union gives 89.6%. OpenVGDB comes in as a cover fallback and as the only synopsis source.

Two verified details the code must respect:

- The file name on libretro-thumbnails is the DAT name with `&*/:` and other forbidden characters replaced by `_`, plus `.png`. An example of the rule: `Guild _ Dungeon - Eye of the Watcher (USA).png`.
- The `Named_Boxarts` tree fits in a single GitHub API call, even for the PlayStation, which has 9301 files and does not come back truncated.

The cover choice among a game's dumps follows region priority: USA, World, Europe, Japan and then any, so the user sees the cover they recognize.

- [ ] **Step 1: Write the failing test**

Add to `tool/test_build_metadata_pack.py`, before the `if __name__` block:

```python
import sqlite3


class ThumbNameTest(unittest.TestCase):
    def test_keeps_the_dat_name_and_adds_png(self):
        self.assertEqual(b.thumb_name("Crystal Vanguard (USA)"), "Crystal Vanguard (USA).png")

    def test_replaces_the_characters_libretro_forbids(self):
        self.assertEqual(
            b.thumb_name("Guild & Dungeon - Eye of the Watcher (USA)"),
            "Guild _ Dungeon - Eye of the Watcher (USA).png",
        )
        self.assertEqual(b.thumb_name("Sprocket: Deadlocked"), "Sprocket_ Deadlocked.png")


class RegionPriorityTest(unittest.TestCase):
    def test_usa_beats_japan(self):
        self.assertLess(
            b.region_rank("Crystal Vanguard (USA)"), b.region_rank("Crystal Vanguard (Japan)")
        )

    def test_world_beats_europe(self):
        self.assertLess(
            b.region_rank("Sprint (World)"), b.region_rank("Sprint (Europe)")
        )

    def test_unknown_region_goes_last(self):
        self.assertGreater(
            b.region_rank("Sprint (Korea)"), b.region_rank("Sprint (Japan)")
        )


class AttachCoversTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/crystal-vanguard",
            "title": "Crystal Vanguard",
            "dumps": [
                {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C"},
                {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"},
            ],
        }]

    def test_picks_the_preferred_region_cover(self):
        games = self.games()
        available = {"Crystal Vanguard (Japan).png", "Crystal Vanguard (USA).png"}
        b.attach_thumbnail_covers(games, available, "Nintendo_-_Super_Nintendo_Entertainment_System")
        self.assertEqual(
            games[0]["cover"],
            "https://raw.githubusercontent.com/libretro-thumbnails/"
            "Nintendo_-_Super_Nintendo_Entertainment_System/master/Named_Boxarts/"
            "Crystal%20Vanguard%20%28USA%29.png",
        )

    def test_falls_back_to_the_only_available_region(self):
        games = self.games()
        b.attach_thumbnail_covers(games, {"Crystal Vanguard (Japan).png"}, "R")
        self.assertIn("Japan", games[0]["cover"])

    def test_no_thumbnail_leaves_the_game_without_cover(self):
        games = self.games()
        b.attach_thumbnail_covers(games, set(), "R")
        self.assertNotIn("cover", games[0])


class OpenVgdbTest(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.executescript('''
            CREATE TABLE ROMs (romID INTEGER, romHashCRC TEXT);
            CREATE TABLE RELEASES (romID INTEGER, releaseDescription TEXT,
                releaseCoverFront TEXT, releaseDeveloper TEXT,
                releasePublisher TEXT, releaseGenre TEXT, releaseDate TEXT);
            INSERT INTO ROMs VALUES (1, '2D206BF7');
            INSERT INTO RELEASES VALUES (1, 'An RPG.', 'https://img/ct.jpg',
                'Square', 'Square', 'Role-Playing', 'Mar 11, 1995');
            INSERT INTO ROMs VALUES (2, 'AAAAAAAA');
            INSERT INTO RELEASES VALUES (2, NULL, NULL, NULL, NULL, NULL, NULL);
        ''')

    def test_index_is_keyed_by_uppercase_crc(self):
        index = b.openvgdb_index(self.conn)
        self.assertIn("2D206BF7", index)
        self.assertEqual(index["2D206BF7"]["synopsis"], "An RPG.")

    def test_year_is_extracted_from_the_release_date(self):
        index = b.openvgdb_index(self.conn)
        self.assertEqual(index["2D206BF7"]["year"], 1995)

    def test_rows_without_any_useful_field_are_skipped(self):
        self.assertNotIn("AAAAAAAA", b.openvgdb_index(self.conn))

    def test_enrich_fills_only_what_is_missing(self):
        games = [{
            "id": "snes/crystal-vanguard", "title": "Crystal Vanguard",
            "genre": "RPG",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["genre"], "RPG")
        self.assertEqual(games[0]["synopsis"], "An RPG.")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_openvgdb_cover_is_only_a_fallback(self):
        games = [{
            "id": "a", "title": "A", "cover": "https://libretro/x.png",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://libretro/x.png")

    def test_openvgdb_cover_is_used_when_there_is_none(self):
        games = [{
            "id": "a", "title": "A",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://img/ct.jpg")
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'thumb_name'`.

- [ ] **Step 3: Implement covers and synopsis**

In `tool/build_metadata_pack.py`, right after `def enrich_from_side(...)`, add:

```python
# libretro-thumbnails replaces these characters with "_" in the filename.
THUMB_FORBIDDEN_RE = re.compile(r"[&*/:`<>?\\|]")
REGION_ORDER = ["(usa", "(world", "(europe", "(japan"]
YEAR_RE = re.compile(r"(19|20)\d{2}")


def thumb_name(dat_name):
    return THUMB_FORBIDDEN_RE.sub("_", dat_name) + ".png"


def region_rank(dat_name):
    low = dat_name.lower()
    for index, marker in enumerate(REGION_ORDER):
        if marker in low:
            return index
    return len(REGION_ORDER)


def attach_thumbnail_covers(games, available, repo):
    """Picks the libretro-thumbnails cover of the best-region dump that
    actually exists in the repository."""
    for game in games:
        best = None
        for dump in sorted(game["dumps"], key=lambda d: region_rank(d["name"])):
            name = thumb_name(dump["name"])
            if name in available:
                best = name
                break
        if best is None:
            continue
        game["cover"] = THUMBS_RAW.format(
            repo=repo, name=urllib.parse.quote(best, safe="")
        )


def openvgdb_index(conn):
    """Maps uppercase CRC32 to the useful OpenVGDB fields."""
    rows = conn.execute(
        "SELECT r.romHashCRC, rel.releaseDescription, rel.releaseCoverFront, "
        "rel.releaseDeveloper, rel.releasePublisher, rel.releaseGenre, rel.releaseDate "
        "FROM ROMs r JOIN RELEASES rel ON rel.romID = r.romID"
    )
    index = {}
    for crc, synopsis, cover, developer, publisher, genre, date in rows:
        if not crc:
            continue
        year = None
        if date:
            match = YEAR_RE.search(date)
            if match:
                year = int(match.group(0))
        record = {"synopsis": synopsis, "cover": cover, "developer": developer,
                  "publisher": publisher, "genre": genre, "year": year}
        if not any(record.values()):
            continue
        index.setdefault(crc.upper(), record)
    return index


def enrich_from_openvgdb(games, index):
    """Fills gaps only; libretro-database always wins over OpenVGDB."""
    for game in games:
        for dump in game["dumps"]:
            record = index.get(dump.get("crc"))
            if not record:
                continue
            for field in ("synopsis", "cover", "developer", "publisher", "genre", "year"):
                if record.get(field) and not game.get(field):
                    game[field] = record[field]
            break
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 57 tests.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): capas do libretro-thumbnails e sinopse do OpenVGDB"
```

---

### Task 10: The builder, network, output and CLI

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Now the network comes in, but isolated in three thin functions (`fetch_text`, `fetch_json`, `download_openvgdb`) so the testable parts stay pure. What the tests cover here is the assembly of the pack and the index, with an injected `fetch` function.

The gzip goes out with `mtime=0` so a rebuild with no data change produces identical bytes, which makes it obvious in the release diff when nothing changed.

- [ ] **Step 1: Write the failing test**

Add to `tool/test_build_metadata_pack.py`, before the `if __name__` block:

```python
import gzip
import json


class BuildPackTest(unittest.TestCase):
    def test_assembles_the_pack_document(self):
        pack = b.build_pack(
            system={"system": "Nintendo - Super Nintendo Entertainment System",
                    "group": "no-intro",
                    "thumbs": "Nintendo_-_Super_Nintendo_Entertainment_System",
                    "aliases": ["snes"]},
            dat_text=NO_INTRO_DAT,
            side_texts={"genre": GENRE_DAT, "serial": SERIAL_DAT},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        self.assertEqual(pack["pack"], "nintendo_super_nintendo_entertainment_system")
        self.assertEqual(pack["system"], "Nintendo - Super Nintendo Entertainment System")
        self.assertEqual(pack["built"], "2026-09-10")
        self.assertEqual(len(pack["games"]), 3)

    def test_side_data_reaches_the_games(self):
        pack = b.build_pack(
            system={"system": "Nintendo - Super Nintendo Entertainment System",
                    "group": "no-intro", "thumbs": "T", "aliases": []},
            dat_text=NO_INTRO_DAT,
            side_texts={"genre": GENRE_DAT, "serial": SERIAL_DAT},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        by_id = {g["id"]: g for g in pack["games"]}
        vanguard = by_id["nintendo_super_nintendo_entertainment_system/crystal-vanguard"]
        self.assertEqual(vanguard["genre"], "Role-Playing")

    def test_missing_side_files_are_tolerated(self):
        pack = b.build_pack(
            system={"system": "Sony - PlayStation", "group": "redump",
                    "thumbs": "T", "aliases": []},
            dat_text=REDUMP_DAT,
            side_texts={},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        self.assertEqual(len(pack["games"]), 2)
        self.assertEqual(pack["games"][0]["dumps"][0]["serial"], "SLPS-01204")


class WritePackTest(unittest.TestCase):
    def test_gzip_round_trips_and_is_deterministic(self):
        pack = {"pack": "snes", "system": "S", "built": "2026-09-10", "games": []}
        first = b.pack_bytes(pack)
        second = b.pack_bytes(pack)
        self.assertEqual(first, second)
        self.assertEqual(json.loads(gzip.decompress(first).decode("utf-8")), pack)


class BuildIndexTest(unittest.TestCase):
    def test_index_carries_pack_system_count_and_aliases(self):
        packs = [{"pack": "snes", "system": "Nintendo - Super Nintendo Entertainment System",
                  "built": "2026-09-10", "games": [{"id": "a"}, {"id": "b"}]}]
        aliases = {"snes": ["super_nintendo", "snes"]}
        index = b.build_index(packs, aliases, "2026-09-10")
        self.assertEqual(index["built"], "2026-09-10")
        self.assertEqual(index["packs"], [{
            "pack": "snes",
            "system": "Nintendo - Super Nintendo Entertainment System",
            "games": 2,
            "aliases": ["super_nintendo", "snes"],
        }])

    def test_empty_pack_list_still_produces_a_valid_index(self):
        self.assertEqual(b.build_index([], {}, "2026-09-10"),
                         {"built": "2026-09-10", "packs": []})
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'build_pack'`.

- [ ] **Step 3: Implement assembly, output and CLI**

In `tool/build_metadata_pack.py`, right after `def enrich_from_openvgdb(...)`, add:

```python
def build_pack(system, dat_text, side_texts, thumbs, openvgdb, built):
    """Assembles everything into a pack document ready to serialize."""
    pack_id = normalize(system["system"])
    games = collapse(parse_dat(dat_text), pack_id)
    side_maps = {
        source: parse_side_dat(text, SIDE_FIELDS[source])
        for source, text in side_texts.items()
    }
    enrich_from_side(games, side_maps)
    attach_thumbnail_covers(games, thumbs, system["thumbs"])
    enrich_from_openvgdb(games, openvgdb)
    return {"pack": pack_id, "system": system["system"], "built": built, "games": games}


def pack_bytes(pack):
    """Compact JSON in deterministic gzip: mtime zeroed so an unchanged
    rebuild produces identical bytes."""
    raw = json.dumps(pack, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as out:
        out.write(raw)
    return buffer.getvalue()


def build_index(packs, aliases, built):
    return {
        "built": built,
        "packs": [{
            "pack": pack["pack"],
            "system": pack["system"],
            "games": len(pack["games"]),
            "aliases": aliases.get(pack["pack"], []),
        } for pack in packs],
    }
```

Add `import argparse`, `import tempfile` and `import zipfile` to the import block
at the top of the file, keeping the alphabetical order that is already there.

Now replace the provisional `def main()` from Task 6 with:

```python
def fetch_text(url, optional=False):
    """Downloads text. With optional=True a 404 returns None."""
    try:
        with urllib.request.urlopen(url, timeout=180) as response:
            return response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        if optional and error.code == 404:
            return None
        raise


def fetch_json(url, token=None):
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


def thumbnail_names(repo, token=None):
    """Filenames in Named_Boxarts; a truncated tree returns an empty set."""
    try:
        tree = fetch_json(THUMBS_API.format(repo=repo), token)
    except urllib.error.HTTPError as error:
        print(f"  thumbnails for {repo} unavailable: HTTP {error.code}", file=sys.stderr)
        return set()
    if tree.get("truncated"):
        print(f"  tree for {repo} truncated, skipping covers", file=sys.stderr)
        return set()
    return {entry["path"] for entry in tree.get("tree", [])}


def download_openvgdb(dest_dir):
    """Downloads and unzips openvgdb.sqlite, returning the connection."""
    zip_path = os.path.join(dest_dir, "openvgdb.zip")
    urllib.request.urlretrieve(OPENVGDB_URL, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(dest_dir)
    return sqlite3.connect(os.path.join(dest_dir, "openvgdb.sqlite"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="dist/packs", help="output directory")
    parser.add_argument("--built", required=True, help="build date, YYYY-MM-DD")
    parser.add_argument("--only", action="append", default=[],
                        help="build only these pack ids, repeatable")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    token = os.environ.get("GITHUB_TOKEN")
    selected = [s for s in SYSTEMS
                if not args.only or normalize(s["system"]) in args.only]
    if not selected:
        raise SystemExit(f"no system matches {args.only}")

    with tempfile.TemporaryDirectory() as tmp:
        conn = download_openvgdb(tmp)
        openvgdb = openvgdb_index(conn)
        conn.close()
        print(f"OpenVGDB: {len(openvgdb)} CRCs")

        packs = []
        aliases = {}
        for system in selected:
            pack_id = normalize(system["system"])
            print(f"{system['system']}")
            dat_url = "{}/metadat/{}/{}.dat".format(
                LIBRETRO_RAW, system["group"],
                urllib.parse.quote(system["system"]))
            dat_text = fetch_text(dat_url)
            side_texts = {}
            for source in SIDE_FIELDS:
                url = "{}/metadat/{}/{}.dat".format(
                    LIBRETRO_RAW, source, urllib.parse.quote(system["system"]))
                text = fetch_text(url, optional=True)
                if text is not None:
                    side_texts[source] = text
            thumbs = thumbnail_names(system["thumbs"], token)
            pack = build_pack(system, dat_text, side_texts, thumbs, openvgdb, args.built)
            with_cover = sum(1 for g in pack["games"] if g.get("cover"))
            with_synopsis = sum(1 for g in pack["games"] if g.get("synopsis"))
            print(f"  {len(pack['games'])} games, {with_cover} with cover, "
                  f"{with_synopsis} with synopsis")
            path = os.path.join(args.out, f"{pack_id}.json.gz")
            with open(path, "wb") as out:
                out.write(pack_bytes(pack))
            packs.append(pack)
            aliases[pack_id] = system["aliases"]

        index = build_index(packs, aliases, args.built)
        with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as out:
            json.dump(index, out, ensure_ascii=False, indent=2)
        print(f"{len(packs)} packs in {args.out}")
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 63 tests.

- [ ] **Step 5: Check that the CLI loads**

Run: `python3 tool/build_metadata_pack.py --help`
Expected: the help text with `--out`, `--built` and `--only`, no traceback.

- [ ] **Step 6: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): montagem, saida gzip e CLI do builder"
```

---

### Task 11: The workflow that publishes the release

**Files:**
- Create: `.github/workflows/metadata-packs.yml`

The tag is fixed, `packs`, and the release is updated in place. That is what keeps the download URL stable and lets the app download without ever calling the GitHub API. The build date lives in the JSON `built` and in the release body.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/metadata-packs.yml`:

```yaml
name: Metadata Packs

on:
  workflow_dispatch:
  schedule:
    # Day 3 at 05:00 UTC, a few days after libretro-database publishes the month's DATs.
    - cron: '0 5 3 * *'

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Run builder tests
        working-directory: tool
        run: python3 -m unittest discover -s . -p 'test_*.py' -v

      - name: Build packs
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          python3 tool/build_metadata_pack.py \
            --out dist/packs \
            --built "$(date -u +%Y-%m-%d)"

      - name: Check the output
        run: |
          test -f dist/packs/index.json
          count=$(python3 -c "import json;print(len(json.load(open('dist/packs/index.json'))['packs']))")
          test "$count" -eq 24 || { echo "expected 24 packs, got $count"; exit 1; }
          ls -lh dist/packs

      - name: Publish the packs release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          built=$(date -u +%Y-%m-%d)
          if gh release view packs >/dev/null 2>&1; then
            gh release edit packs --notes "Metadata packs from $built"
          else
            gh release create packs \
              --title "Metadata packs" \
              --notes "Metadata packs from $built"
          fi
          gh release upload packs dist/packs/* --clobber
```

- [ ] **Step 2: Validate the YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/metadata-packs.yml')); print('ok')"`
Expected: `ok`. If `yaml` is not installed, run `pip install pyyaml` first. This step adds no dependency to the project, it is just the local check.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/metadata-packs.yml
git commit -m "ci(packs): workflow que constroi e publica os metadata packs"
```

---

### Task 12: A real verification, the SNES pack

**Files:** no new file, this task is measurement.

The design spec cites numbers measured in the PoC against the SNES DAT: 4268 dumps collapsing into 2415 canonical games, 86.8% cover coverage on libretro-thumbnails and 75.3% synopsis via OpenVGDB. This task confirms that the builder reproduces the order of magnitude of those numbers. If it does not, the problem is `canon` or the parser, and the slice is not ready.

The libretro-database DATs are republished every month, so the exact number may have moved since the PoC. The acceptable range is 2300 to 2550 games. Outside that, stop and investigate before moving on.

- [ ] **Step 1: Build only the SNES pack**

Run:
```bash
python3 tool/build_metadata_pack.py \
  --out /tmp/packs-verify \
  --built 2026-09-10 \
  --only nintendo_super_nintendo_entertainment_system
```
Expected: something like `OpenVGDB: 33448 CRCs`, then `Nintendo - Super Nintendo Entertainment System` and a line `  2415 games, 2152 with cover, 1819 with synopsis`. Write down the three numbers.

- [ ] **Step 2: Check the numbers against the PoC**

Run:
```bash
python3 - <<'PY'
import gzip, json
pack = json.load(gzip.open('/tmp/packs-verify/nintendo_super_nintendo_entertainment_system.json.gz'))
games = pack['games']
dumps = sum(len(g['dumps']) for g in games)
cover = sum(1 for g in games if g.get('cover'))
syn = sum(1 for g in games if g.get('synopsis'))
reg = sum(1 for g in games for d in g['dumps'] if d.get('region'))
print('games', len(games))
print('dumps', dumps)
print('cover %.1f%%' % (100 * cover / len(games)))
print('synopsis %.1f%%' % (100 * syn / len(games)))
print('region %.1f%% of dumps' % (100 * reg / dumps))
assert 2300 <= len(games) <= 2550, 'collapse out of the PoC range'
assert dumps > 4000, 'parser lost dumps'
assert cover / len(games) > 0.80, 'cover coverage dropped'
assert syn / len(games) > 0.65, 'synopsis coverage dropped'
# On the SNES DAT 293 of the 4268 blocks declare no region, so 93.1% have one.
# Below 85% the REGION_RE stopped matching.
assert reg / dumps > 0.85, 'region vanished from the parser'
print('ok')
PY
```
Expected: the five number lines and `ok` at the end.

- [ ] **Step 3: Sanity-check one enriched game record**

Run:
```bash
python3 - <<'PY'
import gzip, json
pack = json.load(gzip.open('/tmp/packs-verify/nintendo_super_nintendo_entertainment_system.json.gz'))
game = next(g for g in pack['games'] if g.get('cover') and g['dumps'])
print(json.dumps(game, ensure_ascii=False, indent=2)[:800])
assert game['id'].startswith('nintendo_super_nintendo_entertainment_system/')
assert game['title']
assert all(len(d['crc']) == 8 for d in game['dumps'])
assert game['cover'].startswith('https://raw.githubusercontent.com/libretro-thumbnails/')
print('ok')
PY
```
Expected: a game record's JSON with title, dumps and cover, then `ok`.

- [ ] **Step 4: Check the file size**

Run: `ls -lh /tmp/packs-verify/`
Expected: the `.json.gz` around 0.5 MB, which is what the real SNES build produced (469K compressed, 2.0 MB raw). Above 3 MB means an overly long synopsis got in without truncation, and it is worth truncating the synopsis at 1200 characters in `enrich_from_openvgdb` before moving on. For reference, the longest SNES synopsis is 2418 characters and the average is 257, so truncation is not necessary in this pack.

- [ ] **Step 5: Run the whole suite on both sides**

Run: `flutter test && (cd tool && python3 -m unittest discover -s . -p 'test_*.py')`
Expected: PASS on both.

- [ ] **Step 6: Commit the note with the numbers**

Add to the end of section 4.4 of `docs/stremio-de-jogos-design.md` a paragraph with the numbers you measured in this task, in the format: "Build of <date>: the SNES pack came out with N games from M dumps, X% with cover and Y% with synopsis."

```bash
git add docs/stremio-de-jogos-design.md
git commit -m "docs: numeros medidos da primeira build de metadata pack"
```

---

## What this slice does not do

Explicitly out of scope for slice 1, each item with its owning slice:

- Matching the pack against a remote source listing, the matcher tiers and CRC32 over HTTP Range: slice 2.
- Swapping the files grid for a games grid, an availability badge and a detail screen: slice 3.
- Accounts screen, token migration to secure storage and the RTS extended format: slice 4.
- `SourceResolver` and `HttpResolver`: slice 5.
- `DebridClient` and Real-Debrid: slice 6.

Three format decisions worth writing down, so slice 2 does not treat them as an oversight:

- **`norm` and `canon` do not exist in Dart.** They live only in the Python builder, and the app never runs them: the pack already arrives with the canonical title ready. Slice 2 needs runtime normalization to compare the remote file name against the dump name, so it will reimplement these two functions in Dart, not inherit them. The two versions need to agree case by case, and the `NormTest` and `DisplayTitleTest` fixtures in this plan serve as the base for the pair of tests.
- **The md5 is discarded on purpose.** The DAT carries md5 on every `rom` line, and `ROM_RE` even captures it, but only so the sha1 group lands in the right position. None of the three identity axes in the spec use md5: name matching uses no hash, the post-download check uses CRC32 and the tie-break in section 5.7 does too. A third hash per dump would fatten the pack with no buyer.
- **The `serial` is not normalized.** `crc` and `sha1` are uppercased on both sides, in Python and in `PackDump.fromJson`, because they are hexadecimal and the comparison must be stable. The `serial` is a manufacturer catalog string, with uppercase and hyphens that are part of the value (`SLPS-01204`, `SHVC-AY2J-JPN`), and it goes to the pack exactly as the DAT emits it. Whoever compares serial in slice 2 compares literally.

At the end of this slice nothing changes on screen: the app gains the ability to fetch and store the packs, and no screen consumes them yet. This is intentional. Slice 3 is the first one that shows up for the user.
