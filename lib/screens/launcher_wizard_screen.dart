import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/launcher_app_picker_screen.dart';
import 'package:retro_toolbox/screens/launcher_console_picker_screen.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/launcher_wizard_plan.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/services/launcher/manual_recipes.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

enum _Step { emulators, systems, folders, home, done }

/// The desktop file picker of "Add an emulator", as a provider tests can set.
final pickExecutableProvider = Provider<Future<String?> Function(BuildContext context)>((ref) => (context) => pickFile(context, title: 'Choose the emulator'));

/// Launcher mode's setup: which emulators are installed, which one opens
/// each console with games on disk, the folder grants a `saf` emulator needs
/// (Android), whether Retro Toolbox is the home screen (Android), then a
/// summary. Only Finish saves a choice; the detection step 1 runs is a
/// cache, kept even when the wizard is left.
class LauncherWizardScreen extends ConsumerStatefulWidget {
  const LauncherWizardScreen({super.key});

  @override
  ConsumerState<LauncherWizardScreen> createState() => _LauncherWizardState();
}

/// One console row of the Systems step: the console, its art slug and name,
/// its library folder, and the emulators that open it.
typedef _Row = ({Console console, String? slug, String dir, List<DetectedEmulator> covering});

class _LauncherWizardState extends ConsumerState<LauncherWizardScreen> {
  int _index = 0;
  bool _detecting = false;

  /// The label of the app being added while its recipe test runs.
  String? _testing;

  /// Why the last app picked to add was not added.
  String? _addProblem;

  /// What the user picked on a Systems row, by console id; a row not in it
  /// shows [preselect]'s choice.
  final _chosen = <String, LaunchChoice>{};

  /// The folder-access rows the user ticked. Never ticked for them: another
  /// app's grants cannot be read.
  final _done = <String>{};

  /// The Home screen switch, once flipped; until then it shows the saved
  /// `home`.
  bool? _homePick;

  final _stepFocus = FocusNode(debugLabel: 'launcher-step');

  bool get _android => ref.read(launcherOsProvider) == 'android';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterStep(_Step.emulators);
    });
  }

  @override
  void dispose() {
    _stepFocus.dispose();
    super.dispose();
  }

  /// Work a step starts on arrival: Emulators detects.
  void _enterStep(_Step step) {
    if (step == _Step.emulators) _detect();
  }

  Future<void> _detect() async {
    setState(() => _detecting = true);
    try {
      await ref.read(detectEmulatorsProvider)();
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// "Add an emulator": an app (Android) or an executable (desktop) the user
  /// says is an emulator, paired with a recipe or with none. Saved, then
  /// detected like the rest, so its row comes with what a detection brings.
  /// Left anywhere on the way, nothing changes.
  Future<void> _addEmulator(LauncherSession session) async {
    setState(() => _addProblem = null);
    final manual = _android ? await _pickAndroid(session) : await _pickDesktop();
    if (manual == null || !mounted) return;
    setState(() => _detecting = true);
    try {
      await ref.read(addManualEmulatorProvider)(manual);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<ManualEmulator?> _pickAndroid(LauncherSession session) async {
    final app = await Navigator.of(context).push<({String package, AppInfo info})>(
      MaterialPageRoute(builder: (_) => LauncherAppPickerScreen(exclude: {for (final d in session.detected) d.variant})),
    );
    if (app == null || !mounted) return null;
    final label = app.info.label;
    setState(() => _testing = label);
    final file = await ref.read(launchPresetsProvider.future);
    final channel = ref.read(launcherChannelProvider);
    final recipes = await androidRecipesFor(channel, file.presets, app.package);
    final activity = await channel.viewActivity(app.package);
    if (!mounted) return null;
    setState(() => _testing = null);
    // A generic launch needs an activity to send the file to: without one it
    // is not offered.
    final recipe = await _chooseRecipe(label, recipes, generic: activity != null);
    if (recipe == null || !mounted) return null;
    return _withSystems(ManualEmulator(variant: app.package, label: label, recipe: recipe, activity: recipe == ManualEmulator.generic ? activity : null));
  }

  /// The recipes come with the ones whose find rules name the picked file
  /// first; "Just open the file" is always there, since any executable can
  /// be handed the path.
  Future<ManualEmulator?> _pickDesktop() async {
    final os = ref.read(launcherOsProvider);
    final picked = await ref.read(pickExecutableProvider)(context);
    if (picked == null || !mounted) return null;
    final exe = await executableFor(picked, os);
    final file = await ref.read(launchPresetsProvider.future);
    if (!mounted) return null;
    final label = p.basenameWithoutExtension(picked);
    final recipe = await _chooseRecipe(label, desktopRecipesFor(file.presets, os, picked), generic: true);
    if (recipe == null || !mounted) return null;
    return _withSystems(ManualEmulator(variant: exe, label: label, recipe: recipe));
  }

  /// A generic [m] with the consoles the user ticks for it; one with a recipe
  /// as it is. Null when the console list is left.
  Future<ManualEmulator?> _withSystems(ManualEmulator m) async {
    if (!m.isGeneric) return m;
    final ticked = await Navigator.of(context).push<List<String>>(MaterialPageRoute(builder: (_) => LauncherConsolePickerScreen(label: m.label)));
    if (ticked == null || ticked.isEmpty) return null;
    return ManualEmulator(variant: m.variant, label: m.label, recipe: m.recipe, systems: ticked, activity: m.activity);
  }

  /// The ways to open an app being added: each recipe that fits it, then
  /// "Just open the file" when [generic], the first focused even when it is
  /// the only one, so the pick is always the user's. Null when the menu is
  /// closed, or when nothing fits (the step then says so).
  Future<String?> _chooseRecipe(String label, List<LaunchPreset> recipes, {required bool generic}) async {
    if (recipes.isEmpty && !generic) {
      setState(() => _addProblem = '$label cannot be opened by Retro Toolbox.');
      return null;
    }
    String? picked;
    await showRowMenu(context, title: label, subtitle: 'Opens games', items: [
      for (final r in recipes) RowMenuItem('Opens like ${r.name}', () => picked = r.id, subtitle: r.verified ? null : 'not tested'),
      if (generic) RowMenuItem('Just open the file', () => picked = ManualEmulator.generic, subtitle: 'Hands it the game file, for an app no recipe fits'),
    ]);
    return picked;
  }

  /// The consoles with games on disk, in catalog order; null while any of
  /// them is still being looked at.
  List<_Row>? _rows(LauncherSession session) {
    final settings = ref.read(settingsProvider.notifier);
    final rows = <_Row>[];
    for (final c in ref.watch(appStateProvider.select((s) => s.consolesList))) {
      final onDisk = ref.watch(gamesOnDiskProvider(c.id));
      if (onDisk.isLoading) return null;
      if (onDisk.valueOrNull != true) continue;
      final slug = ref.watch(gameSystemProvider(c.id)).slug;
      rows.add((console: c, slug: slug, dir: settings.getDownloadDir(c.id), covering: session.covering(slug)));
    }
    return rows;
  }

  LaunchChoice? _pick(LauncherSession session, _Row row) =>
      _chosen[row.console.id] ?? preselect(session, row.slug, ref.read(launchConfigProvider).defaults[row.console.id]);

  /// Every row's choice, the ones Finish saves.
  Map<String, LaunchChoice> _picks(LauncherSession session, List<_Row> rows) => {
        for (final r in rows)
          if (_pick(session, r) != null) r.console.id: _pick(session, r)!,
      };

  /// The emulators that need a folder grant, each with the folders of the
  /// consoles it was picked for. Android only.
  Map<DetectedEmulator, Set<String>> _folderGrants(LauncherSession session, List<_Row> rows) {
    if (!_android) return const {};
    final out = <DetectedEmulator, Set<String>>{};
    for (final r in rows) {
      final choice = _pick(session, r);
      final preset = choice == null ? null : session.preset(choice.presetId);
      final detected = choice == null ? null : session.detectedFor(choice.presetId);
      final system = preset?.systems[r.slug];
      if (preset == null || detected == null || system == null || !needsFolderAccess(preset, detected, system)) continue;
      out.putIfAbsent(detected, () => <String>{}).add(r.dir);
    }
    return out;
  }

  List<_Step> _steps(LauncherSession? session, List<_Row>? rows) => [
        _Step.emulators,
        _Step.systems,
        if (session != null && rows != null && _folderGrants(session, rows).isNotEmpty) _Step.folders,
        if (ref.watch(homeRoleAvailableProvider)) _Step.home,
        _Step.done,
      ];

  bool _canAdvance(_Step step, LauncherSession? session, List<_Row>? rows) => switch (step) {
        _Step.emulators => !_detecting && _testing == null && session != null && session.detected.isNotEmpty,
        // No console with games yet still lets the mode on: a game downloaded
        // later opens in the one emulator that covers it, or asks which.
        _Step.systems => session != null && rows != null && (rows.isEmpty || _picks(session, rows).isNotEmpty),
        _Step.folders || _Step.home => true,
        _Step.done => session != null && rows != null,
      };

  void _next(List<_Step> steps) {
    setState(() => _index++);
    _enterStep(steps[_index]);
    _focusStep();
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _focusStep();
  }

  Future<void> _finish(LauncherSession session, List<_Row> rows, List<_Step> steps, {required bool wantHome}) async {
    await ref.read(launchConfigProvider.notifier).finishSetup(_picks(session, rows));
    // After the defaults: the home screen opens the games they launch. Android
    // is asked only when the switch changed what it was.
    if (steps.contains(_Step.home) && mounted) {
      final role = ref.read(homeRoleProvider);
      final now = ref.read(launchConfigProvider).home;
      if (wantHome && !now) await role.turnOn();
      if (!wantHome && now) await role.turnOff();
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// With a pad, onto the new step's first control, as the other wizards do.
  void _focusStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      _stepFocus.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull?.requestFocus();
    });
  }

  static String _label(_Step s) => switch (s) {
        _Step.emulators => 'Emulators',
        _Step.systems => 'Systems',
        _Step.folders => 'Folder access',
        _Step.home => 'Home screen',
        _Step.done => 'Done',
      };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(launcherSessionProvider).valueOrNull;
    final rows = session == null ? null : _rows(session);
    final steps = _steps(session, rows);
    // A pick that drops the Folder access step while on it moves to Done.
    if (_index >= steps.length) _index = steps.length - 1;
    final step = steps[_index];
    final last = step == _Step.done;
    final advance = _canAdvance(step, session, rows);
    // The home app cannot move to the bottom display (spec, Dual screen), so
    // under Main on bottom the switch is off whatever it was.
    final mainOnBottom = ref.watch(dualScreenProvider.select((s) => s.mode)) == DualScreenMode.mainOnBottom;
    final wantHome = !mainOnBottom && (_homePick ?? ref.watch(launchConfigProvider.select((c) => c.home)));
    return WizardShell(
      name: 'Launcher mode',
      step: _index,
      count: steps.length,
      stepName: _label(step),
      icon: Icons.sports_esports,
      glyph: PixelIcons.games,
      area: AppArea.games,
      info: const InfoButton(
        icon: Icons.sports_esports,
        title: 'Launcher mode',
        text: 'Retro Toolbox opens the games you have in an emulator. This finds the emulators on this device and lets you pick one for each '
            'console. A game can still open in another one through Open with on its page.',
      ),
      body: Focus(
        focusNode: _stepFocus,
        skipTraversal: true,
        canRequestFocus: false,
        child: switch (step) {
          _Step.emulators => _emulatorsStep(context, session),
          _Step.systems => _systemsStep(context, session, rows),
          _Step.folders => _foldersStep(context, session!, rows!),
          _Step.home => _homeStep(context, on: wantHome, locked: mainOnBottom),
          _Step.done => _doneStep(context, session, rows, home: steps.contains(_Step.home) && wantHome),
        },
      ),
      onNext: !advance ? null : (last ? () => _finish(session!, rows!, steps, wantHome: wantHome) : () => _next(steps)),
      nextLabel: last ? 'Finish' : 'Next',
      // B steps back; on the first step it leaves, with nothing saved.
      onBack: _index > 0 ? _back : null,
      leaveLabel: 'Cancel',
    );
  }

  Widget _emulatorsStep(BuildContext context, LauncherSession? session) {
    final t = KitType.of(context);
    final detected = session?.detected ?? const <DetectedEmulator>[];
    final busy = _detecting || _testing != null;
    final Widget found;
    if (_testing != null) {
      found = StatusPanel.working(items: [WorkItem('Testing $_testing')]);
    } else if (_detecting || session == null) {
      found = const StatusPanel.working(items: [WorkItem('Looking for emulators')]);
    } else if (detected.isEmpty) {
      final slugs = {
        for (final c in ref.watch(appStateProvider.select((s) => s.consolesList)))
          if (ref.watch(gamesOnDiskProvider(c.id)).valueOrNull == true) ref.watch(gameSystemProvider(c.id)).slug,
      }.whereType<String>().toSet();
      final names = [for (final p in suggestEmulators(session.presets, slugs, ref.read(launcherOsProvider))) p.name];
      found = KitPanel(padding: const EdgeInsets.all(12), children: [
        Text(names.isEmpty ? 'No emulator found.' : 'No emulator found. Install ${_list(names)}, then Detect again.', style: t.body),
      ]);
    } else {
      found = OptionList(children: [for (final d in detected) _EmulatorRow(emulator: d, verified: session.preset(d.presetId)?.verified ?? false)]);
    }
    return KitColumns(
      start: [
        const KitLabel('On this device'),
        found,
        if (_addProblem != null) KitPanel(padding: const EdgeInsets.all(12), children: [Text(_addProblem!, style: t.body)]),
        OptionList(children: [
          OptionAction(title: 'Detect again', subtitle: 'After installing or removing an emulator', autofocus: true, onTap: busy ? null : _detect),
          OptionAction(
            key: const ValueKey('launcher-add'),
            title: 'Add an emulator',
            subtitle: 'For one that was not found',
            onTap: busy || session == null ? null : () => _addEmulator(session),
          ),
        ]),
      ],
      end: [
        const KitLabel('Not tested'),
        Text('An emulator tagged "not tested" has not been tried with this app on a device yet. It may still work.', style: t.subtitle),
      ],
    );
  }

  Widget _systemsStep(BuildContext context, LauncherSession? session, List<_Row>? rows) {
    final t = KitType.of(context);
    if (session == null || rows == null) return const KitColumns(start: [StatusPanel.working(items: [WorkItem('Looking for games')])]);
    if (rows.isEmpty) {
      return KitColumns(start: [
        KitPanel(padding: const EdgeInsets.all(12), children: [
          Text('No games in your library folders yet. Finish still turns launcher mode on; set a console\'s emulator later in Settings or on '
              'the console\'s page.', style: t.body),
        ]),
      ]);
    }
    final primary = _android ? ref.watch(primaryStorageRootProvider).valueOrNull : null;
    final allFiles = <DetectedEmulator>{};
    final children = <Widget>[];
    for (final (i, r) in rows.indexed) {
      final choice = _pick(session, r);
      final emulator = choice == null ? null : session.detectedFor(choice.presetId);
      final preset = choice == null ? null : session.preset(choice.presetId);
      final system = preset?.systems[r.slug];
      if (_android && emulator != null && emulator.manageGrant) allFiles.add(emulator);
      final private = primary != null && isAppPrivateDir(r.dir, primary);
      children.add(OptionAction(
        key: ValueKey('launcher-system-${r.console.id}'),
        autofocus: i == 0,
        title: r.console.name,
        subtitle: private ? 'Other apps cannot read this folder. Move your library out of Android/data' : null,
        value: emulator?.label ?? 'No emulator found',
        onTap: r.covering.isEmpty ? null : () => _chooseEmulator(session, r),
      ));
      if (preset != null && preset.usesRetroarchCore && system != null && system.cores.isNotEmpty) {
        final core = choice!.core ?? system.cores.first;
        children.add(OptionAction(
          key: ValueKey('launcher-core-${r.console.id}'),
          title: '${r.console.name} core',
          // Android cannot see which cores RetroArch has.
          subtitle: _android ? 'If the screen stays black, install the $core core in RetroArch' : null,
          value: core,
          onTap: system.cores.length < 2 ? null : () => _chooseCore(r, choice, system),
        ));
      }
    }
    return KitColumns(
      start: [
        const KitLabel('One emulator per console'),
        OptionList(children: children),
        if (allFiles.isNotEmpty)
          OptionList(children: [
            for (final d in allFiles)
              OptionAction(
                title: 'Allow all files access for ${d.label}',
                subtitle: 'It opens your games by their path',
                onTap: () => ref.read(launcherChannelProvider).openAllFilesAccess(d.variant),
              ),
          ]),
      ],
      end: [
        const KitLabel('Only consoles with games'),
        Text('Consoles show here once their folder holds a game. A game can still open in another emulator through Open with.', style: t.subtitle),
      ],
    );
  }

  Future<void> _chooseEmulator(LauncherSession session, _Row row) => showRowMenu(
        context,
        title: row.console.name,
        subtitle: 'Opens its games',
        items: [
          for (final d in row.covering)
            RowMenuItem(
              d.label,
              () => setState(() => _chosen[row.console.id] = d.choice),
              subtitle: session.preset(d.presetId)?.verified ?? false ? null : 'not tested',
            ),
        ],
      );

  Future<void> _chooseCore(_Row row, LaunchChoice choice, PresetSystem system) => showRowMenu(
        context,
        title: '${row.console.name} core',
        items: [
          for (final core in system.cores)
            RowMenuItem(core, () => setState(() => _chosen[row.console.id] = LaunchChoice(presetId: choice.presetId, variant: choice.variant, core: core))),
        ],
      );

  Widget _foldersStep(BuildContext context, LauncherSession session, List<_Row> rows) {
    final t = KitType.of(context);
    final grants = _folderGrants(session, rows);
    return KitColumns(
      start: [
        const KitLabel('Give each emulator its folder'),
        for (final (i, MapEntry(key: d, value: folders)) in grants.entries.indexed)
          OptionList(children: [
            OptionAction(
              key: ValueKey('launcher-folder-${d.presetId}'),
              autofocus: i == 0,
              title: 'Inside ${d.label}, give access to ${folders.length == 1 ? folders.single : 'these folders'}',
              subtitle: folders.length == 1 ? null : folders.join('\n'),
              value: 'Open ${d.label}',
              onTap: () => ref.read(launcherChannelProvider).openApp(d.variant),
            ),
            OptionToggle(
              title: 'Done',
              subtitle: 'Tick it yourself: this app cannot see what ${d.label} was given',
              value: _done.contains(d.presetId),
              onChanged: (v) => setState(() => v ? _done.add(d.presetId) : _done.remove(d.presetId)),
            ),
          ]),
      ],
      end: [
        const KitLabel('Why'),
        Text(
          'These emulators open a game through the folder it is in, and only once you allow that folder inside the emulator. '
          'Without it the emulator says it cannot open the file.',
          style: t.subtitle,
        ),
      ],
    );
  }

  Widget _homeStep(BuildContext context, {required bool on, required bool locked}) {
    final t = KitType.of(context);
    return KitColumns(
      start: [
        const KitLabel('Home screen'),
        OptionList(children: [
          OptionToggle(
            key: const ValueKey('launcher-home'),
            autofocus: true,
            title: homeSwitchTitle,
            subtitle: 'The Home button opens your games',
            value: on,
            lockedReason: locked ? homeLockedReason : null,
            onChanged: (v) => setState(() => _homePick = v),
          ),
        ]),
      ],
      end: [
        const KitLabel('After Finish'),
        Text('Android asks which app is the home screen. Change it later in Settings > Launcher mode.', style: t.subtitle),
      ],
    );
  }

  Widget _doneStep(BuildContext context, LauncherSession? session, List<_Row>? rows, {required bool home}) {
    final t = KitType.of(context);
    if (session == null || rows == null) return const KitColumns(start: [StatusPanel.working(items: [WorkItem('Looking for games')])]);
    final picks = _picks(session, rows);
    return KitColumns(
      start: [
        const KitLabel('Ready'),
        if (picks.isEmpty)
          KitPanel(padding: const EdgeInsets.all(12), children: [Text('No console set up yet.', style: t.body)])
        else
          OptionList(children: [
            for (final r in rows)
              if (picks[r.console.id] != null) OptionAction(title: r.console.name, value: choiceName(session, picks[r.console.id]!), chevron: false, onTap: null),
          ]),
        if (home) const OptionList(children: [OptionAction(title: 'Home screen', value: 'Retro Toolbox', chevron: false, onTap: null)]),
      ],
      end: [
        const KitLabel('After Finish'),
        Text('Play on a game opens it in its console\'s emulator. Change one later in Settings or on the console\'s page.', style: t.subtitle),
      ],
    );
  }
}

/// "a, b or c".
String _list(List<String> names) => names.length < 2 ? names.join() : '${names.take(names.length - 1).join(', ')} or ${names.last}';

class _EmulatorRow extends StatelessWidget {
  const _EmulatorRow({required this.emulator, required this.verified});

  final DetectedEmulator emulator;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final icon = emulator.icon;
    final line = [if (emulator.version != null) emulator.version!, if (!verified) 'not tested'].join(' · ');
    return KitRow(
      key: ValueKey('launcher-found-${emulator.presetId}'),
      child: Row(children: [
        if (icon != null) Image.memory(icon, width: 32, height: 32) else const Icon(Icons.videogame_asset_outlined, size: 32),
        const SizedBox(width: 12),
        Expanded(child: KitRowText(title: emulator.label, subtitle: line)),
      ]),
    );
  }
}
