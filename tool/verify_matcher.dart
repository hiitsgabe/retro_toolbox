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
