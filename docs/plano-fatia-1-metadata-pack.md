# Fatia 1: Metadata Pack, plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir e publicar um pacote de metadados por console (título canônico, dumps com CRC/SHA1/serial/região, capa, sinopse, gênero, ano) e fazer o app baixar, cachear e resolver esse pacote para os consoles do catálogo do usuário, sem login e sem servidor próprio.

**Architecture:** Um script Python em `tool/` roda no GitHub Actions, lê os DATs do libretro-database (No-Intro e Redump), colapsa os dumps em jogos canônicos, enriquece com os side files de `metadat/` e com o OpenVGDB, confere a existência da capa no libretro-thumbnails e publica um `<pack>.json.gz` por sistema mais um `index.json` numa release de tag fixa `packs`. No lado Flutter, `MetadataPackService` baixa sob demanda, descompacta com `gzip` do `dart:io`, grava em `getApplicationSupportDirectory()/packs/` e serve do disco nas próximas aberturas; `PackIndex.resolve` liga o id/nome arbitrário do console do usuário ao id do pacote.

**Tech Stack:** Python 3 stdlib (`urllib.request`, `sqlite3`, `gzip`, `json`, `re`, `unicodedata`, `difflib`, `unittest`), GitHub Actions, Dart/Flutter com Riverpod, `dart:io` `gzip`, `flutter_test`.

---

## Contexto que o implementador precisa

**O que já existe no repositório e não pode quebrar:**

- `lib/services/catalog_service.dart` carrega `consoles.json` e deriva o id do console do nome com `_nameToId` (linha 59): minúsculas, tudo que não é `[a-z0-9]` vira `_`, `_` das pontas some. O id do console é arbitrário e vem do usuário, então o pacote nunca pode assumir que o id do console é igual ao id do pacote. Daí o `index.json` com aliases.
- `tool/build_gametdb_boxarts.py` e `tool/build_xbox360_boxarts.py` são o precedente para scripts de build: Python 3, só stdlib, docstring de módulo explicando a fonte, `def main()`, sem framework de teste. Este plano mantém stdlib e adiciona `unittest`, que também é stdlib.
- Os testes em `test/` usam `flutter_test` puro, sem mockito. Injeção de dependência é feita por parâmetro de construtor. Ver `test/catalog_add_console_test.dart`.
- `assets/catalog/` é git-ignored. Nada deste plano escreve lá.

**Decisões de formato travadas neste plano:**

- Tag da release: `packs`, fixa, atualizada no lugar. A URL de download fica estável e o app não precisa chamar a API do GitHub. A data da build vive no campo `built` do JSON. Isto é um desvio consciente da seção 4.4 do spec de design, que sugeria `packs-YYYY-MM-DD`.
- Nome do arquivo do pacote: `<pack>.json.gz`, onde `<pack>` é o nome do sistema libretro passado pelo mesmo normalizador do `_nameToId`. Exemplo: `Nintendo - Super Nintendo Entertainment System` vira `nintendo_super_nintendo_entertainment_system`.
- `id` do jogo dentro do pacote: `<pack>/<slug do título canônico>`, com sufixo `-2`, `-3` e assim por diante em colisão, na ordem em que aparecem no DAT.
- O pacote guarda a URL da capa, nunca o binário da imagem.

**A tabela dos 24 sistemas** está no Task 6 e é a única fonte de verdade sobre quais DATs baixar, qual repositório de thumbnails usar e quais aliases cada pacote aceita. O Nintendo Switch não tem pacote de propósito: ele cai no MODO FONTE descrito no spec de UI.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
| --- | --- |
| `lib/models/metadata_pack_model.dart` | `PackDump`, `PackGame`, `MetadataPack`. Só dados e serialização. |
| `lib/models/pack_index_model.dart` | `PackIndexEntry`, `PackIndex`, `PackTarget`. A regra de resolução console para pacote mora aqui, pura e testável. |
| `lib/services/metadata_pack_service.dart` | Cache em disco, download, descompressão. Recebe `Directory` e a função de fetch por construtor. |
| `lib/providers/metadata_pack_provider.dart` | Fiação Riverpod. Fino de propósito. |
| `tool/build_metadata_pack.py` | O builder inteiro: parse, colapso, enriquecimento, saída. |
| `tool/test_build_metadata_pack.py` | `unittest` do builder, sem rede. |
| `.github/workflows/metadata-packs.yml` | Roda o builder e publica a release. |
| `test/metadata_pack_model_test.dart` | Testes do Task 1. |
| `test/pack_index_model_test.dart` | Testes do Task 2. |
| `test/metadata_pack_service_test.dart` | Testes dos Tasks 3 e 4. |
| `test/metadata_pack_provider_test.dart` | Teste do Task 5. |

---

### Task 1: Modelo do pacote

**Files:**
- Create: `lib/models/metadata_pack_model.dart`
- Test: `test/metadata_pack_model_test.dart`

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/metadata_pack_model_test.dart`:

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
      "id": "nintendo_super_nintendo_entertainment_system/chrono-trigger",
      "title": "Chrono Trigger",
      "dumps": [
        {"name": "Chrono Trigger (USA)", "crc": "2d206bf7", "sha1": "abc", "serial": null, "region": "USA"},
        {"name": "Chrono Trigger (Japan)", "crc": "1f2e3d4c"}
      ],
      "cover": "https://example.invalid/cover.png",
      "synopsis": "Um RPG.",
      "genre": "Role-Playing",
      "developer": "Square",
      "publisher": "Square",
      "year": 1995
    },
    {
      "id": "nintendo_super_nintendo_entertainment_system/sem-nada",
      "title": "Sem Nada",
      "dumps": []
    }
  ]
}
''';

  test('decode lê o pacote inteiro', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.pack, 'nintendo_super_nintendo_entertainment_system');
    expect(pack.system, 'Nintendo - Super Nintendo Entertainment System');
    expect(pack.built, '2026-09-10');
    expect(pack.games.length, 2);
  });

  test('CRC e SHA1 são normalizados para maiúsculas', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.crc, '2D206BF7');
    expect(pack.games.first.dumps.first.sha1, 'ABC');
    expect(pack.games.first.dumps[1].sha1, isNull);
  });

  test('region é lida como veio e é opcional', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.region, 'USA');
    expect(pack.games.first.dumps[1].region, isNull);
  });

  test('campos opcionais ausentes viram null e dumps vazio é permitido', () {
    final pack = MetadataPack.decode(sample);
    final game = pack.games[1];
    expect(game.cover, isNull);
    expect(game.synopsis, isNull);
    expect(game.year, isNull);
    expect(game.dumps, isEmpty);
  });

  test('toJson omite os nulos e sobrevive ao round trip', () {
    final pack = MetadataPack.decode(sample);
    final round = MetadataPack.decode(jsonEncode(pack.toJson()));
    expect(round.games[1].toJson().containsKey('cover'), isFalse);
    expect(round.games.first.dumps.first.crc, '2D206BF7');
    expect(round.games.first.year, 1995);
    expect(round.games.length, 2);
  });

  test('byCrc indexa todos os dumps do pacote', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.byCrc['2D206BF7']?.title, 'Chrono Trigger');
    expect(pack.byCrc['1F2E3D4C']?.title, 'Chrono Trigger');
    expect(pack.byCrc['DEADBEEF'], isNull);
  });
}
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `flutter test test/metadata_pack_model_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/models/metadata_pack_model.dart'`.

- [ ] **Step 3: Escrever o modelo**

Crie `lib/models/metadata_pack_model.dart`:

```dart
import 'dart:convert';

/// Um dump concreto de um jogo, como o DAT do No-Intro ou do Redump descreve.
/// [name] é o nome do jogo no DAT, sem extensão, com as tags de região e
/// revisão preservadas, porque é ele que o matcher compara com o nome do
/// arquivo remoto.
///
/// [crc] e [sha1] são normalizados para maiúsculas, porque são hexadecimais e a
/// comparação precisa ser estável entre o DAT e o que o app calcula. O [serial]
/// não é: ele é uma string de catálogo do fabricante, com maiúsculas e hifens
/// que fazem parte do valor, e é gravado exatamente como o DAT emite.
/// [region] é a região declarada no DAT, quando existe. Nem todo bloco traz
/// uma: no SNES 293 dos 4268 blocos não têm, no GameCube 33 de 2268. Por isso é
/// opcional. Ela existe para a regra de região preferida do download em lote e
/// para o cartão de detalhe mostrar "(USA)" sem reparsear o nome em runtime.
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

/// Um jogo canônico: um título, várias versões.
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

/// O pacote de um console inteiro.
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

  /// CRC32 em maiúsculas para o jogo dono daquele dump. Construído sob demanda
  /// e guardado, porque um pacote grande tem dezenas de milhares de dumps.
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `flutter test test/metadata_pack_model_test.dart`
Expected: PASS, 6 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/models/metadata_pack_model.dart test/metadata_pack_model_test.dart
git commit -m "feat(packs): modelo do metadata pack"
```

---

### Task 2: Índice de pacotes e a regra de resolução

**Files:**
- Create: `lib/models/pack_index_model.dart`
- Test: `test/pack_index_model_test.dart`

O `index.json` é o que liga o console do usuário ao pacote. O usuário pode chamar o console dele de "Super Nintendo", "SNES" ou "snes_usa_set", e o pacote se chama `nintendo_super_nintendo_entertainment_system`. A resolução tenta, nesta ordem: id do console igual ao id do pacote, nome do console normalizado igual ao id do pacote, id ou nome batendo com algum alias. A ordem importa: um alias nunca ganha de um `pack` exato.

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/pack_index_model_test.dart`:

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

  test('decode lê as entradas', () {
    final index = PackIndex.decode(sample);
    expect(index.built, '2026-09-10');
    expect(index.packs.length, 2);
    expect(index.packs.first.games, 2415);
  });

  test('normalize segue a mesma regra do id de console do catálogo', () {
    expect(PackIndex.normalize('Nintendo - Super Nintendo Entertainment System'),
        'nintendo_super_nintendo_entertainment_system');
    expect(PackIndex.normalize('  PlayStation 1!! '), 'playstation_1');
  });

  test('resolve pelo id do pacote', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'nintendo_super_nintendo_entertainment_system', 'Qualquer Nome'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolve pelo nome do console normalizado', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'catalogo_do_fulano', 'Nintendo - Super Nintendo Entertainment System'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolve por alias, do id e do nome', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('snes', 'Meu Set'))?.pack,
        'nintendo_super_nintendo_entertainment_system');
    expect(index.resolve(const PackTarget('qualquer', 'PlayStation 1'))?.pack,
        'sony_playstation');
  });

  test('pack exato ganha de alias de outra entrada', () {
    const colliding = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "outro", "system": "Outro", "games": 1, "aliases": ["snes"]},
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []}
  ]
}
''';
    final index = PackIndex.decode(colliding);
    expect(index.resolve(const PackTarget('snes', 'Snes'))?.pack, 'snes');

    // A mesma asserção com a ordem das entradas invertida. A garantia vem de
    // resolve varrer todos os packs antes de olhar qualquer alias, não da
    // ordem em que o índice foi escrito, e este par prova isso.
    const reversed = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []},
    {"pack": "outro", "system": "Outro", "games": 1, "aliases": ["snes"]}
  ]
}
''';
    expect(
        PackIndex.decode(reversed).resolve(const PackTarget('snes', 'Snes'))?.pack,
        'snes');
  });

  test('console sem pacote devolve null', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('nintendo_switch', 'Nintendo Switch')),
        isNull);
  });

  test('PackTarget tem igualdade por valor, para servir de chave de family', () {
    expect(const PackTarget('a', 'b'), const PackTarget('a', 'b'));
    expect(const PackTarget('a', 'b').hashCode, const PackTarget('a', 'b').hashCode);
    expect(const PackTarget('a', 'b') == const PackTarget('a', 'c'), isFalse);
  });
}
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `flutter test test/pack_index_model_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/models/pack_index_model.dart'`.

- [ ] **Step 3: Escrever o modelo**

Crie `lib/models/pack_index_model.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Um console do catálogo do usuário, do jeito que ele existe no app: um id
/// arbitrário e um nome livre. É a chave do provider de pacote, então precisa
/// de igualdade por valor.
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

  /// Mesma regra do CatalogService._nameToId. Duplicada de propósito: este
  /// modelo não deve depender de um service.
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Acha o pacote do console. Id e nome do pacote ganham de alias, sempre.
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `flutter test test/pack_index_model_test.dart`
Expected: PASS, 8 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/models/pack_index_model.dart test/pack_index_model_test.dart
git commit -m "feat(packs): indice de pacotes e resolucao console para pacote"
```

---

### Task 3: Serviço, metade do cache em disco

**Files:**
- Create: `lib/services/metadata_pack_service.dart`
- Test: `test/metadata_pack_service_test.dart`

O serviço recebe o diretório de cache e a função de fetch pelo construtor. Nenhum teste toca a rede nem o `path_provider`. Neste task só o lado do disco existe; o download entra no Task 4.

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/metadata_pack_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/metadata_pack_service.dart';

const packJson = '''
{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System",
 "built":"2026-09-10","games":[{"id":"snes/chrono-trigger","title":"Chrono Trigger",
 "dumps":[{"name":"Chrono Trigger (USA)","crc":"2d206bf7"}]}]}
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
        fetch: (uri) async => throw StateError('rede proibida neste teste'),
      );

  test('readCached devolve null quando não tem nada em disco', () async {
    expect(await service().readCached('snes'), isNull);
  });

  test('writeCache grava e readCached lê de volta', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    final pack = await svc.readCached('snes');
    expect(pack, isNotNull);
    expect(pack!.games.single.title, 'Chrono Trigger');
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('writeCache cria o diretório se ele não existir', () async {
    final nested = Directory(p.join(tmp.path, 'a', 'b'));
    final svc = MetadataPackService(
        cacheDir: nested, fetch: (uri) async => throw StateError('nao'));
    await svc.writeCache('snes', packJson);
    expect(await File(p.join(nested.path, 'snes.json')).exists(), isTrue);
  });

  test('readCached devolve null e apaga o arquivo quando o JSON está corrompido',
      () async {
    final svc = service();
    final file = File(p.join(tmp.path, 'snes.json'));
    await file.create(recursive: true);
    await file.writeAsString('{ isso nao e json');
    expect(await svc.readCached('snes'), isNull);
    expect(await file.exists(), isFalse);
  });

  test('cachedPacks lista os ids que estão em disco', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.writeCache('nes', packJson);
    final ids = await svc.cachedPacks();
    expect(ids..sort(), ['nes', 'snes']);
  });

  test('evict apaga o pacote do disco', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.evict('snes');
    expect(await svc.readCached('snes'), isNull);
    expect(await svc.cachedPacks(), isEmpty);
  });

  test('readCachedIndex e writeCacheIndex usam index.json', () async {
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

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/services/metadata_pack_service.dart'`.

- [ ] **Step 3: Escrever o serviço, só o lado do disco**

Crie `lib/services/metadata_pack_service.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

typedef PackFetch = Future<List<int>> Function(Uri uri);

/// Baixa, descompacta e cacheia os metadata packs. Recebe o diretório e a
/// função de rede por construtor para os testes rodarem sem disco de usuário
/// e sem rede.
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
      debugPrint('Pacote $packId corrompido em disco, descartando: $e');
      await file.delete();
      return null;
    }
  }

  Future<PackIndex?> readCachedIndex() async {
    if (!await indexFile.exists()) return null;
    try {
      return PackIndex.decode(await indexFile.readAsString());
    } catch (e) {
      debugPrint('Indice de pacotes corrompido em disco, descartando: $e');
      await indexFile.delete();
      return null;
    }
  }

  /// Ids dos pacotes em disco. O index.json não conta.
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: PASS, 7 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/metadata_pack_service.dart test/metadata_pack_service_test.dart
git commit -m "feat(packs): cache em disco dos metadata packs"
```

---

### Task 4: Serviço, metade do download

**Files:**
- Modify: `lib/services/metadata_pack_service.dart`
- Test: `test/metadata_pack_service_test.dart`

A descompressão usa o `gzip` do `dart:io`, que é stdlib e não depende da API do pacote `archive`. A política de carga é cache primeiro; se não tem cache, baixa; se o download falha, tenta o cache de novo antes de desistir, para o app continuar funcionando offline.

- [ ] **Step 1: Escrever os testes que falham**

Adicione ao final de `test/metadata_pack_service_test.dart`, dentro do `main()`, depois do último `test(...)` existente:

```dart
  List<int> gz(String s) => gzip.encode(utf8.encode(s));

  test('packUri e indexUri apontam para a release de tag fixa', () {
    final svc = service();
    expect(svc.packUri('snes').toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/snes.json.gz');
    expect(svc.indexUri().toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/index.json');
  });

  test('download descompacta, grava no cache e devolve o pacote', () async {
    final pedidos = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        pedidos.add(uri);
        return gz(packJson);
      },
    );
    final pack = await svc.download('snes');
    expect(pack.games.single.title, 'Chrono Trigger');
    expect(pedidos.single.path, endsWith('/packs/snes.json.gz'));
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('load usa o cache e não chama a rede', () async {
    var chamadas = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        chamadas++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes');
    expect(pack!.games.single.title, 'Chrono Trigger');
    expect(chamadas, 0);
  });

  test('load com forceRefresh vai na rede mesmo tendo cache', () async {
    var chamadas = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        chamadas++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    await svc.load('snes', forceRefresh: true);
    expect(chamadas, 1);
  });

  test('load cai de volta no cache quando a rede falha', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('sem rede'),
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes', forceRefresh: true);
    expect(pack!.games.single.title, 'Chrono Trigger');
  });

  test('load devolve null quando não tem rede nem cache', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('sem rede'),
    );
    expect(await svc.load('snes'), isNull);
  });

  test('loadIndex baixa o index.json sem gzip e cacheia', () async {
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":["snes"]}]}';
    final pedidos = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        pedidos.add(uri);
        return utf8.encode(indexJson);
      },
    );
    final index = await svc.loadIndex(forceRefresh: true);
    expect(index!.packs.single.pack, 'snes');
    expect(pedidos.single.path, endsWith('/packs/index.json'));
    expect((await svc.readCachedIndex())!.built, '2026-09-10');
  });
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: FAIL, `The method 'download' isn't defined for the class 'MetadataPackService'`.

- [ ] **Step 3: Adicionar o download ao serviço**

Em `lib/services/metadata_pack_service.dart`, troque os imports do topo por:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
```

Logo depois de `MetadataPackService({required this.cacheDir, required this.fetch});`, adicione:

```dart
  /// Release de tag fixa, atualizada no lugar pelo workflow metadata-packs.
  /// Tag fixa significa URL estável e zero chamadas à API do GitHub no app.
  static const releaseBase =
      'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs';

  /// Fetch padrão de produção. Segue redirect, que a release do GitHub sempre
  /// devolve.
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

  /// Cache primeiro, rede depois, cache de novo se a rede falhar. Null só
  /// quando não existe nem uma coisa nem a outra.
  Future<MetadataPack?> load(String packId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCached(packId);
      if (cached != null) return cached;
    }
    try {
      return await download(packId);
    } catch (e) {
      debugPrint('Falha ao baixar o pacote $packId: $e');
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
      debugPrint('Falha ao baixar o indice de pacotes: $e');
      return readCachedIndex();
    }
  }
```

- [ ] **Step 4: Rodar os testes e ver passar**

Run: `flutter test test/metadata_pack_service_test.dart`
Expected: PASS, 14 testes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/metadata_pack_service.dart test/metadata_pack_service_test.dart
git commit -m "feat(packs): download e descompressao dos metadata packs"
```

---

### Task 5: Providers Riverpod

**Files:**
- Create: `lib/providers/metadata_pack_provider.dart`
- Test: `test/metadata_pack_provider_test.dart`

Os providers são finos de propósito: toda a decisão está no `PackIndex.resolve` do Task 2 e no `MetadataPackService` dos Tasks 3 e 4. O teste usa `ProviderContainer` com override do service, que é onde a rede e o `path_provider` entrariam.

- [ ] **Step 1: Escrever o teste que falha**

Crie `test/metadata_pack_provider_test.dart`:

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
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/chrono-trigger","title":"Chrono Trigger","dumps":[]}]}';

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

  test('packIndexProvider entrega o índice baixado', () async {
    final container = containerWith((uri) async => utf8.encode(indexJson));
    addTearDown(container.dispose);
    final index = await container.read(packIndexProvider.future);
    expect(index!.packs.single.pack, 'snes');
  });

  test('metadataPackProvider resolve por alias e baixa o pacote', () async {
    final container = containerWith((uri) async {
      if (uri.path.endsWith('index.json')) return utf8.encode(indexJson);
      return gzip.encode(utf8.encode(packJson));
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('super_nintendo', 'Super Nintendo'))
            .future);
    expect(pack!.games.single.title, 'Chrono Trigger');
  });

  test('console sem pacote no índice devolve null sem tentar baixar', () async {
    final pedidos = <Uri>[];
    final container = containerWith((uri) async {
      pedidos.add(uri);
      return utf8.encode(indexJson);
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('nintendo_switch', 'Nintendo Switch'))
            .future);
    expect(pack, isNull);
    expect(pedidos.every((u) => u.path.endsWith('index.json')), isTrue);
  });
}
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `flutter test test/metadata_pack_provider_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:roms_downloader/providers/metadata_pack_provider.dart'`.

- [ ] **Step 3: Escrever os providers**

Crie `lib/providers/metadata_pack_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

/// O serviço real, apontando para `<support>/packs`. Os testes sobrescrevem
/// este provider com um serviço de diretório temporário e fetch falso.
final metadataPackServiceProvider =
    FutureProvider<MetadataPackService>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  return MetadataPackService(
    cacheDir: Directory(p.join(supportDir.path, 'packs')),
    fetch: MetadataPackService.httpFetch,
  );
});

/// O index.json da release. Null quando não deu para baixar e não tem cache.
final packIndexProvider = FutureProvider<PackIndex?>((ref) async {
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.loadIndex();
});

/// O pacote de um console do catálogo. Null quando o console não tem pacote,
/// que é o caso do Nintendo Switch e de qualquer console adicionado à mão que
/// não bata com nenhum alias.
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `flutter test test/metadata_pack_provider_test.dart`
Expected: PASS, 3 testes.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `flutter test`
Expected: PASS, com todos os testes que já existiam intactos. Esta fatia adiciona 31 testes Dart: 6 no Task 1, 8 no Task 2, 7 no Task 3, 7 no Task 4 e 3 aqui.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/metadata_pack_provider.dart test/metadata_pack_provider_test.dart
git commit -m "feat(packs): providers do metadata pack"
```

---

### Task 6: Builder, parser de DAT

**Files:**
- Create: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

O libretro-database publica dois formatos. O DAT principal (`metadat/no-intro/*.dat` e `metadat/redump/*.dat`) traz `name`, `region` e uma ou mais linhas `rom` com `crc`, `md5` e `sha1`. Os side files (`metadat/genre/*.dat`, `metadat/developer/*.dat` e companhia) trazem `comment`, o campo em questão e um `rom ( crc ... )` que é a chave de ligação.

Dois fatos verificados que mudam o desenho:

- Os side files só existem para sistemas No-Intro. `metadat/genre/Sony - PlayStation.dat` responde 404. Para os sistemas Redump o enriquecimento vem só do OpenVGDB, e o builder precisa tratar 404 como caso normal.
- No Redump o `serial` vem no próprio bloco `game`, então não depende de side file. No No-Intro ele vem do `metadat/serial/*.dat`.
- Jogos de disco Redump têm várias linhas `rom`, uma por faixa. O builder guarda a primeira, que é a faixa de dados. O CRC de faixa não casa com um `.chd` baixado, e isso é uma limitação conhecida: a verificação por CRC é útil de verdade nos sistemas de cartucho.

- [ ] **Step 1: Escrever o teste que falha**

Crie `tool/test_build_metadata_pack.py`:

```python
#!/usr/bin/env python3
"""Testes do builder de metadata packs. Nada aqui toca a rede."""
import unittest

import build_metadata_pack as b

NO_INTRO_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
\tdescription "Nintendo - Super Nintendo Entertainment System"
)

game (
\tname "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
\tregion "Japan"
\trom ( name "'96 Zenkoku Koukou Soccer Senshuken (Japan).sfc" size 1572864 crc 05FBB855 md5 3369347F7663B133CE445C15200A5AFA sha1 005CCD8362DC41491F89F31FC9326A6688300E0C )
)
game (
\tname "Chrono Trigger (USA)"
\tregion "USA"
\trom ( name "Chrono Trigger (USA).sfc" size 4194304 crc 2D206BF7 md5 A2BC447961E52FD2227BAED164F729DC sha1 DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50 )
)
game (
\tname "Sem Hash (Japan)"
\tregion "Japan"
)
'''

REDUMP_DAT = '''clrmamepro (
\tname "Sony - PlayStation"
)

game (
\tname "'98 Koushien (Japan)"
\tregion "Japan"
\tserial "SLPS-01204"
\trom ( name "'98 Koushien (Japan).bin" size 583415952 crc 8ACD8FB1 md5 39A936EA7521157838D4E67B24F62F15 sha1 782C50827BF4CF8FE5530B64B188A2D43C75B0E0 serial "SLPS-01204" )
)
game (
\tname "'99 Koushien (Japan)"
\tregion "Japan"
\tserial "SLPS-02110"
\trom ( name "'99 Koushien (Japan) (Track 01).bin" size 314812848 crc 1D91CBAB md5 7BDC7092AEF04C6BEC7E78CDFE3D9A81 sha1 C1B7929C137E885569D30803664B26E496F32BB6 serial "SLPS-02110" )
\trom ( name "'99 Koushien (Japan) (Track 02).bin" size 12345 crc AAAAAAAA md5 BB sha1 CC serial "SLPS-02110" )
)
'''

GENRE_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
)

game (
\tcomment "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
\tgenre "Sports"
\trom ( crc 05FBB855 )
)
game (
\tcomment "Chrono Trigger (USA)"
\tgenre "Role-Playing"
\trom ( crc 2d206bf7 )
)
'''

SERIAL_DAT = '''game (
\tcomment "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
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
        self.assertEqual(entries[1]["name"], "Chrono Trigger (USA)")

    def test_reads_the_first_rom_hashes_uppercased(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["crc"], "2D206BF7")
        self.assertEqual(entries[1]["sha1"], "DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50")

    def test_game_without_rom_line_keeps_null_hashes(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[2]["name"], "Sem Hash (Japan)")
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
        # Nem todo bloco declara região. No DAT real do SNES são 293 de 4268,
        # no do GameCube 33 de 2268, então a ausência é normal e vira None.
        sem = b.parse_dat('game (\n\tname "Sem Regiao"\n)\n')
        self.assertIsNone(sem[0]["region"])


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
                self.assertNotIn(alias, seen, f"{alias} repetido em {s['system']}")
                seen[alias] = s["system"]

    def test_every_system_declares_dat_group_and_thumbs(self):
        for s in b.SYSTEMS:
            self.assertIn(s["group"], ("no-intro", "redump"))
            self.assertTrue(s["thumbs"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py' -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'build_metadata_pack'`.

- [ ] **Step 3: Escrever o parser e a tabela de sistemas**

Crie `tool/build_metadata_pack.py`:

```python
#!/usr/bin/env python3
"""Builds one metadata pack per console for the app's "Stremio de jogos" grid.

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

# Os side files por campo só existem para sistemas No-Intro. Para Redump o
# builder recebe 404 e segue em frente com o OpenVGDB.
SIDE_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "releaseyear": "releaseyear",
    "franchise": "franchise",
    "esrb": "esrb_rating",
    "serial": "serial",
}

# system: nome do sistema no libretro-database, e também o que vira o pack id.
# group: qual pasta de metadat tem o DAT principal.
# thumbs: repositório do libretro-thumbnails, que nem sempre casa com o nome
#         do sistema (Wii U Digital usa o repo do Wii U).
# aliases: como o console pode se chamar no catálogo do usuário.
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
# O md5 é capturado só para o grupo do sha1 cair na posição certa. Ele não vai
# para o pacote: nenhum dos três eixos de identidade da fatia 2 usa md5, e
# guardar um hash a mais por dump inflaria o pacote sem comprador.
ROM_RE = re.compile(
    r'rom \( name "([^"]+)"(?:\s+size \d+)?\s+crc (\w+)'
    r"(?:\s+md5 (\w+))?(?:\s+sha1 (\w+))?"
)
CRC_RE = re.compile(r"crc (\w+)")


def normalize(value):
    """Mesma regra do CatalogService._nameToId no app."""
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.lower()))


def parse_dat(text):
    """DAT principal do No-Intro ou do Redump para uma lista de dumps.

    Só a primeira linha rom de cada bloco entra: em jogos de disco as demais
    são faixas de áudio, cujo CRC não serve para identificar o arquivo que o
    usuário baixa.

    O crc e o sha1 sobem para maiúsculas porque são hexadecimais e a comparação
    precisa ser estável. O serial não: ele é uma string de catálogo do
    fabricante e vai para o pacote exatamente como o DAT emite.
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
    """Side file por campo para um mapa CRC32 em maiúsculas para valor."""
    field_re = re.compile(field + r' "([^"]+)"')
    out = {}
    for block in GAME_RE.findall(text):
        crc = CRC_RE.search(block)
        value = field_re.search(block)
        if crc and value:
            out[crc.group(1).upper()] = value.group(1)
    return out


def main():
    raise SystemExit("CLI ainda nao implementada, ver Task 10")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py' -v`
Expected: PASS, 15 testes.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): parser de DAT e tabela dos 24 sistemas"
```

---

### Task 7: Builder, colapso em jogos canônicos

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Aqui mora a razão de o pacote existir: o DAT do SNES tem 4268 dumps e o usuário quer ver 2415 jogos. `canon` joga fora região, revisão, idioma e tags e devolve o título do jogo; dumps que compartilham o mesmo `canon` viram um `PackGame`. `norm` e `canon` são o porte do que a PoC mediu, com uma correção: na PoC a troca do artigo final rodava depois de `norm`, que já tinha comido a vírgula de "Legend of Zelda, The", então nunca acontecia. Aqui ela roda no nome cru, dentro de `display_title`.

- [ ] **Step 1: Escrever o teste que falha**

Adicione a `tool/test_build_metadata_pack.py`, antes do bloco `if __name__`:

```python
class NormTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(b.norm("Chrono Trigger (USA)"), "chrono trigger (usa)")

    def test_expands_ampersand(self):
        self.assertEqual(b.norm("Dig & Spike"), "dig and spike")

    def test_drops_accents(self):
        self.assertEqual(b.norm("Pokémon Rojo"), "pokemon rojo")

    def test_strips_rom_extensions(self):
        self.assertEqual(b.norm("Chrono Trigger (USA).sfc"), "chrono trigger (usa)")
        self.assertEqual(b.norm("Chrono Trigger (USA).zip"), "chrono trigger (usa)")


class CanonTest(unittest.TestCase):
    def test_drops_region_and_revision_tags(self):
        self.assertEqual(b.canon("Chrono Trigger (USA) (Rev 1)"), "chrono trigger")
        self.assertEqual(b.canon("Chrono Trigger (Japan) [T+Eng]"), "chrono trigger")

    def test_moves_the_trailing_article_to_the_front(self):
        self.assertEqual(b.canon("Legend of Zelda, The (USA)"), "the legend of zelda")

    def test_different_regions_share_one_canon(self):
        self.assertEqual(
            b.canon("Super Mario World (USA)"), b.canon("Super Mario World (Europe)")
        )


class DisplayTitleTest(unittest.TestCase):
    def test_keeps_the_original_casing(self):
        self.assertEqual(b.display_title("Chrono Trigger (USA)"), "Chrono Trigger")

    def test_moves_the_article_without_lowercasing_the_rest(self):
        self.assertEqual(
            b.display_title("Legend of Zelda, The (USA)"), "The Legend of Zelda"
        )

    def test_keeps_accents_and_punctuation(self):
        self.assertEqual(b.display_title("Pokémon Rojo (Spain).gb"), "Pokémon Rojo")

    def test_name_that_is_only_tags_becomes_empty(self):
        self.assertEqual(b.display_title("(USA)"), "")


class SlugTest(unittest.TestCase):
    def test_makes_a_url_safe_slug(self):
        self.assertEqual(b.slug("the legend of zelda"), "the-legend-of-zelda")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(b.slug("f-zero  ii!!"), "f-zero-ii")


class CollapseTest(unittest.TestCase):
    def setUp(self):
        self.entries = [
            {"name": "Chrono Trigger (USA)", "crc": "2D206BF7", "sha1": "A",
             "serial": None, "region": "USA"},
            {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C", "sha1": "B",
             "serial": None, "region": "Japan"},
            {"name": "Legend of Zelda, The (USA)", "crc": "AAAAAAAA", "sha1": None,
             "serial": None, "region": None},
        ]

    def test_dumps_of_the_same_game_collapse_into_one_entry(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(len(games), 2)
        self.assertEqual(len(games[0]["dumps"]), 2)

    def test_title_comes_from_the_first_dump_without_its_tags(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["title"], "Chrono Trigger")
        self.assertEqual(games[1]["title"], "The Legend of Zelda")

    def test_id_is_pack_slash_slug(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["id"], "snes/chrono-trigger")
        self.assertEqual(games[1]["id"], "snes/the-legend-of-zelda")

    def test_dump_order_is_the_dat_order(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(
            [d["name"] for d in games[0]["dumps"]],
            ["Chrono Trigger (USA)", "Chrono Trigger (Japan)"],
        )

    def test_hyphen_and_space_spellings_are_the_same_game(self):
        entries = [
            {"name": "Pac-Man (USA)", "crc": "1", "sha1": None, "serial": None},
            {"name": "Pac Man (Japan)", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "nes")
        self.assertEqual(len(games), 1)
        self.assertEqual(games[0]["id"], "nes/pac-man")

    def test_two_titles_with_the_same_slug_get_a_numeric_suffix(self):
        # Tags desbalanceadas sobrevivem ao canon, entao dois jogos de canon
        # diferente podem cair no mesmo slug. O sufixo garante id único.
        entries = [
            {"name": "Sonic (Beta", "crc": "1", "sha1": None, "serial": None},
            {"name": "Sonic Beta", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "md")
        self.assertEqual(len(games), 2)
        self.assertEqual(games[0]["id"], "md/sonic-beta")
        self.assertEqual(games[1]["id"], "md/sonic-beta-2")

    def test_region_travels_to_the_dump_and_is_omitted_when_absent(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["dumps"][0]["region"], "USA")
        self.assertEqual(games[0]["dumps"][1]["region"], "Japan")
        self.assertNotIn("region", games[1]["dumps"][0])

    def test_entries_without_a_canon_title_are_dropped(self):
        entries = [{"name": "(USA)", "crc": "1", "sha1": None, "serial": None}]
        self.assertEqual(b.collapse(entries, "nes"), [])
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'norm'`.

- [ ] **Step 3: Implementar norm, canon, slug e collapse**

Em `tool/build_metadata_pack.py`, logo depois de `def parse_side_dat(...)`, adicione:

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
    """Forma comparável do nome do arquivo: sem extensão, sem acento, sem
    pontuação, mas com as tags de região e revisão preservadas."""
    value = strip_ext(value)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(c for c in value if not unicodedata.combining(c))
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9()\[\]]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def display_title(dat_name):
    """Título de exibição a partir do nome do DAT: sem extensão, sem tags de
    região e revisão, com o artigo de volta na frente.

    A troca do artigo acontece aqui, no nome cru, e não depois de norm, porque
    norm come a vírgula que separa "Legend of Zelda" de "The".
    """
    value = TAG_RE.sub(" ", strip_ext(dat_name))
    value = re.sub(r"\s+", " ", value).strip().strip(",").strip()
    match = ARTICLE_RE.match(value)
    if match:
        value = f"{match.group(2)} {match.group(1)}"
    return value


def canon(value):
    """Título canônico do jogo, a chave de agrupamento: o título de exibição
    passado por norm."""
    return norm(display_title(value))


def slug(value):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", value.lower()))


def collapse(entries, pack_id):
    """Dumps do DAT para jogos canônicos, na ordem em que aparecem."""
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
                # O título vem do primeiro dump, que preserva a grafia e os
                # acentos do DAT. O canon serve só para agrupar e para o slug.
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 36 testes.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): colapso de dumps em jogos canonicos"
```

---

### Task 8: Builder, enriquecimento pelos side files

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Os side files chaveiam por CRC32 de um dump. Um jogo canônico tem vários dumps, então a regra é: o primeiro dump que tiver valor para o campo ganha. Isso favorece a região que aparece primeiro no DAT, que é a ordem alfabética, e é determinístico.

- [ ] **Step 1: Escrever o teste que falha**

Adicione a `tool/test_build_metadata_pack.py`, antes do bloco `if __name__`:

```python
class EnrichTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/chrono-trigger",
            "title": "Chrono Trigger",
            "dumps": [
                {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C"},
                {"name": "Chrono Trigger (USA)", "crc": "2D206BF7"},
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
        games[0]["dumps"][1]["serial"] = "JA-ESTAVA-LA"
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertEqual(games[0]["dumps"][1]["serial"], "JA-ESTAVA-LA")

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
            "franchise": {"2D206BF7": "Chrono"},
            "esrb": {"2D206BF7": "E"},
        })
        self.assertEqual(games[0]["franchise"], "Chrono")
        self.assertEqual(games[0]["esrb"], "E")
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'enrich_from_side'`.

- [ ] **Step 3: Implementar o enriquecimento**

Em `tool/build_metadata_pack.py`, logo depois de `def collapse(...)`, adicione:

```python
# Campo do side file para chave no JSON do jogo. O serial é o único que não
# descreve o jogo e sim o dump, então tem tratamento próprio.
GAME_FIELDS = {
    "genre": "genre",
    "developer": "developer",
    "publisher": "publisher",
    "franchise": "franchise",
    "esrb": "esrb",
}


def enrich_from_side(games, side_maps):
    """Preenche os campos do jogo a partir dos mapas CRC para valor.

    Um jogo tem vários dumps; o primeiro dump que tiver valor para o campo
    ganha, o que torna o resultado determinístico.
    """
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 43 testes.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): enriquecimento pelos side files do libretro-database"
```

---

### Task 9: Builder, capas e sinopse

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Duas fontes, com ordem de preferência. A capa preferida é a do libretro-thumbnails, porque a PoC mediu 86,8% de cobertura contra 75,6% do OpenVGDB e a união dá 89,6%. O OpenVGDB entra como reserva de capa e como única fonte de sinopse.

Dois detalhes verificados que o código precisa respeitar:

- O nome do arquivo no libretro-thumbnails é o nome do DAT com `&*/:` e outros caracteres proibidos trocados por `_`, mais `.png`. Exemplo real do repositório do SNES: `Advanced Dungeons _ Dragons - Eye of the Beholder (USA).png`.
- A árvore de `Named_Boxarts` cabe numa chamada só da API do GitHub, mesmo no PlayStation, que tem 9301 arquivos e não vem truncado.

A escolha da capa entre os dumps de um jogo segue prioridade de região: USA, World, Europe, Japan e depois qualquer um, para o usuário ver a capa que ele reconhece.

- [ ] **Step 1: Escrever o teste que falha**

Adicione a `tool/test_build_metadata_pack.py`, antes do bloco `if __name__`:

```python
import sqlite3


class ThumbNameTest(unittest.TestCase):
    def test_keeps_the_dat_name_and_adds_png(self):
        self.assertEqual(b.thumb_name("Chrono Trigger (USA)"), "Chrono Trigger (USA).png")

    def test_replaces_the_characters_libretro_forbids(self):
        self.assertEqual(
            b.thumb_name("Advanced Dungeons & Dragons - Eye of the Beholder (USA)"),
            "Advanced Dungeons _ Dragons - Eye of the Beholder (USA).png",
        )
        self.assertEqual(b.thumb_name("Ratchet: Deadlocked"), "Ratchet_ Deadlocked.png")


class RegionPriorityTest(unittest.TestCase):
    def test_usa_beats_japan(self):
        self.assertLess(
            b.region_rank("Chrono Trigger (USA)"), b.region_rank("Chrono Trigger (Japan)")
        )

    def test_world_beats_europe(self):
        self.assertLess(
            b.region_rank("Sonic (World)"), b.region_rank("Sonic (Europe)")
        )

    def test_unknown_region_goes_last(self):
        self.assertGreater(
            b.region_rank("Sonic (Korea)"), b.region_rank("Sonic (Japan)")
        )


class AttachCoversTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/chrono-trigger",
            "title": "Chrono Trigger",
            "dumps": [
                {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C"},
                {"name": "Chrono Trigger (USA)", "crc": "2D206BF7"},
            ],
        }]

    def test_picks_the_preferred_region_cover(self):
        games = self.games()
        available = {"Chrono Trigger (Japan).png", "Chrono Trigger (USA).png"}
        b.attach_thumbnail_covers(games, available, "Nintendo_-_Super_Nintendo_Entertainment_System")
        self.assertEqual(
            games[0]["cover"],
            "https://raw.githubusercontent.com/libretro-thumbnails/"
            "Nintendo_-_Super_Nintendo_Entertainment_System/master/Named_Boxarts/"
            "Chrono%20Trigger%20%28USA%29.png",
        )

    def test_falls_back_to_the_only_available_region(self):
        games = self.games()
        b.attach_thumbnail_covers(games, {"Chrono Trigger (Japan).png"}, "R")
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
            INSERT INTO RELEASES VALUES (1, 'Um RPG.', 'https://img/ct.jpg',
                'Square', 'Square', 'Role-Playing', 'Mar 11, 1995');
            INSERT INTO ROMs VALUES (2, 'AAAAAAAA');
            INSERT INTO RELEASES VALUES (2, NULL, NULL, NULL, NULL, NULL, NULL);
        ''')

    def test_index_is_keyed_by_uppercase_crc(self):
        index = b.openvgdb_index(self.conn)
        self.assertIn("2D206BF7", index)
        self.assertEqual(index["2D206BF7"]["synopsis"], "Um RPG.")

    def test_year_is_extracted_from_the_release_date(self):
        index = b.openvgdb_index(self.conn)
        self.assertEqual(index["2D206BF7"]["year"], 1995)

    def test_rows_without_any_useful_field_are_skipped(self):
        self.assertNotIn("AAAAAAAA", b.openvgdb_index(self.conn))

    def test_enrich_fills_only_what_is_missing(self):
        games = [{
            "id": "snes/chrono-trigger", "title": "Chrono Trigger",
            "genre": "RPG",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["genre"], "RPG")
        self.assertEqual(games[0]["synopsis"], "Um RPG.")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_openvgdb_cover_is_only_a_fallback(self):
        games = [{
            "id": "a", "title": "A", "cover": "https://libretro/x.png",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://libretro/x.png")

    def test_openvgdb_cover_is_used_when_there_is_none(self):
        games = [{
            "id": "a", "title": "A",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://img/ct.jpg")
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'thumb_name'`.

- [ ] **Step 3: Implementar capas e sinopse**

Em `tool/build_metadata_pack.py`, logo depois de `def enrich_from_side(...)`, adicione:

```python
# O libretro-thumbnails troca estes caracteres por "_" no nome do arquivo.
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
    """Escolhe a capa do libretro-thumbnails do dump de melhor região que
    realmente existe no repositório."""
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
    """CRC32 em maiúsculas para os campos úteis do OpenVGDB."""
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
    """Só preenche buraco. O libretro-database sempre ganha do OpenVGDB, que
    não tem licença declarada e é a fonte menos confiável das duas."""
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

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 57 testes.

- [ ] **Step 5: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): capas do libretro-thumbnails e sinopse do OpenVGDB"
```

---

### Task 10: Builder, rede, saída e CLI

**Files:**
- Modify: `tool/build_metadata_pack.py`
- Test: `tool/test_build_metadata_pack.py`

Agora a rede entra, mas isolada em três funções finas (`fetch_text`, `fetch_json`, `download_openvgdb`) para as partes testáveis continuarem puras. O que os testes cobrem aqui é a montagem do pacote e do índice, com uma função `fetch` injetada.

O gzip sai com `mtime=0` para que uma rebuild sem mudança de dados produza bytes idênticos, o que deixa óbvio no diff da release quando nada mudou.

- [ ] **Step 1: Escrever o teste que falha**

Adicione a `tool/test_build_metadata_pack.py`, antes do bloco `if __name__`:

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
        chrono = by_id["nintendo_super_nintendo_entertainment_system/chrono-trigger"]
        self.assertEqual(chrono["genre"], "Role-Playing")

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

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: FAIL, `AttributeError: module 'build_metadata_pack' has no attribute 'build_pack'`.

- [ ] **Step 3: Implementar montagem, saída e CLI**

Em `tool/build_metadata_pack.py`, logo depois de `def enrich_from_openvgdb(...)`, adicione:

```python
def build_pack(system, dat_text, side_texts, thumbs, openvgdb, built):
    """Junta tudo num documento de pacote pronto para serializar."""
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
    """JSON compacto em gzip determinístico: mtime zerado para que uma
    rebuild sem mudança produza bytes idênticos."""
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

Acrescente `import argparse`, `import tempfile` e `import zipfile` ao bloco de imports
do topo do arquivo, mantendo a ordem alfabética que já está lá.

Agora troque o `def main()` provisório do Task 6 por:

```python
def fetch_text(url, optional=False):
    """Baixa texto. Com optional=True um 404 vira None, que é o caso normal
    dos side files: eles só existem para os sistemas No-Intro."""
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
    """Nomes de arquivo em Named_Boxarts. A árvore de um diretório único cabe
    numa chamada; se vier truncada o builder devolve conjunto vazio em vez de
    inventar URL que não existe."""
    try:
        tree = fetch_json(THUMBS_API.format(repo=repo), token)
    except urllib.error.HTTPError as error:
        print(f"  thumbnails de {repo} indisponiveis: HTTP {error.code}", file=sys.stderr)
        return set()
    if tree.get("truncated"):
        print(f"  arvore de {repo} truncada, ignorando capas", file=sys.stderr)
        return set()
    return {entry["path"] for entry in tree.get("tree", [])}


def download_openvgdb(dest_dir):
    """Baixa e descompacta o openvgdb.sqlite, devolvendo a conexão."""
    zip_path = os.path.join(dest_dir, "openvgdb.zip")
    urllib.request.urlretrieve(OPENVGDB_URL, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(dest_dir)
    return sqlite3.connect(os.path.join(dest_dir, "openvgdb.sqlite"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="dist/packs", help="diretorio de saida")
    parser.add_argument("--built", required=True, help="data da build, YYYY-MM-DD")
    parser.add_argument("--only", action="append", default=[],
                        help="constroi so estes pack ids, repetivel")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    token = os.environ.get("GITHUB_TOKEN")
    selected = [s for s in SYSTEMS
                if not args.only or normalize(s["system"]) in args.only]
    if not selected:
        raise SystemExit(f"nenhum sistema casa com {args.only}")

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
            print(f"  {len(pack['games'])} jogos, {with_cover} com capa, "
                  f"{with_synopsis} com sinopse")
            path = os.path.join(args.out, f"{pack_id}.json.gz")
            with open(path, "wb") as out:
                out.write(pack_bytes(pack))
            packs.append(pack)
            aliases[pack_id] = system["aliases"]

        index = build_index(packs, aliases, args.built)
        with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as out:
            json.dump(index, out, ensure_ascii=False, indent=2)
        print(f"{len(packs)} pacotes em {args.out}")
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `cd tool && python3 -m unittest discover -s . -p 'test_*.py'`
Expected: PASS, 63 testes.

- [ ] **Step 5: Conferir que a CLI carrega**

Run: `python3 tool/build_metadata_pack.py --help`
Expected: o texto de ajuda com `--out`, `--built` e `--only`, sem traceback.

- [ ] **Step 6: Commit**

```bash
git add tool/build_metadata_pack.py tool/test_build_metadata_pack.py
git commit -m "feat(packs): montagem, saida gzip e CLI do builder"
```

---

### Task 11: Workflow que publica a release

**Files:**
- Create: `.github/workflows/metadata-packs.yml`

A tag é fixa, `packs`, e a release é atualizada no lugar. É isso que deixa a URL de download estável e permite o app baixar sem nunca chamar a API do GitHub. A data da build vive no `built` do JSON e no corpo da release.

- [ ] **Step 1: Escrever o workflow**

Crie `.github/workflows/metadata-packs.yml`:

```yaml
name: Metadata Packs

on:
  workflow_dispatch:
  schedule:
    # Todo dia 3 às 05:00 UTC, alguns dias depois do libretro-database
    # publicar os DATs do mês.
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
          test "$count" -eq 24 || { echo "esperava 24 pacotes, veio $count"; exit 1; }
          ls -lh dist/packs

      - name: Publish the packs release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          built=$(date -u +%Y-%m-%d)
          if gh release view packs >/dev/null 2>&1; then
            gh release edit packs --notes "Metadata packs de $built"
          else
            gh release create packs \
              --title "Metadata packs" \
              --notes "Metadata packs de $built"
          fi
          gh release upload packs dist/packs/* --clobber
```

- [ ] **Step 2: Validar o YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/metadata-packs.yml')); print('ok')"`
Expected: `ok`. Se o `yaml` não estiver instalado, rode `pip install pyyaml` primeiro. Este passo não adiciona dependência ao projeto, é só a checagem local.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/metadata-packs.yml
git commit -m "ci(packs): workflow que constroi e publica os metadata packs"
```

---

### Task 12: Verificação de verdade, o pacote do SNES

**Files:** nenhum arquivo novo, este task é medição.

O spec de design cita números medidos na PoC contra o DAT do SNES: 4268 dumps colapsando em 2415 jogos canônicos, 86,8% de cobertura de capa no libretro-thumbnails e 75,3% de sinopse via OpenVGDB. Este task confirma que o builder reproduz a ordem de grandeza desses números. Se não reproduzir, o problema é o `canon` ou o parser, e a fatia não está pronta.

Os DATs do libretro-database são republicados todo mês, então o número exato pode ter andado desde a PoC. A faixa aceitável é 2300 a 2550 jogos. Fora disso, pare e investigue antes de seguir.

- [ ] **Step 1: Construir só o pacote do SNES**

Run:
```bash
python3 tool/build_metadata_pack.py \
  --out /tmp/packs-verify \
  --built 2026-09-10 \
  --only nintendo_super_nintendo_entertainment_system
```
Expected: sai algo como `OpenVGDB: 33448 CRCs`, depois `Nintendo - Super Nintendo Entertainment System` e uma linha `  2415 jogos, 2152 com capa, 1819 com sinopse`. Anote os três números.

- [ ] **Step 2: Conferir os números contra a PoC**

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
print('jogos', len(games))
print('dumps', dumps)
print('capa %.1f%%' % (100 * cover / len(games)))
print('sinopse %.1f%%' % (100 * syn / len(games)))
print('regiao %.1f%% dos dumps' % (100 * reg / dumps))
assert 2300 <= len(games) <= 2550, 'colapso fora da faixa da PoC'
assert dumps > 4000, 'parser perdeu dumps'
assert cover / len(games) > 0.80, 'cobertura de capa caiu'
assert syn / len(games) > 0.65, 'cobertura de sinopse caiu'
# No DAT do SNES 293 dos 4268 blocos não declaram região, ou seja 93,1% têm.
# Abaixo de 85% o REGION_RE parou de casar.
assert reg / dumps > 0.85, 'region sumiu do parser'
print('ok')
PY
```
Expected: as cinco linhas de número e `ok` no final.

- [ ] **Step 3: Conferir a sanidade de um jogo conhecido**

Run:
```bash
python3 - <<'PY'
import gzip, json
pack = json.load(gzip.open('/tmp/packs-verify/nintendo_super_nintendo_entertainment_system.json.gz'))
game = next(g for g in pack['games'] if g['id'].endswith('/chrono-trigger'))
print(json.dumps(game, ensure_ascii=False, indent=2)[:800])
assert game['title'] == 'Chrono Trigger'
assert any(d['crc'] == '2D206BF7' for d in game['dumps'])
assert game['cover'].startswith('https://raw.githubusercontent.com/libretro-thumbnails/')
print('ok')
PY
```
Expected: o JSON do jogo com título, dumps e capa, depois `ok`.

- [ ] **Step 4: Conferir o tamanho do arquivo**

Run: `ls -lh /tmp/packs-verify/`
Expected: o `.json.gz` na casa de 0,5 MB, que é o que o build real do SNES produziu (469K comprimido, 2,0 MB cru). Acima de 3 MB significa que sinopse longa demais entrou sem corte, e vale truncar a sinopse em 1200 caracteres no `enrich_from_openvgdb` antes de seguir. Para referência, a maior sinopse do SNES tem 2418 caracteres e a média fica em 257, então o corte não é necessário neste pacote.

- [ ] **Step 5: Rodar a suíte inteira dos dois lados**

Run: `flutter test && (cd tool && python3 -m unittest discover -s . -p 'test_*.py')`
Expected: PASS nos dois.

- [ ] **Step 6: Commit da anotação dos números**

Adicione ao final da seção 4.4 de `docs/stremio-de-jogos-design.md` um parágrafo com os números que você mediu neste task, no formato: "Build de <data>: o pacote do SNES saiu com N jogos a partir de M dumps, X% com capa e Y% com sinopse."

```bash
git add docs/stremio-de-jogos-design.md
git commit -m "docs: numeros medidos da primeira build de metadata pack"
```

---

## O que esta fatia não faz

Explicitamente fora do escopo da fatia 1, cada item com a fatia dona:

- Casar o pacote com a listagem de uma fonte remota, os tiers do matcher e o CRC32 por HTTP Range: fatia 2.
- Trocar a grade de arquivos por grade de jogos, badge de disponibilidade e tela de detalhe: fatia 3.
- Tela de contas, migração de token para secure storage e o formato estendido do RTS: fatia 4.
- `SourceResolver` e `HttpResolver`: fatia 5.
- `DebridClient` e Real-Debrid: fatia 6.

Três decisões de formato que valem estar escritas, para a fatia 2 não as tratar como esquecimento:

- **`norm` e `canon` não existem em Dart.** Eles vivem só no builder Python, e o app nunca os executa: o pacote já chega com o título canônico pronto. A fatia 2 precisa de normalização em runtime para comparar o nome do arquivo remoto com o do dump, então ela vai reimplementar essas duas funções em Dart, não herdá-las. As duas versões precisam concordar caso a caso, e as fixtures de `NormTest` e `DisplayTitleTest` deste plano servem de base para o par de testes.
- **O md5 é descartado de propósito.** O DAT traz md5 em toda linha `rom`, e o `ROM_RE` até o captura, mas só para o grupo do sha1 cair na posição certa. Nenhum dos três eixos de identidade do spec usa md5: o casamento por nome não usa hash, a conferência pós-download usa CRC32 e o desempate da seção 5.7 também. Um terceiro hash por dump engordaria o pacote sem comprador.
- **O `serial` não é normalizado.** `crc` e `sha1` sobem para maiúsculas nos dois lados, no Python e no `PackDump.fromJson`, porque são hexadecimais e a comparação precisa ser estável. O `serial` é uma string de catálogo do fabricante, com maiúsculas e hifens que fazem parte do valor (`SLPS-01204`, `SHVC-AY2J-JPN`), e vai para o pacote exatamente como o DAT emite. Quem comparar serial na fatia 2 compara literal.

Ao fim desta fatia nada muda na tela: o app ganha a capacidade de buscar e guardar os pacotes, e nenhuma tela ainda os consome. Isso é intencional. A fatia 3 é a primeira que aparece para o usuário.
