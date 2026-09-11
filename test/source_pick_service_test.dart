import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

Game _game(String filename, int size) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://exemplo.org/snes/$filename',
      size: size,
      consoleId: 'snes',
    );

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

VerifiedSource _v(String filename, SourceVerification state) => (
      source: MatchedSource(
        filename: filename,
        sourceId: kBuiltinSourceId,
        confidence: MatchConfidence.likely,
        size: 100,
      ),
      state: state,
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
}
