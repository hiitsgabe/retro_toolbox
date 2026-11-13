import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

/// Describing an app's saves well enough to sync them, on the handheld that
/// has the app.
///
/// Almost everything is read off the device. The one question a device cannot
/// answer is what a save *is* here — a folder each, a file each, or all of it
/// together — so that is asked in plain words, once, with the real listing on
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

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Describe ${widget.label}')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              for (var i = 0; i < _steps.length; i++) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: i <= _step ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                  child: Text('${i + 1}', style: TextStyle(color: i <= _step ? Colors.white : theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Text(_steps[i], style: theme.textTheme.labelMedium),
                if (i < _steps.length - 1) const Expanded(child: Divider(indent: 8, endIndent: 8)),
              ],
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: switch (_step) {
                0 => _folderStep(theme),
                1 => _shapeStep(theme),
                _ => _travelsStep(theme),
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              if (_step > 0) OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: _busy || _root == null ? null : (_step == 2 ? _finish : () => setState(() => _step++)),
                child: Text(_step == 2 ? 'Save recipe' : 'Next'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _folderStep(ThemeData theme) {
    if (_busy) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (_root == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('No save folder found for this app.', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Open the app once so it makes one, then come back. If its saves live where only root reaches, this device cannot describe them.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _probe, child: const Text('Look again')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('This is what the app keeps', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(_root!, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      const SizedBox(height: 12),
      for (final e in _listing ?? const <({String name, bool isDir})>[])
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(e.isDir ? Icons.folder : Icons.insert_drive_file, size: 20),
          title: Text(e.name),
        ),
      if ((_listing ?? const []).isEmpty)
        Text('Nothing in it yet. Play once and come back.', style: theme.textTheme.bodyMedium),
    ]);
  }

  Widget _shapeStep(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What counts as one save here?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'This is the one thing the app cannot work out by looking. It decides what can be kept apart from what, '
          'and it cannot be changed later without orphaning what was already synced.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final (kind, title, blurb) in const [
          (UnitKind.folder, 'Each folder here is a separate save', 'One folder per slot, save file and its companions inside.'),
          (UnitKind.file, 'Each file here is a separate save', 'One file per slot, side by side.'),
          (UnitKind.all, 'All of this together is one save', 'The app keeps one state, spread over whatever it likes.'),
        ])
          RadioListTile<UnitKind>(
            contentPadding: EdgeInsets.zero,
            value: kind,
            // ignore: deprecated_member_use
            groupValue: _unit,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => _unit = v ?? _unit),
            title: Text(title),
            subtitle: Text(blurb, style: theme.textTheme.bodySmall),
          ),
      ]);

  Widget _travelsStep(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        Text('What should travel?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          "Leave out the app's own backups and its settings: they belong to the handheld they are on.",
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        for (final e in _listing ?? const <({String name, bool isDir})>[])
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _travels.contains(e.name),
            onChanged: (on) => setState(() => on == true ? _travels.add(e.name) : _travels.remove(e.name)),
            title: Text(e.name),
          ),
      ]);

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

    // A recipe can parse and still match nothing — a folder unit whose
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
