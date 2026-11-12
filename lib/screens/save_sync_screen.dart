import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Words for a unit's plan.
String planLabel(UnitPlan plan) => switch (plan) {
      UpToDate() => 'up to date',
      PushPlan() => 'push pending',
      PullPlan(:final missingLocally) => missingLocally ? 'not on this device, pull available' : 'pull available',
      Diverged() => 'divergence: both sides changed (choosing a version comes in a later update)',
      Busy() => 'save in progress',
      Blocked(:final reason) => reason,
    };

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class SaveSyncScreen extends ConsumerStatefulWidget {
  const SaveSyncScreen({super.key});

  @override
  ConsumerState<SaveSyncScreen> createState() => _SaveSyncScreenState();
}

class _SaveSyncScreenState extends ConsumerState<SaveSyncScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(saveSyncProvider.notifier).refresh());
  }

  Future<void> _pickHub() async {
    final current = ref.read(saveSyncProvider).hubFolder;
    final path = await pickDirectory(context, title: 'Choose the hub folder', initialDir: current.isEmpty ? null : current);
    if (path != null) await ref.read(saveSyncProvider.notifier).setHubFolder(path);
  }

  /// Switches the hub. Game folders are never touched by a switch.
  Future<void> _chooseHub() async {
    final google = ref.read(saveSyncProvider).googleAvailable;
    final pick = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Where should saves go?'),
        children: [
          if (google)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('google'),
              child: const ListTile(
                leading: Icon(Icons.cloud),
                title: Text('Google Drive'),
                subtitle: Text('Sign in and pick the account on the next screen'),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('folder'),
            child: const ListTile(
              leading: Icon(Icons.folder_shared),
              title: Text('A folder on this device'),
              subtitle: Text('Another app (Syncthing, FolderSync) carries it between devices'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (pick == 'google') await ref.read(saveSyncProvider.notifier).signInWithGoogle();
    if (pick == 'folder') await _pickHub();
  }

  Future<void> _showCheck(GameStatus g) async {
    final lines = ref.read(saveSyncProvider.notifier).check(g.recipe.id).catchError(
          (Object e) => [CheckLine(CheckLevel.fail, 'Check', '$e')],
        );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Check: ${g.recipe.name}'),
        content: SizedBox(
          width: 480,
          child: FutureBuilder<List<CheckLine>>(
            future: lines,
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
              return ListView(
                shrinkWrap: true,
                children: [
                  for (final l in snap.data!)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        switch (l.level) {
                          CheckLevel.ok => Icons.check_circle,
                          CheckLevel.warn => Icons.warning_amber,
                          CheckLevel.fail => Icons.error,
                        },
                        color: switch (l.level) {
                          CheckLevel.ok => Colors.green,
                          CheckLevel.warn => Colors.orange,
                          CheckLevel.fail => Theme.of(context).colorScheme.error,
                        },
                      ),
                      title: Text(l.title),
                      subtitle: Text(l.detail),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _confirm(NeedsConfirm c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are these the saves?'),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            Text(c.binding.dir(const DevicePaths())),
            const SizedBox(height: 8),
            for (final f in c.files) Text(f),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Use this place')),
        ],
      ),
    );
    if (ok == true) await ref.read(saveSyncProvider.notifier).confirmBinding(c.binding);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(saveSyncProvider);
    final n = ref.read(saveSyncProvider.notifier);
    final busy = s.busyRecipe != null || s.loading || s.signingIn;
    final errorStyle = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Sync'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: busy ? null : n.refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ToolDescription(
              icon: Icons.sync,
              text: "Pull a game's save before you play and push it after. Saves go to the hub: "
                  '${s.googleAvailable ? 'a Retro Toolbox Saves folder in your own Google Drive, or ' : ''}'
                  'a folder another app (Syncthing, FolderSync) carries between devices. '
                  'Every save this replaces is kept in history on this device.',
            ),
            const SizedBox(height: 12),
            if (s.hubKind == HubKind.none) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Where should saves go?', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    if (s.googleAvailable)
                      const Text('Google Drive keeps them in a "Retro Toolbox Saves" folder in your own Drive. '
                          'Retro Toolbox sees only the files it creates there.'),
                    Text(s.googleAvailable
                        ? 'A folder works without Google: another app (Syncthing, FolderSync) carries it between devices.'
                        : 'Another app (Syncthing, FolderSync) carries the folder between devices.'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (s.googleAvailable)
                        FilledButton.icon(onPressed: busy ? null : n.signInWithGoogle, icon: const Icon(Icons.login), label: const Text('Sign in with Google')),
                      OutlinedButton.icon(onPressed: busy ? null : () => n.setHubFolder(), icon: const Icon(Icons.folder), label: const Text('Use a folder')),
                    ]),
                    if (s.signInError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.signInError!, style: errorStyle)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (s.access == SyncAccess.none)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('No access to game folders'),
                    const SizedBox(height: 4),
                    Text(
                      s.shizukuRunning
                          ? 'Shizuku is running. Allow Retro Toolbox to use it.'
                          : 'Start Shizuku (wireless debugging, or root), then come back and refresh.',
                    ),
                    const SizedBox(height: 8),
                    if (s.shizukuRunning)
                      FilledButton(onPressed: busy ? null : n.requestShizuku, child: const Text('Grant Shizuku access'))
                    else
                      OutlinedButton(onPressed: busy ? null : n.refresh, child: const Text('Retry')),
                  ]),
                ),
              )
            else
              Text('Access: ${s.access == SyncAccess.root ? 'root' : 'Shizuku (shell)'}'),
            const SizedBox(height: 8),
            if (s.hubKind == HubKind.drive)
              Row(children: [
                const Icon(Icons.cloud, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Google Drive: ${s.googleEmail}', overflow: TextOverflow.ellipsis)),
                if (s.signInAgain) FilledButton(onPressed: busy ? null : n.signInWithGoogle, child: const Text('Sign in again')),
                TextButton(onPressed: busy ? null : n.signOut, child: const Text('Sign out')),
                TextButton(onPressed: busy ? null : _chooseHub, child: const Text('Change')),
              ]),
            if (s.hubKind == HubKind.folder) ...[
              Row(children: [
                const Icon(Icons.folder_shared, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(s.hubFolder, overflow: TextOverflow.ellipsis)),
                TextButton(onPressed: busy ? null : _chooseHub, child: const Text('Change')),
              ]),
              Text(
                'Folder hub: "up to date" means up to date with what this folder holds right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (s.signInError != null && s.hubKind != HubKind.none) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.signInError!, style: errorStyle)),
            if (s.loading || s.signingIn) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (s.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.error!, style: errorStyle)),
            for (final m in s.messages) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m)),
            const SizedBox(height: 8),
            for (final g in s.games) _GameCard(game: g, busy: busy, onPush: () => n.push(g.recipe.id), onPull: () => n.pull(g.recipe.id), onCheck: () => _showCheck(g), onConfirm: _confirm),
            for (final e in s.recipeProblems.entries) Text('Recipe ${e.key} not loaded: ${e.value}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.busy, required this.onPush, required this.onPull, required this.onCheck, required this.onConfirm});

  final GameStatus game;
  final bool busy;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onCheck;
  final void Function(NeedsConfirm) onConfirm;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.recipe.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            [
              '${g.source} recipe',
              bindLabel(g.bind),
              if (g.installedVersion != null) 'version ${g.installedVersion}',
              if (g.backupOnly) 'backup only (the game has its own cloud)',
            ].join(' · '),
            style: small,
          ),
          if (g.error != null) Text(g.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (g.running) Text('${g.recipe.name} is running: close it to sync'),
          for (final note in g.notes) Text(note, style: small),
          const SizedBox(height: 6),
          for (final e in g.units.entries)
            Text(
              [
                '${e.key}: ${planLabel(e.value.plan)}',
                if (e.value.newest != null) 'newest by ${e.value.newest!.deviceName}, ${_when(e.value.newest!.createdAt)}',
              ].join(' · '),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (g.bind case final NeedsConfirm c) FilledButton(onPressed: busy ? null : () => onConfirm(c), child: const Text('Confirm save location')),
            OutlinedButton.icon(onPressed: !busy && g.canPull ? onPull : null, icon: const Icon(Icons.download), label: const Text('Pull')),
            FilledButton.icon(onPressed: !busy && g.canPush ? onPush : null, icon: const Icon(Icons.upload), label: const Text('Push')),
            TextButton.icon(onPressed: busy ? null : onCheck, icon: const Icon(Icons.fact_check), label: const Text('Check')),
          ]),
        ]),
      ),
    );
  }
}
