import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/services/update_service.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
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
          state.asset != null
              ? formatBytes(state.asset!.size)
              : ServerMode.current
                  ? 'Update the Docker image: $_pullCommand'
                  : 'Download it from the release page',
        ),
      UpdatePhase.downloading => ('Downloading ${release?.version}…', '${(state.progress * 100).round()}%'),
      UpdatePhase.ready => notifier.handheld
          ? ('Update ready', 'Restart Retro Toolbox to finish the update')
          : ('Update downloaded', 'Install version ${release?.version}'),
      UpdatePhase.installFailed => ('Update not installed', state.message ?? ''),
      UpdatePhase.error => (release == null ? 'Update check failed' : 'Update failed', state.message ?? ''),
      UpdatePhase.portMaster => ('Updates through PortMaster', 'Installed from PortMaster: update Retro Toolbox there'),
    };

    final (String label, VoidCallback? onPressed) = switch (state.phase) {
      UpdatePhase.available when state.asset == null && ServerMode.current => (
          'Copy command',
          () => Clipboard.setData(const ClipboardData(text: _pullCommand)),
        ),
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

    final t = KitType.of(context);
    final failed = state.phase == UpdatePhase.error || state.installFailed;
    return KitPanel(
      padding: const EdgeInsets.all(12),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (failed ? t.k.error : t.k.accent).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(t.k.buttonRadius.clamp(4, 8).toDouble()),
                  ),
                  child: Icon(failed ? Icons.error_outline_rounded : Icons.system_update_rounded, size: 18, color: failed ? t.k.error : t.k.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.row),
                      const SizedBox(height: 2),
                      Text(subtitle, style: t.subtitle.copyWith(fontSize: t.size(13))),
                    ],
                  ),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes, style: t.subtitle.copyWith(fontSize: t.size(13))),
            ],
            if (readyNote != null) ...[
              const SizedBox(height: 12),
              Text(readyNote, style: t.subtitle.copyWith(fontSize: t.size(13))),
            ],
            if (state.phase == UpdatePhase.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.progress > 0 ? state.progress : null),
            ],
            if (state.phase != UpdatePhase.portMaster) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: state.installFailed
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        FilledButton.tonal(
                          focusNode: _action,
                          autofocus: true,
                          onPressed: () => notifier.keepFailedUpdate(widget.currentVersion),
                          child: const Text('Try again on next start'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => notifier.discardFailedUpdate(widget.currentVersion),
                          child: const Text('Discard update'),
                        ),
                      ],
                    )
                  : FilledButton.tonal(focusNode: _action, onPressed: onPressed, child: Text(label)),
            ),
            ],
          ],
        ),
      ],
    );
  }

  static const _pullCommand = 'docker compose pull && docker compose up -d';

  static Future<void> _openPage(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
