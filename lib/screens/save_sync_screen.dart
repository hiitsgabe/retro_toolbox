import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
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
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
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

/// "2 h ago": a row says how fresh a save is, not when to the minute.
String saveSyncAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 30) return '${d.inDays} days ago';
  return _when(t).substring(0, 10);
}

String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// A row's one action: what Start and its button say, and what they run.
typedef _Verb = ({String label, IconData icon, VoidCallback? run});

/// A row's state in a word with its colour, and the line after it.
typedef _Status = ({String word, KitTone tone, String? detail});

/// What the last action said in a row, and whether every save it named moved.
typedef _Result = ({String text, bool ok});

const _area = AppArea.saves;

class SaveSyncScreen extends ConsumerStatefulWidget {
  const SaveSyncScreen({super.key});

  @override
  ConsumerState<SaveSyncScreen> createState() => _SaveSyncScreenState();
}

class _SaveSyncScreenState extends ConsumerState<SaveSyncScreen> {
  /// So a handheld that leaves setup without choosing is not sent straight
  /// back into it.
  bool _offeredSetup = false;

  /// The game whose row has focus: Start runs its action and the bar names it.
  String? _focused;

  /// The game the last action ran on. Its results show in its own row, not
  /// as loose lines above the list.
  String? _acted;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(saveSyncProvider.notifier).refresh());
  }

  SaveSyncNotifier get _n => ref.read(saveSyncProvider.notifier);

  /// Runs an action on [g], remembering it so its result lands in its row.
  void _on(GameStatus g, Future<void> Function() action) {
    setState(() => _acted = g.recipe.id);
    action();
  }

  /// Some apps keep their saves under a directory they named at install time,
  /// and more than one of them can look right. The binder finds them all and
  /// refuses to pick; this is where the owner picks, seeing how much is in
  /// each one rather than guessing from a name that means nothing.
  Future<void> _chooseLocation(GameStatus g) async {
    if (g.bind case final NeedsDiscovery d when d.places.length > 1) {
      final picked = await showKitSheet<Binding>(
        context,
        area: _area,
        title: 'Which of these holds your saves?',
        subtitle: 'This app names its own save folder, and more than one here could be it.',
        builder: (context) {
          final t = KitType.of(context);
          return KitPanel(children: [
            for (final (i, (binding, files)) in d.places.indexed)
              KitRow(
                autofocus: i == 0,
                onTap: () => Navigator.of(context).pop(binding),
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 20, color: t.k.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(binding.root.split('/').last, style: t.mono(14)),
                      Text(files.isEmpty ? 'Nothing read from it yet' : _count(files.length, 'file'), style: t.subtitle),
                    ]),
                  ),
                ]),
              ),
          ]);
        },
      );
      if (picked != null && mounted) _on(g, () => _n.confirmBinding(picked));
    }
  }

  /// Which save of a game that keeps several, for an action that takes one.
  Future<String?> _pickUnit(GameStatus g, String title) async {
    final units = _units(g);
    if (units.length < 2) return units.firstOrNull;
    String? picked;
    await showRowMenu(context, title: title, subtitle: _label(g), items: [
      for (final u in units) RowMenuItem(_unitLabel(u), () => picked = u, icon: Icons.save_outlined),
    ]);
    return picked;
  }

  /// Puts back the save a pull replaced. The hub keeps one per handheld, so
  /// the choice is which handheld's, and the confirm says plainly that what
  /// is here now goes away.
  Future<void> _restore(GameStatus g, [String? unit]) async {
    unit ??= await _pickUnit(g, 'Restore which save?');
    if (unit == null || !mounted) return;
    final backups = await _n.backupsFor(g.recipe.id, unit);
    if (!mounted) return;
    if (backups.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No backup yet'),
          content: const Text('A backup is left in the hub each time a download replaces a save here. Nothing has been replaced yet.'),
          actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    final picked = await showKitSheet<({String device, String name, DateTime at})>(
      context,
      area: _area,
      title: 'Restore a backup',
      subtitle: 'The save that was here before a download replaced it. One is kept per handheld.',
      builder: (context) => KitPanel(children: [
        for (final (i, b) in backups.indexed)
          KitRow(
            autofocus: i == 0,
            onTap: () => Navigator.of(context).pop(b),
            child: Row(children: [
              Icon(Icons.history, size: 20, color: KitType.of(context).muted),
              const SizedBox(width: 10),
              Expanded(child: KitRowText(title: b.name, subtitle: _when(b.at))),
            ]),
          ),
      ]),
    );
    if (picked == null || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Put this one back?'),
        content: Text('The save here now is replaced by the backup from ${picked.name}. It is kept in this device\'s history first.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restore')),
        ],
      ),
    );
    if (go == true && mounted) _on(g, () => _n.restoreBackup(g.recipe.id, unit!, fromDevice: picked.device));
  }

  /// The two versions of a save that drifted apart, side by side, so the
  /// choice is made on what each one is rather than on which button is
  /// nearer. Nothing here destroys anything: whichever is kept, the one it
  /// replaces is filed into this device's history first.
  Future<void> _chooseVersion(GameStatus g, String unit, Diverged plan) async {
    final local = g.units[unit]?.local;
    final keep = await showKitSheet<String>(
      context,
      area: _area,
      title: 'Which version should win?',
      subtitle: 'Every save this replaces is kept in history on this device.',
      builder: (context) {
        Widget version(IconData icon, String title, String subtitle, String value, {bool first = false}) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                Icon(icon, size: 20, color: KitType.of(context).muted),
                const SizedBox(width: 10),
                Expanded(child: KitRowText(title: title, subtitle: subtitle)),
                FilledButton(autofocus: first, onPressed: () => Navigator.of(context).pop(value), child: const Text('Keep this')),
              ]),
            );
        return KitPanel(children: [
          if (local != null) version(Icons.smartphone, 'On this device', _count(local.hashes.length, 'file'), SaveSyncEngine.keepLocal, first: true),
          for (final head in plan.heads)
            version(Icons.cloud_outlined, head.deviceName, '${_when(head.createdAt)} · ${_count(head.files.length, 'file')}', head.gen, first: local == null && head == plan.heads.first),
        ]);
      },
    );
    if (keep != null && mounted) _on(g, () => _n.resolve(g.recipe.id, unit, keep: keep));
  }

  void _chooseFirstVersion(GameStatus g) {
    for (final e in g.units.entries) {
      if (e.value.plan case final Diverged d) {
        _chooseVersion(g, e.key, d);
        return;
      }
    }
  }

  /// Picks more apps for this set of handhelds. The catalog is asked again
  /// here, so the picker shows what was published a minute ago; it is never a
  /// precondition for anything else.
  Future<void> _addApps() async {
    final already = {for (final g in ref.read(saveSyncProvider).games) g.recipe.packages.first};
    final catalog = await _n.catalog();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => SaveSyncAddAppScreen(already: already, catalog: catalog, known: _n.knownRecipeByPackage),
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
      if (mounted) await _n.refresh();
    });
  }

  Future<void> _pickHub() async {
    final current = ref.read(saveSyncProvider).hubFolder;
    final path = await pickDirectory(context, title: 'Choose the hub folder', initialDir: current.isEmpty ? null : current);
    if (path != null) await _n.setHubFolder(path);
  }

  /// Switches the hub. Game folders are never touched by a switch.
  Future<void> _chooseHub(BuildContext context) async {
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
    if (pick == 'google') await _n.signInWithGoogle();
    if (pick == 'folder') await _pickHub();
  }

  Future<void> _showCheck(GameStatus g) async {
    final lines = _n.check(g.recipe.id).catchError((Object e) => [CheckLine(CheckLevel.fail, 'Check', '$e')]);
    await showKitSheet<void>(
      context,
      area: _area,
      title: 'Check: ${_label(g)}',
      subtitle: 'What Save Sync found. Nothing is changed.',
      builder: (context) => FutureBuilder<List<CheckLine>>(
        future: lines,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
          final t = KitType.of(context);
          return KitPanel(children: [
            for (final l in snap.data!)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    switch (l.level) {
                      CheckLevel.ok => Icons.check_circle,
                      CheckLevel.warn => Icons.warning_amber,
                      CheckLevel.fail => Icons.error,
                    },
                    size: 18,
                    color: switch (l.level) {
                      CheckLevel.ok => t.k.success,
                      CheckLevel.warn => t.k.warning,
                      CheckLevel.fail => t.k.error,
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: KitRowText(title: l.title, subtitle: l.detail)),
                ]),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _confirm(GameStatus g, NeedsConfirm c) async {
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
          FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: const Text('Use this place')),
        ],
      ),
    );
    if (ok == true && mounted) _on(g, () => _n.confirmBinding(c.binding));
  }

  // ---- What a row says and does ----

  SaveSyncState get _s => ref.read(saveSyncProvider);

  String _label(GameStatus g) {
    final info = _s.appInfo[g.recipe.packages.first];
    return info?.label.isNotEmpty == true ? info!.label : g.recipe.name;
  }

  /// A unit key is a folder name: a farm, or an emulated game's id. An id the
  /// catalog knows is shown as the game; anything else is shown as it is.
  String _unitLabel(String unit) => _s.titles[unit.toUpperCase()]?.name ?? unit;

  /// The saves this recipe covers here, in a settled order: by what they are
  /// called, so a list of games reads alphabetically rather than by id.
  List<String> _units(GameStatus g) => g.units.keys.toList()..sort((a, b) => _unitLabel(a).toLowerCase().compareTo(_unitLabel(b).toLowerCase()));

  /// A game with several saves (an emulator, a farm each) opens a list of
  /// them; each one syncs on its own, since acting on all of them at once is
  /// exactly what loses somebody's progress.
  bool _multi(GameStatus g) => g.bind is Bound && g.units.length > 1;

  bool get _hasAccess => _s.access != SyncAccess.none;

  /// One verb, never two, and whichever direction the row needs is the
  /// affirmative one. A state with nothing to do offers nothing.
  _Verb? _verb(GameStatus g, RowState state, {required bool anyBusy}) {
    if (g.running) return null;
    VoidCallback? go(VoidCallback f) => anyBusy ? null : f;
    if (_multi(g)) return (label: 'Open saves', icon: Icons.chevron_right, run: () => _openSaves(g));
    return switch (state) {
      RowNeedsPull() => (label: 'Download', icon: Icons.download, run: go(() => _on(g, () => _n.pull(g.recipe.id)))),
      RowNeedsPush() => (label: 'Upload', icon: Icons.upload, run: go(() => _on(g, () => _n.push(g.recipe.id)))),
      RowNeedsConfirm(:final bind) => (label: 'Confirm location', icon: Icons.task_alt, run: go(() => _confirm(g, bind))),
      RowBlocked(:final reason) when reason == BlockReason.locationUnknown && g.bind is NeedsDiscovery && (g.bind as NeedsDiscovery).places.length > 1 =>
        (label: 'Choose location', icon: Icons.folder_open, run: go(() => _chooseLocation(g))),
      RowBlocked(:final reason) when reason == BlockReason.backupOnly => (label: 'Upload', icon: Icons.upload, run: go(() => _on(g, () => _n.push(g.recipe.id)))),
      RowConflict() => (label: 'Choose version', icon: Icons.call_split, run: go(() => _chooseFirstVersion(g))),
      RowFailed() => (label: 'Details', icon: Icons.info_outline, run: () => _showCheck(g)),
      _ => null,
    };
  }

  _Status _status(RowState state) => switch (state) {
        RowUpToDate(:final at) => (word: 'Up to date', tone: KitTone.success, detail: at == null ? null : 'synced ${saveSyncAgo(at)}'),
        RowNeedsPush(:final at) => (word: 'Needs upload', tone: KitTone.accent, detail: at == null ? 'nothing in the hub yet' : 'this device is newer'),
        RowNeedsPull(:final fromDevice, :final at) => (word: 'Needs download', tone: KitTone.info, detail: '$fromDevice is newer${at == null ? '' : ', ${saveSyncAgo(at)}'}'),
        RowConflict() => (word: 'Both sides changed since the last sync', tone: KitTone.error, detail: null),
        RowNeedsConfirm() => (word: 'Confirm where the saves are', tone: KitTone.warning, detail: null),
        RowNotInstalled() => (word: 'Not installed here', tone: KitTone.neutral, detail: null),
        RowFailed(:final message) => (word: 'Failed', tone: KitTone.error, detail: message),
        RowBlocked(:final reason) => (
            word: switch (reason) {
              BlockReason.needsRoot => "Saves live in a folder only root can open. This device isn't rooted.",
              BlockReason.notOpenableHere => "This device can't open this app's save folder. It works on your other handheld.",
              BlockReason.folderMissing => 'Open the app once so it makes its save folder.',
              BlockReason.locationUnknown => 'The saves could be in more than one place here.',
              BlockReason.noAccess => 'Nothing syncs from this device yet.',
              BlockReason.backupOnly => 'This app has its own cloud: uploads only.',
            },
            tone: KitTone.neutral,
            detail: null,
          ),
      };

  /// The row of a game with several saves: what its saves owe, the most
  /// urgent first and in its colour, then how many saves there are.
  _Status _multiStatus(GameStatus g, RowState state) {
    final states = [for (final u in g.units.keys) rowStateForUnit(g, u, hasAccess: _hasAccess)];
    final saves = _count(states.length, 'save');
    final both = states.whereType<RowConflict>().length;
    final down = states.whereType<RowNeedsPull>().length, up = states.whereType<RowNeedsPush>().length;
    final owed = [
      if (both > 0) (word: '$both with both sides changed', tone: KitTone.error),
      if (down > 0) (word: '$down to download', tone: KitTone.info),
      if (up > 0) (word: '$up to upload', tone: KitTone.accent),
    ];
    if (owed.isEmpty) {
      final s = _status(state);
      return (word: s.word, tone: s.tone, detail: saves);
    }
    return (word: owed.first.word, tone: owed.first.tone, detail: [for (final o in owed.skip(1)) o.word, saves].join(' · '));
  }

  /// What the last action said about [g] (about its save [unit] only, when
  /// given), in the row's words: "Pushed" in a row that is one save, the
  /// save's name first in a row of several. Null when it said nothing here.
  _Result? _results(GameStatus g, SaveSyncState s, [String? unit]) {
    if (_acted != g.recipe.id || s.busyRecipe != null) return null;
    final lines = [for (final m in s.messages) if (unit == null || m.startsWith('$unit:')) m];
    if (lines.isEmpty) return null;
    final one = unit != null || g.units.length < 2;
    String say(String m) {
      final i = m.indexOf(': ');
      if (i < 0 || !g.units.containsKey(m.substring(0, i))) return m;
      final what = m.substring(i + 2);
      return one ? '${what[0].toUpperCase()}${what.substring(1)}' : '${_unitLabel(m.substring(0, i))}: $what';
    }

    return (text: lines.map(say).join(' · '), ok: lines.every(_okLine.hasMatch));
  }

  static final _okLine = RegExp(r': (pushed|pulled|settled|restored from .*)$');

  /// Opens the list of a game's saves, each with its own state and action.
  /// It follows the provider, so a pull changes the row it was made from.
  Future<void> _openSaves(GameStatus g) {
    return showKitSheet<void>(
      context,
      area: _area,
      title: _label(g),
      subtitle: _count(g.units.length, 'save'),
      builder: (context) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(saveSyncProvider);
        final now = s.games.where((x) => x.recipe.id == g.recipe.id).firstOrNull ?? g;
        final anyBusy = s.busyRecipe != null || s.loading || s.signingIn;
        final units = _units(now);
        return KitPanel(children: [
          for (final (i, unit) in units.indexed)
            _SaveRow(
              autofocus: i == 0,
              label: _unitLabel(unit),
              art: s.titles[unit.toUpperCase()]?.image,
              status: _status(rowStateForUnit(now, unit, hasAccess: s.access != SyncAccess.none)),
              verb: _unitVerb(now, unit, rowStateForUnit(now, unit, hasAccess: s.access != SyncAccess.none), anyBusy: anyBusy),
              busy: s.busyRecipe == now.recipe.id,
              results: _results(now, s, unit),
              onMenu: () => showRowMenu(context, title: _unitLabel(unit), subtitle: _label(now), items: [
                RowMenuItem('Restore a backup…', anyBusy ? null : () => _restore(now, unit), icon: Icons.history),
              ]),
            ),
        ]);
      }),
    );
  }

  _Verb? _unitVerb(GameStatus g, String unit, RowState state, {required bool anyBusy}) {
    if (g.running) return null;
    VoidCallback? go(VoidCallback f) => anyBusy ? null : f;
    return switch (state) {
      RowNeedsPull() => (label: 'Download', icon: Icons.download, run: go(() => _on(g, () => _n.pull(g.recipe.id, unit: unit)))),
      RowNeedsPush() => (label: 'Upload', icon: Icons.upload, run: go(() => _on(g, () => _n.push(g.recipe.id, unit: unit)))),
      RowConflict() => switch (g.units[unit]?.plan) {
          final Diverged d => (label: 'Choose version', icon: Icons.call_split, run: go(() => _chooseVersion(g, unit, d))),
          _ => null,
        },
      _ => null,
    };
  }

  /// Y on a row, a long press, or its dots: everything else that can be done
  /// to a game, so a rare action never sits next to the common one.
  void _menu(GameStatus g, _Verb? verb, {required bool anyBusy}) {
    final VoidCallback? place = switch (g.bind) {
      NeedsDiscovery(:final places) when places.length > 1 => () => _chooseLocation(g),
      final NeedsConfirm c => () => _confirm(g, c),
      _ => null,
    };
    showRowMenu(context, title: _label(g), subtitle: '${g.source[0].toUpperCase()}${g.source.substring(1)} recipe', items: [
      if (verb != null) RowMenuItem(verb.label, verb.run, icon: verb.icon),
      RowMenuItem('Restore a backup…', anyBusy || g.units.isEmpty ? null : () => _restore(g), icon: Icons.history, subtitle: 'Put back the save a download replaced'),
      RowMenuItem('Check', () => _showCheck(g), icon: Icons.fact_check_outlined, subtitle: 'What Save Sync found here. Changes nothing.'),
      RowMenuItem('Choose location', anyBusy ? null : place, icon: Icons.folder_open, subtitle: place == null ? 'Only when the saves could be in more than one place' : null),
    ]);
  }

  // ---- The (i) ----

  InfoButton _info(SaveSyncState s) => InfoButton(
        icon: Icons.sync,
        title: 'Save Sync',
        text: "Pull a game's save before you play and push it after. Saves go to the hub: "
            '${s.googleAvailable ? 'a Retro Toolbox Saves folder in your own Google Drive, or ' : ''}'
            'a folder another app (Syncthing, FolderSync) carries between devices. '
            'Every save this replaces is kept in history on this device.',
        learnMore: Uri.parse('https://hiitsgabe.github.io/retro_toolbox/save-sync.html'),
        // Where saves go is a setup decision, so it lives here (and in
        // Settings) rather than on every visit.
        extra: (context) => Consumer(builder: (context, ref, _) => _hub(context, ref.watch(saveSyncProvider))),
      );

  Widget _hub(BuildContext context, SaveSyncState s) {
    final t = KitType.of(context);
    final busy = s.busyRecipe != null || s.loading || s.signingIn;
    final drive = s.hubKind == HubKind.drive, folder = s.hubKind == HubKind.folder;
    final access = switch (s.access) {
      SyncAccess.root => 'Access: root',
      SyncAccess.shizuku => 'Access: Shizuku (shell)',
      SyncAccess.none => null,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (drive || folder) ...[
        Row(children: [
          Icon(drive ? Icons.cloud_outlined : Icons.folder_shared_outlined, size: 18, color: t.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(drive ? 'Google Drive: ${s.googleEmail}' : s.hubFolder, style: t.body, overflow: TextOverflow.ellipsis)),
        ]),
        Wrap(spacing: 4, children: [
          if (drive && s.signInAgain) TextButton(onPressed: busy ? null : _n.signInWithGoogle, child: const Text('Sign in again')),
          if (drive) TextButton(onPressed: busy ? null : _n.signOut, child: const Text('Sign out')),
          TextButton(onPressed: busy ? null : () => _chooseHub(context), child: const Text('Change')),
        ]),
        if (folder) Text('Folder hub: "up to date" means up to date with what this folder holds right now.', style: t.subtitle),
      ],
      if (access != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(access, style: t.subtitle)),
    ]);
  }

  // ---- The screen ----

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(saveSyncProvider);
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final busy = s.busyRecipe != null || s.loading || s.signingIn;
    _setupIfUnset(s.hubKind);
    // A game this handheld does not have is not a row to act on, so it folds
    // into its own group below instead of sitting among the live ones. It
    // still reaches the hub report, so other devices keep seeing it.
    final shown = s.games.where((g) => g.bind is! NotInstalled).toList();
    final absent = s.games.where((g) => g.bind is NotInstalled).toList();
    final hubSet = s.hubKind == HubKind.folder || s.hubKind == HubKind.drive;
    final t = KitType.of(context);

    final rows = <Widget>[];
    _Verb? focusedVerb;
    GameStatus? focused;
    for (final (i, g) in shown.indexed) {
      final state = rowStateFor(g, hasAccess: s.access != SyncAccess.none);
      final verb = _verb(g, state, anyBusy: busy);
      final multi = _multi(g);
      if (g.recipe.id == _focused) {
        focused = g;
        focusedVerb = verb;
      }
      final status = g.running ? (word: 'Close the game first', tone: KitTone.warning, detail: null) : (multi ? _multiStatus(g, state) : _status(state));
      rows.add(_GameRow(
        key: ValueKey('save-sync-row-${g.recipe.id}'),
        label: _label(g),
        icon: s.appInfo[g.recipe.packages.first]?.icon,
        status: status,
        verb: verb,
        multi: multi,
        dim: state is RowBlocked || state is RowNotInstalled,
        busy: s.busyRecipe == g.recipe.id,
        results: _results(g, s),
        autofocus: i == 0,
        onOpen: multi ? () => _openSaves(g) : () => _showCheck(g),
        onMenu: () => _menu(g, verb, anyBusy: busy),
        onFocus: (on) {
          if (on && _focused != g.recipe.id) setState(() => _focused = g.recipe.id);
          if (!on && _focused == g.recipe.id) setState(() => _focused = null);
        },
      ));
    }

    final panels = <Widget>[
      if (s.access == SyncAccess.none)
        StatusPanel.missingRequirement(
          key: const ValueKey('save-sync-access'),
          title: 'No access to game folders',
          detail: s.shizukuRunning ? 'Shizuku is running. Allow Retro Toolbox to use it.' : 'Start Shizuku (wireless debugging, or root), then come back and refresh.',
          actionLabel: s.shizukuRunning ? 'Grant Shizuku access' : 'Retry',
          onAction: busy ? null : (s.shizukuRunning ? _n.requestShizuku : _n.refresh),
          // The handheld has no browser to open it in.
          linkLabel: Handheld.current ? null : 'How to set up Shizuku',
          onLink: () => openLink(Uri.parse('https://hiitsgabe.github.io/retro_toolbox/save-sync.html#shizuku')),
        ),
      if (s.hubKind == HubKind.drive && s.signInAgain)
        StatusPanel.missingRequirement(
          title: s.error ?? 'Sign in to Google again.',
          detail: s.googleEmail.isEmpty ? null : s.googleEmail,
          actionLabel: 'Sign in again',
          onAction: busy ? null : _n.signInWithGoogle,
        )
      else if (s.error != null)
        StatusPanel.error(line: s.error!),
      if (s.signInError != null && s.hubKind != HubKind.none) StatusPanel.error(line: s.signInError!),
    ];

    final folds = [
      // Not hidden, just folded away: a game that vanished from the list
      // reads as lost data, especially when the hub says it is covered.
      if (absent.isNotEmpty)
        OptionExpander(title: 'Not on this device (${absent.length})', children: [
          for (final g in absent)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(_label(g), style: t.body)),
        ]),
      if (s.recipeProblems.isNotEmpty)
        OptionExpander(title: 'Recipes that did not load (${s.recipeProblems.length})', children: [
          for (final e in s.recipeProblems.entries)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: KitRowText(title: e.key, subtitle: e.value)),
        ]),
    ];

    final empty = shown.isEmpty && !s.loading && hubSet
        ? EmptyState(
            icon: Icons.sync,
            glyph: PixelIcons.saves,
            line: s.games.isEmpty ? 'No apps yet. Use Add an app to choose which games sync.' : 'Nothing here is set up to sync yet.',
          )
        : null;

    final add = KitAction('Add an app', hubSet && !busy ? _addApps : null, icon: Icons.add, button: PadButton.select);
    // With a pad, Start is the focused row's action and the bar says which.
    // On touch nothing has focus: each row's own button is the way, and the
    // bar keeps Add an app.
    final rowFocused = pad && focused != null;
    final bar = ActionBar(
      primary: rowFocused ? (focusedVerb == null ? null : KitAction(focusedVerb.label, focusedVerb.run, icon: focusedVerb.icon)) : (hubSet ? add : null),
      secondary: rowFocused && hubSet ? add : null,
      hints: [
        if (focused != null) KitHint(PadButton.a, _multi(focused) ? 'Saves' : 'Check'),
        if (focused != null) const KitHint(PadButton.y, 'Menu'),
      ],
      summary: rowFocused ? _label(focused) : null,
    );

    final subtitle = switch (s.hubKind) {
      HubKind.drive => 'Drive · ${s.googleEmail}',
      HubKind.folder => 'Folder · ${_count(shown.length, 'game')}',
      _ => null,
    };

    return KitScaffold(
      title: 'Save Sync',
      subtitle: subtitle,
      icon: Icons.sync,
      glyph: PixelIcons.saves,
      area: _area,
      info: _info(s),
      actions: [IconButton(tooltip: 'Refresh', onPressed: busy ? null : _n.refresh, icon: const Icon(Icons.refresh))],
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // A fixed slot, so a refresh never moves the list.
        SizedBox(height: 3, child: s.loading || s.signingIn ? const LinearProgressIndicator(minHeight: 3) : null),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 5, bottom: 8),
            children: [
              for (final p in panels) Padding(padding: const EdgeInsets.only(bottom: kitGap), child: p),
              ...rows,
              if (empty != null) empty,
              if (folds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: kitGap - 4), child: KitPanel(children: folds)),
            ],
          ),
        ),
      ]),
      actionBar: bar,
    );
  }
}

/// One game: its icon, its name, its state in a coloured word, and its one
/// action. One focus stop: A or a tap opens its saves (several) or its Check,
/// Start runs the action, Y or a long press opens the menu. The buttons are
/// for touch and stay out of the d-pad's way.
class _GameRow extends StatelessWidget {
  const _GameRow({
    super.key,
    required this.label,
    required this.icon,
    required this.status,
    required this.verb,
    required this.multi,
    required this.dim,
    required this.busy,
    required this.results,
    required this.autofocus,
    required this.onOpen,
    required this.onMenu,
    required this.onFocus,
  });

  final String label;

  /// What Android shows for this app, when it could be read.
  final Uint8List? icon;
  final _Status status;
  final _Verb? verb;
  final bool multi;
  final bool dim;

  /// This row is the one working.
  final bool busy;

  /// What the last action on this game said.
  final _Result? results;
  final bool autofocus;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final portrait = DeviceClass.of(context) == DeviceClass.portrait;
    final verb = this.verb;
    final Widget trailing;
    if (busy) {
      trailing = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Syncing', style: t.subtitle),
        ]),
      );
    } else if (multi) {
      trailing = Icon(Icons.chevron_right, size: 22, color: t.muted);
    } else if (verb == null) {
      trailing = const SizedBox.shrink();
    } else if (portrait) {
      trailing = ExcludeFocus(child: IconButton.filledTonal(tooltip: verb.label, onPressed: verb.run, icon: Icon(verb.icon, size: 20)));
    } else {
      trailing = ExcludeFocus(
        child: FilledButton.icon(
          onPressed: verb.run,
          icon: Icon(verb.icon, size: 18),
          label: Text(verb.label),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      );
    }
    return RowMenuTarget(
      onMenu: onMenu,
      child: Actions(
        actions: {
          // Start is this row's action while it has focus; nothing at all
          // when it has none (never the bar's Add an app).
          PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (_) {
            verb?.run?.call();
            return null;
          }),
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: k.panel,
            shape: RoundedRectangleBorder(borderRadius: kitRowRadius(k), side: BorderSide(color: k.panelLine)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              autofocus: autofocus,
              borderRadius: kitRowRadius(k),
              onTap: onOpen,
              onFocusChange: onFocus,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                child: Row(children: [
                  Opacity(opacity: dim ? 0.5 : 1, child: _Thumb(icon: icon)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Opacity(
                      opacity: dim ? 0.7 : 1,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(label, style: t.row, maxLines: 1, overflow: TextOverflow.ellipsis),
                        _StatusLine(status: status),
                        if (results case final r?) _ResultLine(result: r),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  trailing,
                  ExcludeFocus(
                    child: IconButton(
                      tooltip: 'More',
                      onPressed: onMenu,
                      icon: Icon(Icons.more_vert, size: 20, color: t.muted),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The state word in its colour, then the detail, muted.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final _Status status;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final detail = status.detail;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: status.word, style: TextStyle(color: kitToneColor(context, status.tone), fontWeight: FontWeight.w600)),
        if (detail != null && detail.isNotEmpty) TextSpan(text: ' · $detail'),
      ]),
      style: t.subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// What the last action said, in the row it was about: green when every
/// line is a save that moved, amber when one is not.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});

  final _Result result;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final ok = result.ok;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(children: [
        Icon(ok ? Icons.check : Icons.info_outline, size: 14, color: ok ? t.k.success : t.k.warning),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            result.text,
            key: const ValueKey('save-sync-result'),
            style: t.subtitle.copyWith(color: ok ? t.k.success : t.k.warning),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

/// One save inside a game that keeps several: a farm, or one emulated title.
/// Carries its own state and its own action. One focus stop: A or a tap runs
/// the action (or opens its menu when it has none), Y or a long press opens
/// the menu.
class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.autofocus,
    required this.label,
    this.art,
    required this.status,
    required this.verb,
    required this.busy,
    required this.results,
    required this.onMenu,
  });

  final bool autofocus;
  final String label;

  /// Art for this save's game, when the catalog had some.
  final String? art;
  final _Status status;
  final _Verb? verb;
  final bool busy;
  final _Result? results;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final verb = this.verb;
    return RowMenuTarget(
      onMenu: onMenu,
      child: KitRow(
        autofocus: autofocus,
        onTap: verb?.run ?? onMenu,
        child: Row(children: [
          if (art case final url?) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                // Art is decoration: a slow or dead URL must never hold up or
                // disfigure the row that carries the verb.
                placeholder: (_, __) => const SizedBox(width: 32, height: 32),
                errorWidget: (_, __, ___) => const SizedBox(width: 32, height: 32),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: t.row, maxLines: 1, overflow: TextOverflow.ellipsis),
              _StatusLine(status: status),
              if (results case final r?) _ResultLine(result: r),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (verb != null)
            ExcludeFocus(
              child: OutlinedButton.icon(
                onPressed: verb.run,
                icon: Icon(verb.icon, size: 18),
                label: Text(verb.label),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The app's own icon in the house thumbnail frame. No icon (no launcher
/// activity, or any run off Android) falls back to a neutral glyph in the
/// same frame, so rows never change height.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.icon});

  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final t = KitType.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 8).toDouble()),
        border: Border.all(color: k.panelLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: icon != null
          ? Image.memory(icon!, width: 40, height: 40, gaplessPlayback: true, filterQuality: FilterQuality.medium)
          : Icon(Icons.videogame_asset_outlined, size: 22, color: t.muted),
    );
  }
}
