import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/services/update_service.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:url_launcher/url_launcher.dart';

/// About's update status, in the InfoCard style. [currentVersion] is null
/// until package info loads.
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({super.key, required this.currentVersion});
  final String? currentVersion;

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  final _action = FocusNode(debugLabel: 'update action');

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(updateProvider.notifier);
    final state = ref.watch(updateProvider);
    // The action button is disabled while busy, which drops its focus; hand
    // it back when there is something to press again and nothing else holds focus.
    ref.listen(updateProvider, (_, next) {
      if (next.busy) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focused = FocusManager.instance.primaryFocus;
        if (mounted && (focused == null || focused is FocusScopeNode)) _action.requestFocus();
      });
    });

    final release = state.release;
    final (String title, String subtitle) = switch (state.phase) {
      UpdatePhase.idle => ('Updates', 'Check for a newer version'),
      UpdatePhase.checking => ('Checking for updates…', 'Asking GitHub for the latest release'),
      UpdatePhase.upToDate => ('Up to date', 'Version ${widget.currentVersion ?? '-'} is the latest'),
      UpdatePhase.available => (
          'Version ${release?.version} available',
          state.asset == null ? 'Download it from the release page' : formatBytes(state.asset!.size),
        ),
      UpdatePhase.downloading => ('Downloading ${release?.version}…', '${(state.progress * 100).round()}%'),
      UpdatePhase.ready => notifier.handheld
          ? ('Update ready', 'Restart Retro Toolbox to finish the update')
          : ('Update downloaded', 'Install version ${release?.version}'),
      UpdatePhase.error => ('Update check failed', state.message ?? ''),
    };

    final (String label, VoidCallback? onPressed) = switch (state.phase) {
      UpdatePhase.available when state.asset == null => ('Open release page', () => _openPage(release!.htmlUrl)),
      UpdatePhase.available => ('Download update', notifier.download),
      UpdatePhase.ready when notifier.handheld => ('Close app', () => exit(0)),
      UpdatePhase.ready => ('Install', notifier.install),
      UpdatePhase.checking || UpdatePhase.downloading => ('Check for updates', null),
      _ => (
          'Check for updates',
          widget.currentVersion == null ? null : () => notifier.check(widget.currentVersion!),
        ),
    };

    final notes = state.phase == UpdatePhase.available && release != null ? releaseNotesExcerpt(release.notes) : '';
    final readyNote = state.phase == UpdatePhase.ready ? state.message : null;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    state.phase == UpdatePhase.error ? Icons.error_outline_rounded : Icons.system_update_rounded,
                    size: 20,
                    color: state.phase == UpdatePhase.error ? theme.colorScheme.error : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (readyNote != null) ...[
              const SizedBox(height: 12),
              Text(readyNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (state.phase == UpdatePhase.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.progress > 0 ? state.progress : null),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(focusNode: _action, onPressed: onPressed, child: Text(label)),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openPage(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
