// Runs the matcher over a real pack and a real listing, and prints the tier
// table. Runs outside Flutter:
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

/// ROM names from an `archive.org/metadata/<item>` response, excluding
/// derivative files.
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
