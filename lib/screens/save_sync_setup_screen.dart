import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';

/// The two decisions a handheld needs before it can sync anything: where the
/// saves go, and which of the apps already named there apply here.
///
/// Its own screen rather than cards on the list, because a first run is a
/// sequence with an end, and because the list behind it has nothing to show
/// until both answers exist.
class SaveSyncSetupScreen extends ConsumerStatefulWidget {
  const SaveSyncSetupScreen({super.key});

  @override
  ConsumerState<SaveSyncSetupScreen> createState() => _SaveSyncSetupScreenState();
}

class _SaveSyncSetupScreenState extends ConsumerState<SaveSyncSetupScreen> {
  static const _steps = ['Where', 'Apps'];

  /// Packages the owner left ticked. Null until the hub has been read once,
  /// so the first paint cannot tick boxes it has not seen.
  Set<String>? _chosen;

  bool get _onStep2 => ref.read(saveSyncProvider).hubKind != HubKind.none;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(saveSyncProvider);
    final step = s.hubKind == HubKind.none || s.hubKind == HubKind.unknown ? 0 : 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(theme, step),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: step == 0 ? _whereStep(theme, s) : _appsStep(theme, s),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(ThemeData theme, int step) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sync, size: 28),
            const SizedBox(width: 12),
            Text('Save Sync', style: theme.textTheme.titleLarge),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _stepDot(theme, i, step),
              if (i < _steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: i < step ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ]),
        ]),
      );

  Widget _stepDot(ThemeData theme, int i, int step) {
    final active = i == step;
    final done = i < step;
    return Column(children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: done || active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
        child: done
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : Text('${i + 1}', style: TextStyle(color: active ? Colors.white : theme.colorScheme.onSurfaceVariant)),
      ),
      const SizedBox(height: 6),
      Text(_steps[i], style: theme.textTheme.labelSmall),
    ]);
  }

  Widget _whereStep(ThemeData theme, SaveSyncState s) {
    final n = ref.read(saveSyncProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Where should saves go?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'Google Drive keeps them in a folder in your own Drive, and Retro Toolbox sees only the files it puts there. '
        'A folder works without Google: another app carries it between your handhelds.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      if (s.googleAvailable)
        FilledButton.icon(
          onPressed: s.signingIn ? null : n.signInWithGoogle,
          icon: const Icon(Icons.login),
          label: const Text('Sign in with Google'),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: s.signingIn ? null : () => n.setHubFolder(),
        icon: const Icon(Icons.folder),
        label: const Text('Use a folder'),
      ),
      if (s.signInError != null) ...[
        const SizedBox(height: 12),
        Text(s.signInError!, style: TextStyle(color: theme.colorScheme.error)),
      ],
      if (s.signingIn) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
    ]);
  }

  Widget _appsStep(ThemeData theme, SaveSyncState s) {
    if (s.loading) {
      return Column(children: [
        const SizedBox(height: 24),
        const Center(child: HammerLoader()),
        const SizedBox(height: 12),
        Text('Reading the hub…', style: theme.textTheme.bodyMedium),
      ]);
    }
    if (s.error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.read(saveSyncProvider.notifier).setHubFolder(),
              child: const Text('Pick the folder again'),
            ),
          ]),
        ),
      );
    }

    final here = [for (final g in s.games) if (g.bind is! NotInstalled) g];
    final elsewhere = [for (final g in s.games) if (g.bind is NotInstalled) g];
    final chosen = _chosen ??= {for (final g in here) g.recipe.packages.first};

    if (s.games.isEmpty) {
      return Column(children: [
        const SizedBox(height: 24),
        Icon(Icons.inbox, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text('This hub is empty.', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Nothing has been added yet. Open Save Sync and add the first app.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _done, child: const Text('Open Save Sync')),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This hub already covers ${s.games.length} app${s.games.length == 1 ? '' : 's'}.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      if (here.isNotEmpty) ...[
        Text('Will apply here (${chosen.length})', style: theme.textTheme.titleSmall),
        for (final g in here)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: chosen.contains(g.recipe.packages.first),
            title: Text(s.appInfo[g.recipe.packages.first]?.label ?? g.recipe.name),
            subtitle: Text(g.recipe.packages.first, style: theme.textTheme.bodySmall),
            onChanged: (on) => setState(() {
              final key = g.recipe.packages.first;
              on == true ? chosen.add(key) : chosen.remove(key);
            }),
          ),
      ],
      // Shown rather than filtered away: a handheld that quietly drops apps
      // leaves the owner wondering what happened to them.
      if (elsewhere.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Not on this device (${elsewhere.length})', style: theme.textTheme.titleSmall),
        for (final g in elsewhere)
          Opacity(
            opacity: 0.5,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(s.appInfo[g.recipe.packages.first]?.label ?? g.recipe.name),
              subtitle: Text(g.recipe.packages.first, style: theme.textTheme.bodySmall),
            ),
          ),
      ],
      if (s.recipeProblems.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Needs a look (${s.recipeProblems.length})', style: theme.textTheme.titleSmall),
        for (final e in s.recipeProblems.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(e.key),
            subtitle: Text('No recipe for this one yet', style: theme.textTheme.bodySmall),
          ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _done,
        child: Text(here.isEmpty ? 'Open Save Sync' : 'Adopt ${chosen.length}'),
      ),
    ]);
  }

  void _done() {
    if (!mounted) return;
    Navigator.of(context).pop(_onStep2);
  }
}
