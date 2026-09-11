import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
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
}
