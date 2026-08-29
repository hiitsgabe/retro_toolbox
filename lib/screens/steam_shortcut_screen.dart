import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/steam_service.dart';

/// Search the Steam store, multi-select games, and write `.steam` shortcut
/// files (ES-DE format) into a chosen folder.
class SteamShortcutScreen extends StatefulWidget {
  const SteamShortcutScreen({super.key});

  static const _lastDirKey = 'steam_shortcut_last_dir';

  @override
  State<SteamShortcutScreen> createState() => _SteamShortcutScreenState();
}

class _SteamShortcutScreenState extends State<SteamShortcutScreen> {
  final _steamService = SteamService();
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_hasMore && !_loadingMore && !_loading && _scrollController.position.extentAfter < 400) {
        _loadMore();
      }
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

  Future<void> _createFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select destination folder',
      initialDirectory: prefs.getString(SteamShortcutScreen._lastDirKey),
    );
    if (folder == null || !mounted) return;
    await prefs.setString(SteamShortcutScreen._lastDirKey, folder);

    setState(() => _creating = true);
    final games = _selected.values.toList();
    final errors = await _steamService.createShortcuts(games, folder);
    if (!mounted) return;
    setState(() => _creating = false);

    if (errors.isEmpty) {
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${games.length} shortcut${games.length == 1 ? '' : 's'} in $folder')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${errors.length} of ${games.length} failed: ${errors.values.first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Steam Shortcuts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search Steam games…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty ? null : _selectionBar(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _search, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _loading
              ? 'Searching…'
              : _query.isEmpty
                  ? 'Search for games to create .steam shortcut files'
                  : 'No results for "$_query"',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        // Steam header.jpg is 460x215; leave room for the title strip.
        childAspectRatio: 1.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return const Center(child: CircularProgressIndicator());
        }
        return _gameCard(theme, _results[i]);
      },
    );
  }

  Widget _gameCard(ThemeData theme, SteamGame game) {
    final selected = _selected.containsKey(game.appid);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        selected ? _selected.remove(game.appid) : _selected[game.appid] = game;
      }),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor.withValues(alpha: 0.2),
            width: selected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: game.bannerUrl,
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(color: theme.colorScheme.surfaceContainerHighest),
                errorWidget: (context, _, __) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.videogame_asset_rounded, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Text(
                    game.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
        child: Row(
          children: [
            Text('${_selected.length} selected', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            TextButton(onPressed: _creating ? null : () => setState(() => _selected.clear()), child: const Text('Clear')),
            const Spacer(),
            FilledButton.icon(
              onPressed: _creating ? null : _createFiles,
              icon: _creating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('Create files'),
            ),
          ],
        ),
      ),
    );
  }
}
