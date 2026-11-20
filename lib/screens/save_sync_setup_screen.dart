import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// The two decisions a handheld needs before it can sync anything: where the
/// saves go, and which of the apps already named there apply here.
///
/// Its own screen rather than cards on the list, because a first run is a
/// sequence with an end, and because the list behind it has nothing to show
/// until both answers exist.
/// Where the hub picker opens for [dir]. The default folder only exists once a hub has been made in it, and the
/// in-app browser cannot open a missing folder nor make one, so it is made here to keep the default pickable.
/// Without permission to make it, the picker opens at its parent instead.
Future<String> hubPickerStart(String dir) async {
  try {
    await Directory(dir).create(recursive: true);
    return dir;
  } on FileSystemException {
    return p.dirname(dir);
  }
}

class SaveSyncSetupScreen extends ConsumerStatefulWidget {
  const SaveSyncSetupScreen({super.key, this.pickFolder});

  /// Tests hand in their own picker; null opens the one Save Sync uses to change the hub.
  final Future<String?> Function(BuildContext context, String initialDir)? pickFolder;

  @override
  ConsumerState<SaveSyncSetupScreen> createState() => _SaveSyncSetupScreenState();
}

class _SaveSyncSetupScreenState extends ConsumerState<SaveSyncSetupScreen> {
  static const _steps = ['Where', 'Apps'];

  bool get _onStep2 => ref.read(saveSyncProvider).hubKind != HubKind.none;

  /// The row chosen on Where; null: Google Drive when the build has it.
  HubKind? _choice;

  /// The step last built: the hub arriving moves to Apps, and a pad's focus
  /// goes with it.
  int? _shown;

  /// Holds the step's body, so a new step can take focus from the button
  /// that moved to it.
  final _body = FocusNode(debugLabel: 'save-sync-setup-step');

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _focusStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      _body.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(saveSyncProvider);
    final n = ref.read(saveSyncProvider.notifier);
    final step = s.hubKind == HubKind.none || s.hubKind == HubKind.unknown ? 0 : 1;
    if (_shown != null && _shown != step) _focusStep();
    _shown = step;
    final drive = s.googleAvailable && (_choice ?? HubKind.drive) == HubKind.drive;
    final KitAction primary;
    if (step == 0) {
      primary = drive
          ? KitAction('Sign in with Google', s.signingIn ? null : n.signInWithGoogle)
          : KitAction('Use a folder', s.signingIn ? null : () => _pickHub(n.defaultHubFolder));
    } else {
      primary = KitAction('Open Save Sync', s.loading ? null : _done);
    }
    return WizardShell(
      name: 'Save Sync setup',
      step: step,
      count: _steps.length,
      stepName: _steps[step],
      icon: Icons.sync,
      glyph: PixelIcons.saves,
      area: AppArea.saves,
      info: const InfoButton(
        icon: Icons.sync,
        title: 'Save Sync setup',
        text: 'Google Drive keeps your saves in a folder in your own Drive, and Retro Toolbox sees only the files it puts there. '
            'A folder works without Google: another app, such as Syncthing or FolderSync, carries it between your handhelds. '
            'Then Save Sync lists the apps the hub already covers.',
      ),
      body: Focus(
        focusNode: _body,
        skipTraversal: true,
        canRequestFocus: false,
        child: step == 0 ? _whereStep(context, s, drive) : _appsStep(context, s),
      ),
      onNext: primary.onPressed,
      nextLabel: primary.label,
      // A desktop has no back key: the first question can be put off.
      leaveLabel: step == 0 ? 'Not now' : null,
    );
  }

  Widget _whereStep(BuildContext context, SaveSyncState s, bool drive) {
    final t = KitType.of(context);
    final pick = s.signingIn ? null : (HubKind k) => setState(() => _choice = k);
    return KitColumns(
      start: [
        Padding(padding: const EdgeInsets.fromLTRB(2, 2, 2, 0), child: Text('Where should saves go?', style: t.row.copyWith(fontSize: t.size(16)))),
        OptionList(children: [
          if (s.googleAvailable)
            OptionChoice<HubKind>(
              autofocus: true,
              title: 'Google Drive',
              subtitle: 'A folder in your own Drive. Retro Toolbox sees only the files it puts there.',
              value: HubKind.drive,
              groupValue: drive ? HubKind.drive : HubKind.folder,
              onSelected: pick,
            ),
          OptionChoice<HubKind>(
            autofocus: !s.googleAvailable,
            title: 'A folder',
            subtitle: 'Works without Google: another app, such as Syncthing, carries it between your handhelds.',
            value: HubKind.folder,
            groupValue: drive ? HubKind.drive : HubKind.folder,
            onSelected: pick,
          ),
        ]),
        // Under the choices, not beside them: the list keeps its width
        // whether or not there is something to say.
        if (s.signingIn) const StatusPanel.working(items: [WorkItem('Signing in to Google')]),
        if (s.signInError != null) StatusPanel.error(line: s.signInError!),
      ],
    );
  }

  Widget _appsStep(BuildContext context, SaveSyncState s) {
    final t = KitType.of(context);
    if (s.loading) return KitColumns(start: const [StatusPanel.working(items: [WorkItem('Reading the hub…')])]);
    if (s.error != null) {
      return KitColumns(start: [
        StatusPanel.missingRequirement(
          title: "Couldn't read the hub",
          detail: s.error,
          actionLabel: 'Pick the folder again',
          onAction: () => _pickHub(s.hubFolder.isEmpty ? ref.read(saveSyncProvider.notifier).defaultHubFolder : s.hubFolder),
        ),
      ]);
    }
    if (s.games.isEmpty) {
      return const EmptyState(icon: Icons.inbox_outlined, glyph: PixelIcons.saves, line: 'This hub is empty. Open Save Sync and add the first app.');
    }

    final here = [for (final g in s.games) if (g.bind is! NotInstalled) g];
    final elsewhere = [for (final g in s.games) if (g.bind is NotInstalled) g];
    String name(GameStatus g) => s.appInfo[g.recipe.packages.first]?.label ?? g.recipe.name;
    Widget row(String title, String subtitle) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: KitRowText(title: title, subtitle: subtitle),
        );

    return KitColumns(
      start: [
        StatusPanel.done(summary: 'This hub already covers ${s.games.length} app${s.games.length == 1 ? '' : 's'}.'),
        // Plain rows: a hub app applies to every device that has it, and there
        // is no per-device opt-out a tick could set.
        if (here.isNotEmpty) ...[
          KitLabel('Will apply here (${here.length})'),
          KitPanel(children: [for (final g in here) row(name(g), g.recipe.packages.first)]),
        ],
      ],
      end: [
        // Shown rather than filtered away: a handheld that quietly drops apps
        // leaves the owner wondering what happened to them.
        if (elsewhere.isNotEmpty) ...[
          KitLabel('Not on this device (${elsewhere.length})'),
          Opacity(opacity: 0.55, child: KitPanel(children: [for (final g in elsewhere) row(name(g), g.recipe.packages.first)])),
        ],
        if (s.recipeProblems.isNotEmpty) ...[
          KitLabel('Needs a look (${s.recipeProblems.length})'),
          KitPanel(children: [for (final e in s.recipeProblems.entries) row(e.key, e.value)]),
        ],
        if (elsewhere.isEmpty && s.recipeProblems.isEmpty) Text('Every app the hub covers is on this device.', style: t.subtitle),
      ],
    );
  }

  /// A cancelled picker leaves the step as it was.
  Future<void> _pickHub(String initialDir) async {
    final path = await (widget.pickFolder ?? _systemPicker)(context, initialDir);
    if (path != null && mounted) await ref.read(saveSyncProvider.notifier).setHubFolder(path);
  }

  static Future<String?> _systemPicker(BuildContext context, String initialDir) async {
    final start = await hubPickerStart(initialDir);
    if (!context.mounted) return null;
    return pickDirectory(context, title: 'Choose the hub folder', initialDir: start);
  }

  void _done() {
    if (!mounted) return;
    Navigator.of(context).pop(_onStep2);
  }
}
