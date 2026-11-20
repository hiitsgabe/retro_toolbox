import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Describing an app's saves well enough to sync them, on the handheld that
/// has the app.
///
/// Almost everything is read off the device. The one question a device cannot
/// answer is what a save *is* here (a folder each, a file each, or all of it
/// together), so that is asked in plain words, once, with the real listing on
/// screen. It becomes the hub's directory name, and getting it wrong later
/// orphans everything already pushed.
class SaveSyncRecipeWizardScreen extends ConsumerStatefulWidget {
  const SaveSyncRecipeWizardScreen({super.key, required this.package, required this.label});

  final String package;
  final String label;

  @override
  ConsumerState<SaveSyncRecipeWizardScreen> createState() => _SaveSyncRecipeWizardScreenState();
}

class _SaveSyncRecipeWizardScreenState extends ConsumerState<SaveSyncRecipeWizardScreen> {
  static const _steps = ['Folder', 'Shape', 'What travels'];

  int _step = 0;
  String? _root;
  List<({String name, bool isDir})>? _listing;
  UnitKind _unit = UnitKind.all;
  late final TextEditingController _name = TextEditingController(text: widget.label);
  final _travels = <String>{};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_probe);
  }

  /// Holds the step's body, so a new step can take focus from the button
  /// that moved to it.
  final _body = FocusNode(debugLabel: 'describe-step');

  /// Moves to [step] and, with a pad, onto its first control: focus left on
  /// the (i) or the bar would make the d-pad hunt for the question.
  void _go(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      // Not a text field: on a pad that opens the keyboard's way into a name
      // that is already filled in.
      bool field(FocusNode n) => n.context?.findAncestorWidgetOfExactType<EditableText>() != null;
      _body.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal && !field(n)).firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    _body.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() => _busy = true);
    final found = await ref.read(saveSyncProvider.notifier).probeSaveFolder(widget.package);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _root = found?.root;
      _listing = found?.entries;
      for (final e in found?.entries ?? const <({String name, bool isDir})>[]) {
        if (!_looksLocal(e.name)) _travels.add(e.name);
      }
    });
  }

  /// Only ever a pre-tick. The person decides; the heuristic just saves them
  /// from unticking the obvious.
  bool _looksLocal(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.bak') || n.contains('_old') || n.startsWith('settings') || n.endsWith('.log') || n.contains('backup');
  }

  static const _shapes = [
    (UnitKind.folder, 'Each folder here is a separate save', 'One folder per slot, save file and its companions inside.'),
    (UnitKind.file, 'Each file here is a separate save', 'One file per slot, side by side.'),
    (UnitKind.all, 'All of this together is one save', 'The app keeps one state, spread over whatever it likes.'),
  ];

  @override
  Widget build(BuildContext context) {
    final last = _step == _steps.length - 1;
    final body = switch (_step) {
      0 => _folderStep(context),
      1 => _shapeStep(context),
      _ => _travelsStep(context),
    };
    return WizardShell(
      name: 'Describe ${widget.label}',
      step: _step,
      count: _steps.length,
      stepName: _steps[_step],
      icon: Icons.sync,
      glyph: PixelIcons.saves,
      area: AppArea.saves,
      info: const InfoButton(
        icon: Icons.sync,
        title: 'Describe an app',
        text: 'Save Sync shows you the folder this app keeps its saves in, then asks what counts as one save and what should travel. '
            'What counts as one save is the one thing the app cannot work out by looking. It decides what can be kept apart from what, '
            'and it cannot be changed later without orphaning what was already synced.',
      ),
      body: Focus(
        focusNode: _body,
        skipTraversal: true,
        canRequestFocus: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            body,
            if (_error != null) Padding(padding: const EdgeInsets.only(top: kitGap), child: StatusPanel.error(line: _error!)),
          ]),
        ),
      ),
      onBack: _step > 0 && !_busy ? () => _go(_step - 1) : null,
      // Step 1 has no Back; a desktop has no back key either.
      leaveLabel: _step == 0 ? 'Cancel' : null,
      onNext: _busy || _root == null ? null : (last ? _finish : () => _go(_step + 1)),
      nextLabel: last ? 'Save recipe' : 'Next',
    );
  }

  Widget _folderStep(BuildContext context) {
    final t = KitType.of(context);
    if (_busy && _root == null) return StatusPanel.working(items: const [WorkItem('Looking for the save folder')]);
    if (_root == null) {
      return StatusPanel.missingRequirement(
        title: 'No save folder found for this app.',
        detail: 'Open the app once so it makes one, then come back. If its saves live where only root reaches, this device cannot describe them.',
        actionLabel: 'Look again',
        onAction: _probe,
      );
    }
    final listing = _listing ?? const <({String name, bool isDir})>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const KitLabel('This is what the app keeps'),
      const SizedBox(height: 4),
      KitPanel(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Text(_root!, style: t.mono(12))),
        for (final e in listing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(e.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined, size: 18, color: t.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(e.name, style: t.body, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        if (listing.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('Nothing in it yet. Play once and come back.', style: t.body)),
      ]),
    ]);
  }

  Widget _shapeStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const KitLabel('What counts as one save here?'),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
          child: Text("Can't be changed later. The (i) says why.", style: KitType.of(context).subtitle),
        ),
        OptionList(children: [
          for (final (i, (kind, title, blurb)) in _shapes.indexed)
            OptionChoice<UnitKind>(
              autofocus: i == 0,
              title: title,
              subtitle: blurb,
              value: kind,
              groupValue: _unit,
              onSelected: (v) => setState(() => _unit = v),
            ),
        ]),
      ]);

  Widget _travelsStep(BuildContext context) {
    final listing = _listing ?? const <({String name, bool isDir})>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KitPanel(children: [FieldSlot(label: 'Name', controller: _name, icon: Icons.label_outline)]),
      const SizedBox(height: kitGap),
      const KitLabel('What should travel?'),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
        child: Text("Leave out the app's own backups and its settings: they belong to the handheld they are on.", style: KitType.of(context).subtitle),
      ),
      OptionList(children: [
        for (final (i, e) in listing.indexed)
          OptionToggle(
            autofocus: i == 0,
            title: e.name,
            value: _travels.contains(e.name),
            onChanged: (on) => setState(() => on ? _travels.add(e.name) : _travels.remove(e.name)),
          ),
      ]),
    ]);
  }

  String get _id {
    final slug = _name.text.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp('^-+|-+\$'), '');
    return slug.isEmpty ? 'app-${widget.package.hashCode.abs()}' : slug;
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final travels = _travels.toList()..sort();
    final local = [for (final e in _listing ?? const <({String name, bool isDir})>[]) if (!_travels.contains(e.name)) e.name];
    final json = <String, dynamic>{
      'schema': 1,
      'id': _id,
      'name': _name.text.trim(),
      // Never verified: that skips the prompt that asks the owner to confirm
      // where the saves are, which a recipe written from one device has not
      // earned.
      'status': 'draft',
      'packages': [widget.package],
      'locations': [
        {'area': 'androidData', 'root': _rootRelative},
      ],
      'unit': _unit.name,
      'include': [for (final t in travels) _unit == UnitKind.folder ? '*/$t' : t],
      if (local.isNotEmpty) 'deviceLocal': [for (final t in local) _unit == UnitKind.folder ? '*/$t' : t],
      // Correct with no knowledge of the app at all, and it only ever refuses
      // a restore across versions.
      'version': {'from': 'package', 'rule': 'sameBuild'},
    };

    // Recipe.parse is the validator: an unknown key is a hard error there, so
    // there is no second rulebook here to drift from it.
    Recipe recipe;
    try {
      recipe = Recipe.parse(json);
    } on RecipeError catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    }

    // A recipe can parse and still match nothing: a folder unit whose
    // patterns have no slash can never group a file. Refuse to save one that
    // would silently sync nothing.
    final rels = [
      for (final e in _listing ?? const <({String name, bool isDir})>[]) e.isDir ? '${e.name}/file' : e.name,
    ];
    if (groupUnits(recipe, rels).isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Nothing in this folder would travel with those choices. Try another shape.';
      });
      return;
    }

    try {
      final dir = Directory(p.join(ref.read(saveSyncProvider.notifier).saveSyncDir, 'recipes'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, '${recipe.id}.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
      await ref.read(saveSyncProvider.notifier).addApps({widget.package: recipe.id});
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// The recipe's root is relative to the app's data folder, so a recipe
  /// written here reads the same on a handheld that mounts it elsewhere.
  String get _rootRelative {
    final root = _root ?? '';
    final marker = '/${widget.package}/';
    final i = root.indexOf(marker);
    return i < 0 ? 'files' : root.substring(i + marker.length);
  }
}
