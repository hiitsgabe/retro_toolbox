import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_add_app_screen.dart';
import 'package:retro_toolbox/screens/save_sync_setup_screen.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/row_state.dart';
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
  /// So a handheld that leaves setup without choosing is not sent straight
  /// back into it.
  bool _offeredSetup = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(saveSyncProvider.notifier).refresh());
  }

  /// Puts back the save a pull replaced. The hub keeps one per handheld, so
  /// the choice is which handheld's, and the confirm says plainly that what
  /// is here now goes away.
  Future<void> _restore(GameStatus g) async {
    final n = ref.read(saveSyncProvider.notifier);
    final units = g.units.keys.toList()..sort();
    final unit = units.length == 1 ? units.first : null;
    if (unit == null && units.isEmpty) return;
    final backups = await n.backupsFor(g.recipe.id, unit ?? units.first);
    if (!mounted) return;
    if (backups.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No backup yet'),
          content: const Text('A backup is left in the hub each time a download replaces a save here. Nothing has been replaced yet.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<({String device, String name, DateTime at})>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Restore a backup', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'The save that was here before a download replaced it. One is kept per handheld.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final b in backups)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(b.name),
                    subtitle: Text(_when(b.at)),
                    onTap: () => Navigator.of(context).pop(b),
                  ),
                ),
            ]),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Put this one back?'),
        content: Text('The save here now is replaced by the backup from ${picked.name}. It is kept in this device\'s history first.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restore')),
        ],
      ),
    );
    if (go == true && mounted) await n.restoreBackup(g.recipe.id, unit ?? units.first, fromDevice: picked.device);
  }

  /// The two versions of a save that drifted apart, side by side, so the
  /// choice is made on what each one is rather than on which button is
  /// nearer. Nothing here destroys anything: whichever is kept, the one it
  /// replaces is filed into this device's history first.
  Future<void> _chooseVersion(GameStatus g, String unit, Diverged plan) async {
    final local = g.units[unit]?.local;
    final keep = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Which version should win?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (local != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.smartphone),
                    title: const Text('On this device'),
                    subtitle: Text('${local.hashes.length} file${local.hashes.length == 1 ? '' : 's'}'),
                    trailing: FilledButton(
                      onPressed: () => Navigator.of(context).pop(SaveSyncEngine.keepLocal),
                      child: const Text('Keep this'),
                    ),
                  ),
                ),
              for (final head in plan.heads)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud),
                    title: Text(head.deviceName),
                    subtitle: Text('${_when(head.createdAt)} · ${head.files.length} file${head.files.length == 1 ? '' : 's'}'),
                    trailing: FilledButton(
                      onPressed: () => Navigator.of(context).pop(head.gen),
                      child: const Text('Keep this'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Every save this replaces is kept in history on this device.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        );
      },
    );
    if (keep != null && mounted) await ref.read(saveSyncProvider.notifier).resolve(g.recipe.id, unit, keep: keep);
  }

  /// Picks more apps for this set of handhelds. The catalog is read here
  /// rather than on every refresh: it is wanted only when somebody is about
  /// to choose, and it is never a precondition for anything else.
  Future<void> _addApps() async {
    final n = ref.read(saveSyncProvider.notifier);
    final already = {for (final g in ref.read(saveSyncProvider).games) g.recipe.packages.first};
    final catalog = await n.catalog();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => SaveSyncAddAppScreen(already: already, catalog: catalog),
    ));
  }

  /// A handheld with no place chosen has nothing to list, so the first run
  /// gets its own two questions rather than a screen of empty cards.
  void _setupIfUnset(HubKind kind) {
    if (_offeredSetup || kind != HubKind.none) return;
    _offeredSetup = true;
    Future.microtask(() async {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const SaveSyncSetupScreen()));
      if (mounted) await ref.read(saveSyncProvider.notifier).refresh();
    });
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
    // A game this handheld does not have is not a row to act on, so it folds
    // into its own group below instead of sitting among the live ones. It
    // still reaches the hub report, so other devices keep seeing it.
    _setupIfUnset(s.hubKind);
    final shown = s.games.where((g) => g.bind is! NotInstalled).toList();
    final absent = s.games.where((g) => g.bind is NotInstalled).toList();
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
            // The first run has its own screen now; a chooser here as well
            // would be a second place to answer the same question.
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
            for (final g in shown)
              _AppRow(
                game: g,
                state: rowStateFor(g, hasAccess: s.access != SyncAccess.none),
                info: s.appInfo[g.recipe.packages.first],
                busy: s.busyRecipe == g.recipe.id,
                anyBusy: busy,
                onPush: () => n.push(g.recipe.id),
                onPull: () => n.pull(g.recipe.id),
                onCheck: () => _showCheck(g),
                onConfirm: _confirm,
                onRestore: () => _restore(g),
                hasAccess: s.access != SyncAccess.none,
                onPushUnit: (unit) => n.push(g.recipe.id, unit: unit),
                onPullUnit: (unit) => n.pull(g.recipe.id, unit: unit),
                onChooseVersion: () {
                  for (final e in g.units.entries) {
                    if (e.value.plan case final Diverged d) {
                      _chooseVersion(g, e.key, d);
                      return;
                    }
                  }
                },
              ),
            if (shown.isEmpty && !s.loading && s.hubKind != HubKind.none)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [
                  Icon(Icons.inbox, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(s.games.isEmpty ? 'No recipes loaded.' : 'Nothing here is set up to sync yet.'),
                ]),
              ),
            // Not hidden, just folded away: a game that vanished from the list
            // reads as lost data, especially when the hub says it is covered.
            if (absent.isNotEmpty)
              ExpansionTile(
                title: Text('Not on this device (${absent.length})'),
                children: [
                  for (final g in absent)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.videogame_asset, size: 20),
                      title: Text(s.appInfo[g.recipe.packages.first]?.label ?? g.recipe.name),
                    ),
                ],
              ),
            if (s.hubKind != HubKind.none && s.hubKind != HubKind.unknown) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : _addApps,
                icon: const Icon(Icons.add),
                label: const Text('Add an app'),
              ),
            ],
            if (s.recipeProblems.isNotEmpty)
              ExpansionTile(
                title: Text('Recipes that did not load (${s.recipeProblems.length})'),
                children: [
                  for (final e in s.recipeProblems.entries)
                    ListTile(dense: true, title: Text(e.key), subtitle: Text(e.value)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.game,
    required this.state,
    required this.info,
    required this.busy,
    required this.anyBusy,
    required this.onPush,
    required this.onPull,
    required this.onCheck,
    required this.onConfirm,
    required this.onChooseVersion,
    required this.onRestore,
    required this.onPushUnit,
    required this.onPullUnit,
    required this.hasAccess,
  });

  final GameStatus game;
  final RowState state;

  /// What Android shows for this app, when it could be read.
  final AppInfo? info;

  /// This row is the one working.
  final bool busy;

  /// Some row is working. The engine takes one action at a time, so the other
  /// rows' verbs wait — but taps, Check and the rest of the screen stay live.
  final bool anyBusy;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onCheck;
  final void Function(NeedsConfirm) onConfirm;
  final VoidCallback onChooseVersion;
  final VoidCallback onRestore;
  final void Function(String unit) onPushUnit;
  final void Function(String unit) onPullUnit;
  final bool hasAccess;

  /// The saves this recipe covers here, in a settled order.
  List<String> get units => game.units.keys.toList()..sort();

  /// A unit key is a folder name: a farm, or an emulated game's id. Shown as
  /// it is until something can name it better.
  String unitLabel(String unit) => unit;

  bool get _dim => state is RowBlocked || state is RowNotInstalled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = info?.label.isNotEmpty == true ? info!.label : game.recipe.name;
    return Opacity(
      opacity: _dim ? 0.5 : 1,
      child: Card(
        child: InkWell(
          onTap: onCheck,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Thumb(icon: info?.icon, badge: _badge(theme)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_line(), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text('${game.source} recipe', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (game.running) Text('Close the game first', style: theme.textTheme.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              if (busy)
                const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              else ...[
                if (units.length < 2) _verb() ?? const SizedBox.shrink(),
                // The row keeps one verb; everything else that can be done to
                // a game lives behind the dots, so a rare action never sits
                // next to the common one.
                PopupMenuButton<String>(
                  enabled: !anyBusy,
                  tooltip: 'More',
                  onSelected: (v) => v == 'restore' ? onRestore() : onCheck(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'restore', child: Text('Restore a backup…')),
                    PopupMenuItem(value: 'check', child: Text('Check')),
                  ],
                ),
              ],
              ]),
              // An emulator keeps one save per game under a single recipe, and
              // the game you are ahead in is not the game the other handheld is
              // ahead in. So each save gets its own line and its own verb, and
              // nothing acts on all of them at once.
              if (units.length > 1)
                for (final unit in units)
                  _UnitRow(
                    label: unitLabel(unit),
                    state: rowStateForUnit(game, unit, hasAccess: hasAccess),
                    busy: busy,
                    anyBusy: anyBusy,
                    onPush: () => onPushUnit(unit),
                    onPull: () => onPullUnit(unit),
                  ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Four shapes and no more. Blocked wears the neutral lock, a failure wears
  /// the error colour: a condition of the device and an incident never look
  /// alike.
  ({IconData icon, Color color})? _badge(ThemeData theme) => switch (state) {
        RowUpToDate() => (icon: Icons.check_circle, color: theme.colorScheme.primary),
        RowNeedsPush() => (icon: Icons.arrow_circle_up, color: theme.colorScheme.primary),
        RowNeedsPull() => (icon: Icons.arrow_circle_down, color: theme.colorScheme.primary),
        RowConflict() => (icon: Icons.error, color: theme.colorScheme.error),
        RowFailed() => (icon: Icons.error, color: theme.colorScheme.error),
        RowBlocked() || RowNotInstalled() => (icon: Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
        RowNeedsConfirm() => null,
      };

  /// One sentence. The direction is always named and the time always relative.
  String _line() => switch (state) {
        RowUpToDate(:final at) => at == null ? 'Up to date' : 'Up to date · ${_when(at)}',
        RowNeedsPush(:final at) => at == null ? 'Needs upload — nothing in the hub yet' : 'Needs upload — this device is newer (${_when(at)})',
        RowNeedsPull(:final fromDevice, :final at) => 'Needs download — $fromDevice is newer${at == null ? '' : ' (${_when(at)})'}',
        RowConflict() => 'Both sides changed since the last sync',
        RowNeedsConfirm() => 'Confirm where the saves are',
        RowNotInstalled() => 'Not installed here',
        RowFailed(:final message) => message,
        RowBlocked(:final reason) => switch (reason) {
            BlockReason.needsRoot => "Saves live in a folder only root can open. This device isn't rooted.",
            BlockReason.notOpenableHere => "This device can't open this app's save folder — it works on your other handheld.",
            BlockReason.folderMissing => 'Open the app once so it makes its save folder.',
            BlockReason.locationUnknown => 'The saves could be in more than one place here.',
            BlockReason.noAccess => 'Nothing syncs from this device yet.',
            BlockReason.backupOnly => 'This app has its own cloud — uploads only.',
          },
      };

  /// One verb, never two, and whichever direction the row needs is the
  /// affirmative one. A state with nothing to do offers nothing.
  Widget? _verb() => switch (state) {
        RowNeedsPull() => FilledButton.icon(onPressed: anyBusy ? null : onPull, icon: const Icon(Icons.download), label: const Text('Download')),
        RowNeedsPush() => FilledButton.icon(onPressed: anyBusy ? null : onPush, icon: const Icon(Icons.upload), label: const Text('Upload')),
        RowNeedsConfirm(:final bind) => FilledButton(onPressed: anyBusy ? null : () => onConfirm(bind), child: const Text('Confirm location')),
        RowBlocked(:final reason) when reason == BlockReason.backupOnly =>
          FilledButton.icon(onPressed: anyBusy ? null : onPush, icon: const Icon(Icons.upload), label: const Text('Upload')),
        RowConflict() => FilledButton(onPressed: anyBusy ? null : onChooseVersion, child: const Text('Choose version')),
        RowFailed() => OutlinedButton(onPressed: anyBusy ? null : onCheck, child: const Text('Details')),
        _ => null,
      };
}

/// One save inside a game that keeps several: a farm, or one emulated title.
/// Carries its own state and its own verb, because acting on all of them at
/// once is exactly what loses somebody's progress.
class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.label,
    required this.state,
    required this.busy,
    required this.anyBusy,
    required this.onPush,
    required this.onPull,
  });

  final String label;
  final RowState state;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onPush;
  final VoidCallback onPull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 60),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_line(), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        switch (state) {
          RowNeedsPull() => OutlinedButton.icon(
              onPressed: anyBusy ? null : onPull,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
            ),
          RowNeedsPush() => OutlinedButton.icon(
              onPressed: anyBusy ? null : onPush,
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Upload'),
            ),
          _ => const SizedBox.shrink(),
        },
      ]),
    );
  }

  String _line() => switch (state) {
        RowUpToDate(:final at) => at == null ? 'Up to date' : 'Up to date · ${_when(at)}',
        RowNeedsPush() => 'Needs upload — this device is newer',
        RowNeedsPull(:final fromDevice) => 'Needs download — $fromDevice is newer',
        RowConflict() => 'Both sides changed',
        RowFailed(:final message) => message,
        _ => '',
      };
}

/// The app's own icon in the house thumbnail frame, with the state badge
/// overlaid. No icon — no launcher activity, or any run off Android — falls
/// back to a neutral glyph in the same frame, so rows never change height.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.icon, required this.badge});

  final Uint8List? icon;
  final ({IconData icon, Color color})? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: icon != null
              ? Image.memory(icon!, width: 48, height: 48, gaplessPlayback: true, filterQuality: FilterQuality.medium)
              : Icon(Icons.videogame_asset, color: theme.colorScheme.onSurfaceVariant),
        ),
        if (badge != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
              child: Icon(badge!.icon, size: 14, color: badge!.color),
            ),
          ),
      ]),
    );
  }
}
