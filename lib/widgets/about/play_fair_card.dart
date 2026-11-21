import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// The app's stance on piracy: in About, and when the Games Library is enabled.
class PlayFairCard extends StatelessWidget {
  const PlayFairCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    return KitPanel(
      edge: k.accent.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.verified_user_rounded, color: k.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Play fair', style: t.row),
              const SizedBox(height: 2),
              Text(
                'Retro Toolbox is a utility, not a source of games. Neither the app nor its developers endorse piracy. It stands for easy access to a library you already own. Stick to trusted sources and download only titles you own.',
                style: t.subtitle.copyWith(fontSize: t.size(13)),
              ),
            ]),
          ),
        ]),
      ],
    );
  }
}
