import 'package:flutter/material.dart';

/// The app's stance on piracy: in About, and when the Games Library is enabled.
class PlayFairCard extends StatelessWidget {
  const PlayFairCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, color: theme.colorScheme.primary, size: 28),
          const SizedBox(height: 8),
          Text(
            'Play fair',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Retro Toolbox is a utility, not a source of games. Neither the app nor its developers endorse piracy. It stands for easy access to a library you already own. Stick to trusted sources and download only titles you own.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
