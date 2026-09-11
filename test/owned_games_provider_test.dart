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
