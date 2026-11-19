import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

class GameTags extends StatelessWidget {
  final Game game;

  const GameTags({
    super.key,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    final tags = _getGameTags();
    if (tags.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 2),
        Wrap(
          spacing: 3,
          runSpacing: 2,
          children: [for (final tag in tags) _tag(tag, _getTagColor(context, tag))],
        ),
      ],
    );
  }

  List<String> _getGameTags() {
    final tags = <String>[];
    final metadata = game.metadata;
    if (metadata == null) return tags;

    if (metadata.dumpQualities.contains(DumpQuality.badDump)) tags.add('Bad');
    if (metadata.dumpQualities.contains(DumpQuality.overdump)) tags.add('Over');

    if (metadata.romTypes.contains(RomType.demo)) tags.add('Demo');
    if (metadata.romTypes.contains(RomType.sample)) tags.add('Sample');
    if (metadata.romTypes.contains(RomType.proto)) tags.add('Proto');
    if (metadata.romTypes.contains(RomType.beta)) tags.add('Beta');
    if (metadata.romTypes.contains(RomType.alpha)) tags.add('Alpha');
    if (metadata.romTypes.contains(RomType.bios)) tags.add('BIOS');

    if (metadata.modifications.contains(ModificationType.hack)) tags.add('Hack');
    if (metadata.modifications.contains(ModificationType.translation)) tags.add('Transl.');
    if (metadata.modifications.contains(ModificationType.fixed)) tags.add('Fixed');
    if (metadata.modifications.contains(ModificationType.trainer)) tags.add('Trainer');

    if (metadata.distributionTypes.contains(DistributionType.alternate)) tags.add('Alt');
    if (metadata.distributionTypes.contains(DistributionType.unlicensed)) tags.add('Unlic');
    if (metadata.distributionTypes.contains(DistributionType.aftermarket)) tags.add('After');
    if (metadata.distributionTypes.contains(DistributionType.pirate)) tags.add('Pirate');

    return tags;
  }

  Widget _tag(String tag, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            // The warning amber is too light for white.
            color: ThemeData.estimateBrightnessForColor(color) == Brightness.light ? Colors.black87 : Colors.white,
          ),
        ),
      );

  Color _getTagColor(BuildContext context, String tag) {
    switch (tag) {
      case 'Bad':
      case 'Over':
        return StyleTokens.of(context).error;
      case 'Demo':
      case 'Sample':
      case 'Proto':
      case 'Beta':
      case 'Alpha':
        return StyleTokens.of(context).warning;
      case 'Hack':
      case 'Transl.':
      case 'Fixed':
      case 'Trainer':
        return Colors.blue.shade600;
      case 'Alt':
      case 'Unlic':
      case 'After':
      case 'Pirate':
        return Colors.purple.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}
