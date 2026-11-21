import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/kit_scaffold.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

/// Settings in sections. Wide: the sections in a rail on the left, the
/// chosen one's rows on the right; L1/R1 change section, B goes from the rows
/// back to the rail, and Consoles opens a console's own page in place (its
/// consoles then fill the rail). Narrow: a list of sections, each its own page.
/// [consoleId] opens that console's page; [section] opens that section.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.consoleId, this.section, this.showControllerHints});

  final String? consoleId;
  final SettingsSection? section;

  /// The L1/R1 hint in the header, shown only after gamepad input. Null: on
  /// Android and the Linux handheld, where a gamepad drives the app.
  final bool? showControllerHints;

  /// From this width the rail and the rows share the screen.
  static const wideFrom = 720.0;

  /// Opens Settings on [section] (a converter's "Open Settings > Keys").
  static Future<void> open(BuildContext context, {SettingsSection? section}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(section: section)));

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsSection _section = SettingsSection.library;

  /// Wide: the console whose page is open in Consoles.
  String? _consoleId;
  bool _openedArg = false;

  final _nodes = <String, FocusNode>{};
  final _content = FocusNode(debugLabel: 'settings rows', canRequestFocus: false, skipTraversal: true);
  final _rail = FocusNode(debugLabel: 'settings rail', canRequestFocus: false, skipTraversal: true);

  /// On a device with a pad, and only while the last input came from it.
  bool get _hints => (widget.showControllerHints ?? (Platform.isAndroid || Handheld.current)) && ref.watch(inputModeProvider) == InputMode.gamepad;

  @override
  void initState() {
    super.initState();
    if (widget.consoleId != null) {
      _section = SettingsSection.consoles;
      _consoleId = widget.consoleId;
    } else if (widget.section != null) {
      _section = widget.section!;
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

  /// A row's link to another section (a console's missing keys to Keys).
  void _goTo(SettingsSection s) {
    setState(() {
      _section = s;
      _consoleId = null;
    });
    _later(_focusRows);
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

  /// B and the header's back button: from the rows to the rail, from a
  /// console's page to Consoles, else out of Settings.
  void _back() {
    if (settingsFocusShows && _inRows(FocusManager.instance.primaryFocus)) {
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
    // Side by side buttons inside a row keep left for themselves.
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

  SettingsLinks _links(BuildContext context) => SettingsLinks(
        openConsole: (c) => _onConsolePicked(context, c),
        openSection: (s) => _onSectionLink(context, s),
      );

  void _onConsolePicked(BuildContext context, Console c) {
    if (MediaQuery.sizeOf(context).width < SettingsScreen.wideFrom) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c)));
    } else {
      _openConsole(c);
    }
  }

  void _onSectionLink(BuildContext context, SettingsSection s) {
    if (MediaQuery.sizeOf(context).width < SettingsScreen.wideFrom) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: s)));
    } else {
      _goTo(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = _links(context);
    final rows = {for (final s in SettingsSection.values) s: settingsSectionRows(s, ref, links: links)};
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

  // ---- Wide

  Widget _wide(BuildContext context, List<SettingsSection> visible, List<Widget> sectionRows, List<Console> consoles, Console? console) {
    final k = StyleTokens.of(context);
    final crumbs = [_section.label, if (console != null) console.name];
    // A handheld just past the breakpoint (Odin 2, 731) keeps more for the rows.
    final railWidth = (MediaQuery.sizeOf(context).width * 0.3).clamp(232.0, 288.0);
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
          body: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SettingsTopBar(
                crumbs: crumbs,
                gear: console == null,
                sectionHint: _hints && console == null,
                back: console != null || Navigator.of(context).canPop(),
              ),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    width: railWidth,
                    decoration: BoxDecoration(color: k.settingsTile, border: Border(right: BorderSide(color: k.settingsLine))),
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
                  Expanded(
                    child: Focus(
                      focusNode: _content,
                      onKeyEvent: _onRowsKey,
                      child: FocusTraversalGroup(
                        child: SingleChildScrollView(
                          key: ValueKey('rows ${_section.name} $_consoleId'),
                          padding: const EdgeInsets.fromLTRB(24, 16 - settingsHalfGap, 24, 32),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: console == null ? sectionRows : consoleSettingsRows(console, ref, onOpenKeys: () => _goTo(SettingsSection.keys)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionTiles(List<SettingsSection> visible) => [
        for (final s in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _RailTile(
              key: ValueKey('rail ${s.name}'),
              focusNode: _sectionNode(s),
              autofocus: s == _section && widget.consoleId == null,
              section: s,
              label: s.label,
              hint: s.hint,
              selected: s == _section,
              // A d-pad walk down the rail shows each section as it passes.
              onFocused: () {
                if (settingsFocusShows) _select(s);
              },
              onTap: () {
                _select(s);
                _later(_focusRows);
              },
            ),
          ),
      ];

  List<Widget> _consoleTiles(List<Console> consoles) {
    final notifier = ref.read(settingsProvider.notifier);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Text('CONSOLES', style: KitType.of(context).label.copyWith(fontSize: KitType.of(context).size(12))),
      ),
      for (final c in consoles)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _RailTile(
            key: ValueKey('rail console ${c.id}'),
            focusNode: _consoleNode(c.id),
            autofocus: c.id == _consoleId && widget.consoleId != null,
            label: c.name,
            badge: notifier.changedKeys(c.id).length,
            selected: c.id == _consoleId,
            onFocused: () {
              if (settingsFocusShows && c.id != _consoleId) setState(() => _consoleId = c.id);
            },
            onTap: () {
              setState(() => _consoleId = c.id);
              _later(_focusRows);
            },
          ),
        ),
    ];
  }

  // ---- Narrow

  Widget _narrow(BuildContext context, List<SettingsSection> visible) {
    if (!_openedArg && (widget.consoleId != null || widget.section != null)) {
      _openedArg = true;
      final c = widget.consoleId == null ? null : ref.read(appStateProvider).consoles[widget.consoleId];
      final section = widget.section;
      _later(() {
        final nav = Navigator.of(context);
        if (c != null) {
          nav.push(MaterialPageRoute(builder: (_) => _SectionPage(section: SettingsSection.consoles)));
          nav.push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c)));
        } else if (section != null && visible.contains(section)) {
          nav.push(MaterialPageRoute(builder: (_) => _SectionPage(section: section)));
        }
      });
    }
    final t = KitType.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingsTopBar(crumbs: const [], back: Navigator.of(context).canPop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                for (final s in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SettingsTile(
                      key: ValueKey('section ${s.name}'),
                      autofocus: s == visible.first,
                      minHeight: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: s))),
                      child: Row(children: [
                        _SectionIconTile(section: s, selected: false),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                            Text(s.label, style: t.row.copyWith(fontSize: t.size(16))),
                            Text(settingsSectionSummary(s, ref), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle.copyWith(fontSize: t.size(13))),
                          ]),
                        ),
                        const SizedBox(width: 14),
                        SettingsIcon(SettingsIcons.chevronRight, size: 18, color: t.muted),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// A section on its own page (narrow screens).
class _SectionPage extends ConsumerWidget {
  const _SectionPage({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = settingsSectionRows(
      section,
      ref,
      links: SettingsLinks(
        openConsole: (c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ConsolePage(console: c))),
        openSection: (s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: s))),
      ),
    );
    return _RowsPage(title: section.label, rows: rows);
  }
}

/// A console's page on its own (narrow screens).
class _ConsolePage extends ConsumerWidget {
  const _ConsolePage({required this.console});

  final Console console;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _RowsPage(
        title: console.name,
        rows: consoleSettingsRows(
          console,
          ref,
          onOpenKeys: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: SettingsSection.keys))),
        ),
      );
}

class _RowsPage extends StatelessWidget {
  const _RowsPage({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingsTopBar(crumbs: [title], back: true, page: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The bar on top of Settings: the back button, the gear, "Settings /
/// Section / ..." and on a gamepad the L1/R1 hint. [page]: a page of its
/// own (narrow), with only its title.
class SettingsTopBar extends StatelessWidget {
  const SettingsTopBar({super.key, required this.crumbs, this.gear = true, this.sectionHint = false, this.back = false, this.page = false});

  final List<String> crumbs;
  final bool gear;
  final bool sectionHint;
  final bool back;
  final bool page;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final parts = page ? crumbs : ['Settings', ...crumbs];
    return Container(
      height: t.portrait ? 56 : 48,
      padding: EdgeInsets.only(left: back ? 4 : 16, right: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: k.settingsLine))),
      child: Row(children: [
        if (back) ...[
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: k.pixelIcons ? const PixelIcon(PixelIcons.back, size: 20) : Icon(Icons.arrow_back, color: t.ink),
          ),
          const SizedBox(width: 4),
        ],
        if (gear && !page) ...[
          const KitIconTile(icon: Icons.settings, glyph: PixelIcons.settings, size: 30),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Row(children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('/', style: t.title.copyWith(color: t.muted))),
              Flexible(
                child: Text(
                  parts[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.title.copyWith(
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: i == 0 || i == parts.length - 1 && parts.length > 2 ? t.ink : t.muted,
                  ),
                ),
              ),
            ],
          ]),
        ),
        if (sectionHint) ...[
          const KeyCap('L1'),
          const SizedBox(width: 8),
          const KeyCap('R1'),
          const SizedBox(width: 8),
          Text('switch section', style: t.subtitle.copyWith(fontSize: t.size(13))),
        ],
      ]),
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
    this.section,
    this.hint,
    this.badge = 0,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final String label;
  final bool selected;
  final VoidCallback onFocused;
  final VoidCallback onTap;
  /// Null for a console's tile, which has no icon.
  final SettingsSection? section;
  final String? hint;
  final int badge;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final fg = t.ink;
    final console = section == null;
    final wash = k.accent.withValues(alpha: 0.18);
    return SettingsTile(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onFocusChange: (f) {
        if (f) onFocused();
      },
      color: selected ? wash : Colors.transparent,
      focusedColor: selected ? Color.alphaBlend(wash, k.settingsTileFocused) : k.settingsTileFocused,
      minHeight: console ? 52 : 60,
      padding: EdgeInsets.symmetric(horizontal: console ? 14 : 12, vertical: 8),
      child: Row(children: [
        if (section != null) ...[
          _SectionIconTile(section: section!, selected: selected, size: 34),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.row.copyWith(fontSize: t.size(15), fontWeight: console && !selected ? FontWeight.w500 : FontWeight.w600, color: fg)),
            if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle.copyWith(color: selected ? fg.withValues(alpha: 0.8) : t.muted)),
          ]),
        ),
        if (badge > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: selected ? k.accent : Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('$badge', style: TextStyle(fontSize: t.size(12), fontWeight: FontWeight.w700, color: selected ? k.onAccent : t.ink)),
          ),
      ]),
    );
  }
}

/// A controller button's name in a small chip: round for one letter.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final round = label.length == 1;
    return Container(
      constraints: BoxConstraints(minWidth: round ? 22 : 28),
      height: 22,
      padding: EdgeInsets.symmetric(horizontal: round ? 0 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(round ? 11 : 6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: round ? FontWeight.w700 : FontWeight.w600, color: scheme.onSurface)),
    );
  }
}

/// A section's icon on a tile of the accent: filled when [selected], a wash
/// of it otherwise.
class _SectionIconTile extends StatelessWidget {
  const _SectionIconTile({required this.section, required this.selected, this.size = 38});

  final SettingsSection section;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? k.accent : k.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 10).toDouble()),
      ),
      child: SectionIcon(section, size: size * 0.55, color: selected ? k.onAccent : k.accent),
    );
  }
}
