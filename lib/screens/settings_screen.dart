import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

/// Settings in sections. Wide: the sections in a rail on the left, the
/// chosen one's rows on the right; L1/R1 change section, B goes from the rows
/// back to the rail, and Consoles opens a console's own page in place (its
/// consoles then fill the rail). Narrow: a list of sections, each its own page.
/// [consoleId] opens that console's page.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.consoleId, this.showControllerHints});

  final String? consoleId;

  /// Button hints in the header and footer. Null: on Android and the Linux
  /// handheld, where a gamepad drives the app.
  final bool? showControllerHints;

  /// From this width the rail and the rows share the screen.
  static const wideFrom = 720.0;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsSection _section = SettingsSection.library;

  /// Wide: the console whose page is open in Consoles.
  String? _consoleId;
  bool _openedConsoleArg = false;

  final _nodes = <String, FocusNode>{};
  final _content = FocusNode(debugLabel: 'settings rows', canRequestFocus: false, skipTraversal: true);
  final _rail = FocusNode(debugLabel: 'settings rail', canRequestFocus: false, skipTraversal: true);

  bool get _hints => widget.showControllerHints ?? (Platform.isAndroid || Handheld.current);

  @override
  void initState() {
    super.initState();
    if (widget.consoleId != null) {
      _section = SettingsSection.consoles;
      _consoleId = widget.consoleId;
    }
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _content.dispose();
    _rail.dispose();
    super.dispose();
  }

  FocusNode _node(String key) => _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'settings $key'));
  FocusNode _sectionNode(SettingsSection s) => _node('section:${s.name}');
  FocusNode _consoleNode(String id) => _node('console:$id');

  bool get _traditional => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  bool _inRows(FocusNode? n) => n != null && n.ancestors.contains(_content);

  /// After the next frame, so rows just put on screen can take it.
  void _later(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  void _focusRows() {
    final first = _content.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    first?.requestFocus();
  }

  void _focusRail() => (_consoleId != null ? _consoleNode(_consoleId!) : _sectionNode(_section)).requestFocus();

  void _select(SettingsSection s) {
    if (s == _section && _consoleId == null) return;
    setState(() {
      _section = s;
      _consoleId = null;
    });
  }

  void _openConsole(Console c) {
    setState(() {
      _section = SettingsSection.consoles;
      _consoleId = c.id;
    });
    _later(_focusRows);
  }

  void _closeConsole() {
    setState(() => _consoleId = null);
    _later(() => _sectionNode(SettingsSection.consoles).requestFocus());
  }

  /// L1/R1: the section before or after, keeping focus on the rail or in the
  /// rows, wherever it was.
  void _step(List<SettingsSection> visible, bool forward) {
    final i = visible.indexOf(_section);
    final next = (i + (forward ? 1 : -1)).clamp(0, visible.length - 1);
    if (next == i && _consoleId == null) return;
    final inRows = _inRows(FocusManager.instance.primaryFocus);
    setState(() {
      _section = visible[next];
      _consoleId = null;
    });
    _later(inRows ? _focusRows : () => _sectionNode(_section).requestFocus());
  }

  /// B (and the back button): from the rows to the rail, from a console's
  /// page to Consoles, else out of Settings.
  void _back() {
    if (_traditional && _inRows(FocusManager.instance.primaryFocus)) {
      _focusRail();
    } else if (_consoleId != null) {
      _closeConsole();
    } else {
      Navigator.of(context).pop();
    }
  }

  KeyEventResult _onRowsKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final from = FocusManager.instance.primaryFocus;
    if (from == null || from.context?.findAncestorStateOfType<EditableTextState>() != null) return KeyEventResult.ignored;
    // Side by side buttons inside a row (a form) keep left for themselves.
    final r = from.rect;
    final beside = _content.traversalDescendants
        .any((n) => n != from && n.canRequestFocus && !n.skipTraversal && n.rect.right <= r.left + 1 && n.rect.bottom > r.top && n.rect.top < r.bottom);
    if (beside) return KeyEventResult.ignored;
    // Not a plain step left: the nearest rail tile may not be this section's.
    _focusRail();
    return KeyEventResult.handled;
  }

  KeyEventResult _onRailKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    _focusRows();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final rows = {
      for (final s in SettingsSection.values) s: settingsSectionRows(s, ref, onOpenConsole: (c) => _onConsolePicked(context, c)),
    };
    final visible = [
      for (final s in SettingsSection.values)
        if (rows[s]!.isNotEmpty) s
    ];
    if (!visible.contains(_section)) {
      _section = visible.first;
      _consoleId = null;
    }
    final consoles = ref.watch(appStateProvider).consolesList;
    final console = consoles.where((c) => c.id == _consoleId).firstOrNull;
    if (_consoleId != null && console == null && consoles.isNotEmpty) _consoleId = null;

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < SettingsScreen.wideFrom) return _narrow(context, visible);
      return _wide(context, visible, rows[_section]!, consoles, console);
    });
  }

  void _onConsolePicked(BuildContext context, Console c) {
    if (MediaQuery.sizeOf(context).width < SettingsScreen.wideFrom) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c, hints: _hints)));
    } else {
      _openConsole(c);
    }
  }

  // ---- Wide

  Widget _wide(BuildContext context, List<SettingsSection> visible, List<Widget> sectionRows, List<Console> consoles, Console? console) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final crumbs = ['Settings', _section.label, if (console != null) console.name];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Actions(
        actions: {
          PageFocusIntent: CallbackAction<PageFocusIntent>(onInvoke: (i) {
            _step(visible, i.forward);
            return null;
          }),
        },
        child: Scaffold(
          appBar: AppBar(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Row(children: [
              for (var i = 0; i < crumbs.length; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('/', style: TextStyle(color: scheme.outline))),
                Flexible(
                  child: Text(
                    crumbs[i],
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                      color: i == 0 || i == crumbs.length - 1 ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ]),
            actions: [
              if (_hints)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(children: const [_KeyCap('L1'), SizedBox(width: 6), _KeyCap('R1'), SizedBox(width: 8), Text('switch section')]),
                ),
            ],
          ),
          bottomNavigationBar: _hints ? _HintBar(reset: console != null) : null,
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 288,
              child: Material(
                color: scheme.surfaceContainerLow,
                child: Focus(
                  focusNode: _rail,
                  onKeyEvent: _onRailKey,
                  child: FocusTraversalGroup(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: console == null ? _sectionTiles(visible) : _consoleTiles(consoles),
                    ),
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: scheme.surfaceContainerHigh),
            Expanded(
              child: Focus(
                focusNode: _content,
                onKeyEvent: _onRowsKey,
                child: FocusTraversalGroup(
                  child: SingleChildScrollView(
                    key: ValueKey('rows ${_section.name} $_consoleId'),
                    padding: const EdgeInsets.fromLTRB(40, 20, 40, 32),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: console == null ? sectionRows : consoleSettingsRows(console, ref),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _sectionTiles(List<SettingsSection> visible) => [
        for (final s in visible)
          _RailTile(
            key: ValueKey('rail ${s.name}'),
            focusNode: _sectionNode(s),
            autofocus: s == _section && widget.consoleId == null,
            icon: s.icon,
            label: s.label,
            hint: s.hint,
            selected: s == _section,
            // A d-pad walk down the rail shows each section as it passes.
            onFocused: () {
              if (_traditional) _select(s);
            },
            onTap: () {
              _select(s);
              _later(_focusRows);
            },
          ),
      ];

  List<Widget> _consoleTiles(List<Console> consoles) {
    final notifier = ref.read(settingsProvider.notifier);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text('CONSOLES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: Theme.of(context).colorScheme.outline)),
      ),
      for (final c in consoles)
        _RailTile(
          key: ValueKey('rail console ${c.id}'),
          focusNode: _consoleNode(c.id),
          autofocus: c.id == _consoleId && widget.consoleId != null,
          label: c.name,
          badge: notifier.changedKeys(c.id).length,
          selected: c.id == _consoleId,
          onFocused: () {
            if (_traditional && c.id != _consoleId) setState(() => _consoleId = c.id);
          },
          onTap: () {
            setState(() => _consoleId = c.id);
            _later(_focusRows);
          },
        ),
    ];
  }

  // ---- Narrow

  Widget _narrow(BuildContext context, List<SettingsSection> visible) {
    if (widget.consoleId != null && !_openedConsoleArg) {
      _openedConsoleArg = true;
      final c = ref.read(appStateProvider).consoles[widget.consoleId];
      if (c != null) {
        _later(() {
          final nav = Navigator.of(context);
          nav.push(MaterialPageRoute(builder: (_) => _SectionPage(section: SettingsSection.consoles, hints: _hints)));
          nav.push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c, hints: _hints)));
        });
      }
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: false, elevation: 0, scrolledUnderElevation: 0),
      bottomNavigationBar: _hints ? const _HintBar(adjust: false) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final s in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('section ${s.name}'),
                  autofocus: s == visible.first,
                  focusColor: Colors.transparent,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: s, hints: _hints))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(children: [
                      _IconTile(icon: s.icon, selected: false),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(s.hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ]),
                      ),
                      Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A section on its own page (narrow screens).
class _SectionPage extends ConsumerWidget {
  const _SectionPage({required this.section, required this.hints});

  final SettingsSection section;
  final bool hints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = settingsSectionRows(
      section,
      ref,
      onOpenConsole: (c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c, hints: hints))),
    );
    return _RowsPage(title: section.label, hints: hints, rows: rows);
  }
}

/// A console's page on its own (narrow screens).
class _ConsolePage extends ConsumerWidget {
  const _ConsolePage({required this.console, required this.hints});

  final Console console;
  final bool hints;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _RowsPage(title: console.name, hints: hints, reset: true, rows: consoleSettingsRows(console, ref));
}

class _RowsPage extends StatelessWidget {
  const _RowsPage({required this.title, required this.hints, required this.rows, this.reset = false});

  final String title;
  final bool hints;
  final bool reset;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false, elevation: 0, scrolledUnderElevation: 0),
      bottomNavigationBar: hints ? _HintBar(reset: reset) : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.selected});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: selected ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: selected ? scheme.onPrimary : scheme.primary),
    );
  }
}

/// One section (or console) in the wide rail.
class _RailTile extends StatelessWidget {
  const _RailTile({
    super.key,
    required this.focusNode,
    required this.label,
    required this.selected,
    required this.onFocused,
    required this.onTap,
    this.icon,
    this.hint,
    this.badge = 0,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final String label;
  final bool selected;
  final VoidCallback onFocused;
  final VoidCallback onTap;
  final IconData? icon;
  final String? hint;
  final int badge;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          autofocus: autofocus,
          focusColor: Colors.transparent,
          onFocusChange: (f) {
            if (f) onFocused();
          },
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                if (icon != null) ...[_IconTile(icon: icon!, selected: selected), const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: fg)),
                    if (hint != null)
                      Text(hint!,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: selected ? fg : scheme.outline)),
                  ]),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: selected ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                    child: Text('$badge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.onSurface)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface)),
    );
  }
}

/// The controller buttons this screen answers to.
class _HintBar extends StatelessWidget {
  const _HintBar({this.reset = false, this.adjust = true});

  final bool reset;
  final bool adjust;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget hint(String key, String what) => Row(mainAxisSize: MainAxisSize.min, children: [_KeyCap(key), const SizedBox(width: 6), Text(what)]);
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.surfaceContainerHigh))),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 20,
              children: [
                hint('A', 'Change'),
                if (adjust) hint('◀ ▶', 'Adjust'),
                if (reset) hint('X', 'Reset'),
                hint('B', 'Back'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
