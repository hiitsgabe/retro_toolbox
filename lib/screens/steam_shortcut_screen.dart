import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/services/steam_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';
import 'package:retro_toolbox/services/pick.dart';

/// Search the Steam store, multi-select games, and write `.steam` shortcut
/// files (ES-DE format) into a chosen folder.
class SteamShortcutScreen extends ConsumerStatefulWidget {
  const SteamShortcutScreen({super.key, this.service});

  /// Tests: the store search and the file writer.
  final SteamService? service;

  static const _lastDirKey = 'steam_shortcut_last_dir';

  @override
  ConsumerState<SteamShortcutScreen> createState() => _SteamShortcutScreenState();
}

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "Permission denied" out of a FileSystemException; else its first line.
String _reason(String error) => RegExp(r'OS Error: ([^,)]+)').firstMatch(error)?.group(1)?.trim() ?? error.split('\n').first;

class _SteamShortcutScreenState extends ConsumerState<SteamShortcutScreen> {
  late final _steamService = widget.service ?? SteamService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<SteamGame> _results = [];
  // Selection persists across searches so users can build a batch.
  final Map<int, SteamGame> _selected = {};

  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _creating = false;
  String? _error;

  /// Where the files go: the last folder used, until changed.
  String? _dir;
  StatusPanel _status = const StatusPanel.hidden();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_hasMore && !_loadingMore && !_loading && _scrollController.position.extentAfter < 400) {
        _loadMore();
      }
    });
    SharedPreferences.getInstance().then((prefs) {
      final dir = prefs.getString(SteamShortcutScreen._lastDirKey);
      if (mounted && dir != null) setState(() => _dir ??= dir);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
      _results.clear();
      _hasMore = false;
    });
    try {
      final page = await _steamService.search(query);
      if (!mounted) return;
      setState(() {
        _results.addAll(page.results);
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await _steamService.search(_query, start: _results.length);
      if (!mounted) return;
      setState(() {
        _results.addAll(page.results);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // Pagination failure is non-fatal; the scroll listener will retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<String?> _pickDir() async {
    final folder = await pickDirectory(context, title: 'Select destination folder', initialDir: _dir);
    if (folder == null || !mounted) return null;
    setState(() => _dir = folder);
    (await SharedPreferences.getInstance()).setString(SteamShortcutScreen._lastDirKey, folder);
    return folder;
  }

  Future<void> _createFiles() async {
    if (_selected.isEmpty || _creating) return;
    final folder = _dir ?? await _pickDir();
    if (folder == null || !mounted) return;

    final games = _selected.values.toList();
    setState(() => _creating = true);
    final errors = await _steamService.createShortcuts(games, folder);
    if (!mounted) return;
    final made = games.length - errors.length;
    setState(() {
      _creating = false;
      // What was written leaves the selection; what failed stays for a retry.
      _selected.removeWhere((_, g) => !errors.containsKey(g.name));
      final where = pathParts(folder).join(pathSeparator);
      if (errors.isEmpty) {
        _status = StatusPanel.done(summary: 'Created ${_count(made, 'shortcut')} in $where');
      } else if (made == 0) {
        _status = StatusPanel.error(
          line: 'Could not create ${games.length == 1 ? 'the shortcut' : 'the shortcuts'}',
          details: [for (final e in errors.entries) '${e.key}: ${e.value}'].join('\n'),
        );
      } else {
        _status = StatusPanel.done(
          summary: '$made created in $where, ${errors.length} failed',
          problems: [for (final e in errors.entries) Problem(e.key, _reason(e.value), failed: true)],
        );
      }
    });
  }

  void _setSelection(Set<String> ids) {
    final known = {for (final g in [..._selected.values, ..._results]) '${g.appid}': g};
    setState(() {
      _selected
        ..clear()
        ..addEntries([for (final id in ids) if (known[id] != null) MapEntry(known[id]!.appid, known[id]!)]);
    });
  }

  static const _info = InfoButton(
    icon: Icons.videogame_asset_rounded,
    title: 'Steam Shortcuts',
    text: 'Launchers like ES-DE can start Steam games through GameHub or a similar app, but need one .steam '
        'shortcut file per game. Search the store, mark the games, and the files are written into the Save to folder.\n\n'
        'Marked games stay marked across searches, so a batch can come from several.',
  );

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    final shown = {for (final g in _results) g.appid};
    final earlier = [for (final g in _selected.values) if (!shown.contains(g.appid)) g];
    final Widget empty;
    if (_error != null) {
      empty = EmptyState(icon: Icons.wifi_off, line: "Can't reach the Steam store", action: KitAction('Retry', _search, icon: Icons.refresh));
    } else if (_loading) {
      empty = const EmptyState(icon: Icons.search, line: 'Searching');
    } else if (_query.isEmpty) {
      empty = const EmptyState(icon: Icons.search, glyph: PixelIcons.steam, line: 'Search the Steam store by name');
    } else {
      empty = EmptyState(icon: Icons.search_off, line: 'No games match "$_query"');
    }
    return KitScaffold(
      title: 'Steam Shortcuts',
      subtitle: 'Launcher shortcuts for Steam games',
      icon: Icons.videogame_asset_rounded,
      glyph: PixelIcons.steam,
      area: AppArea.tools,
      info: _info,
      body: KitColumns(
        fillEnd: true,
        start: [
          const KitLabel('Search'),
          KitPanel(children: [
            FieldSlot(
              label: 'Search',
              controller: _searchController,
              hint: 'Search Steam',
              icon: Icons.search,
              // The keyboard would cover half a phone on arrival; a pad user is
              // here to type with the on-screen one.
              autofocus: ref.read(inputModeProvider) == InputMode.gamepad,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              trailing: _loading
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.arrow_forward), tooltip: 'Search', onPressed: _search),
            ),
            Slot(label: 'Save to', folder: true, path: _dir, emptyText: 'Choose where the files go', onPick: _creating ? null : _pickDir),
          ]),
          _status,
        ],
        end: [
          ResultsList(
            controller: _scrollController,
            groups: [
              ResultGroup(_query.isEmpty ? 'Results' : 'Results for "$_query"', [for (final g in _results) _row(g)]),
              ResultGroup('Marked earlier', [for (final g in earlier) _row(g)]),
            ],
            selected: {for (final id in _selected.keys) '$id'},
            onSelectionChanged: _creating ? null : _setSelection,
            footer: _loadingMore ? const Padding(padding: EdgeInsets.all(12), child: Center(child: HammerLoader())) : null,
            empty: empty,
          ),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction(n == 0 ? 'Create shortcuts' : 'Create ${_count(n, 'shortcut')}', n == 0 || _creating ? null : _createFiles, icon: Icons.note_add_outlined),
        secondary: n == 0 ? null : KitAction('Clear', _creating ? null : () => setState(_selected.clear), icon: Icons.clear_all, button: PadButton.y),
        hints: const [KitHint(PadButton.a, 'Mark'), KitHint(PadButton.select, 'All'), KitHint(PadButton.b, 'Back')],
        summary: n == 0 ? 'Mark games to create their files' : '${_count(n, 'game')} marked',
      ),
    );
  }

  ResultRow _row(SteamGame g) => ResultRow(id: '${g.appid}', title: g.name, leading: _Banner(g));
}

/// The game's store banner, small: Steam's header.jpg is 460x215.
class _Banner extends StatelessWidget {
  const _Banner(this.game);

  final SteamGame game;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final fallback = ColoredBox(color: Colors.white.withValues(alpha: 0.06), child: Icon(Icons.videogame_asset_rounded, size: 18, color: k.accent.withValues(alpha: 0.7)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(k.buttonRadius.clamp(2, 6).toDouble()),
      child: SizedBox(
        width: 74,
        height: 35,
        child: CachedNetworkImage(imageUrl: game.bannerUrl, fit: BoxFit.cover, placeholder: (_, __) => fallback, errorWidget: (_, __, ___) => fallback),
      ),
    );
  }
}
