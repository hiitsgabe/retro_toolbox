import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/widgets/settings/accounts_setting.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

/// First-run onboarding: catalog source → download directory & defaults →
/// optional Internet Archive connection.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  static const seenKey = 'setup_wizard_seen';

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(seenKey, true);
  }

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  static const _steps = ['Catalog', 'Downloads', 'Connections'];

  final _catalogService = CatalogService();
  final _urlController = TextEditingController();
  final _pasteController = TextEditingController();

  int _step = 0;
  bool _busy = false;
  bool _catalogReady = false;
  bool _usingExample = false;
  bool _changingCatalog = false;
  String? _catalogSummary;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    final savedUrl = ref.read(settingsProvider).catalogSourceUrl;
    if (savedUrl != null) _urlController.text = savedUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _installCatalog(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _catalogError = null;
    });
    try {
      await action();
      await ref.read(appStateProvider.notifier).reloadConsoles();
      final count = ref.read(appStateProvider).consolesList.length;
      setState(() {
        _catalogReady = count > 0;
        _usingExample = false;
        _changingCatalog = false;
        _catalogSummary = '$count console${count == 1 ? '' : 's'} loaded';
      });
    } catch (e) {
      setState(() {
        _catalogReady = false;
        _catalogError = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a catalog JSON file',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _installCatalog(() => _catalogService.setCatalogFromJson(File(path).readAsStringSync()));
  }

  Future<void> _loadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(url);
    await _installCatalog(() => _catalogService.setCatalogFromUrl(url));
  }

  Future<void> _loadPaste() async {
    final json = _pasteController.text.trim();
    if (json.isEmpty) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _installCatalog(() => _catalogService.setCatalogFromJson(json));
  }

  Future<void> _finish() async {
    await SetupWizardScreen.markSeen();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // A bundled catalog loads asynchronously at startup and may only arrive
    // after this screen is pushed — detect it reactively, not in initState.
    final bundledCount = ref.watch(appStateProvider).consolesList.length;
    if (!_catalogReady && !_changingCatalog && !_busy && _catalogError == null && bundledCount > 0) {
      _catalogReady = true;
      _usingExample = true;
      _catalogSummary = '$bundledCount console${bundledCount == 1 ? '' : 's'} already available';
    }
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(theme),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: switch (_step) {
                      0 => _catalogStep(theme),
                      1 => _downloadsStep(theme),
                      _ => _connectionsStep(theme),
                    },
                  ),
                ),
              ),
            ),
            _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        children: [
          Row(
            children: [
              Image.asset('assets/icon.png', width: 32),
              const SizedBox(width: 12),
              Text('Welcome — quick setup', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                _stepDot(theme, i),
                if (i < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: i < _step ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot(ThemeData theme, int i) {
    final active = i == _step;
    final done = i < _step;
    final color = done || active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color,
          child: done
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text('${i + 1}', style: TextStyle(color: active ? Colors.white : theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
        Text(_steps[i], style: theme.textTheme.labelSmall),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, color: theme.colorScheme.primary), const SizedBox(width: 10), Text(title, style: theme.textTheme.titleMedium)]),
        const SizedBox(height: 6),
        Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _catalogStep(ThemeData theme) {
    // Inputs collapse once a catalog is loaded; the loaded card summarises it
    // and offers a Change button to bring the inputs back.
    final showInputs = !_catalogReady || _usingExample || _changingCatalog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.dataset_outlined, 'Catalog source',
            'Provide a console catalog. Import a JSON file, load one from a URL, or paste it directly.'),
        if (_catalogReady && _usingExample) ...[
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Example catalog included — ${_catalogSummary ?? 'ready to use'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => setState(() => _step = 1),
                    child: const Text('Use example data'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_catalogReady && !_usingExample && !_changingCatalog)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _catalogSummary ?? 'Catalog loaded',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _changingCatalog = true),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ),
        if (showInputs) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Catalog URL',
                    hintText: 'https://…/consoles.json',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  onSubmitted: (_) => _loadUrl(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _loadUrl, child: const Text('Load')),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importFile,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Import from file'),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text('Paste JSON', style: theme.textTheme.bodyMedium),
            children: [
              TextField(
                controller: _pasteController,
                enabled: !_busy,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: '[ { "name": "…", "url": "…" } ]',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(onPressed: _busy ? null : _loadPaste, child: const Text('Use pasted JSON')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_catalogError != null)
            _statusRow(theme, Icons.error_outline, theme.colorScheme.error, _catalogError!),
        ],
      ],
    );
  }

  Widget _downloadsStep(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dir = settings.generalSettings.downloadDir ?? '';
    final autoExtract = settings.generalSettings.autoExtract ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.folder_open, 'Download directory & defaults',
            'Where games are saved, and what happens after a download.'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dir.isEmpty ? 'No directory selected' : dir,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  final picked = await notifier.selectDownloadDirectory();
                  if (picked != null) await notifier.setGeneralSetting(AppSettings.downloadDir, picked);
                },
                child: const Text('Choose'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto extract after download'),
          subtitle: const Text('Unzip archives automatically'),
          value: autoExtract,
          onChanged: (v) => notifier.setGeneralSetting(AppSettings.autoExtract, v),
        ),
      ],
    );
  }

  Widget _connectionsStep(ThemeData theme) {
    // Consoles whose catalog defines a sign-in form (username/password). Listed
    // only here in the wizard so users can connect them during onboarding.
    final settings = ref.watch(settingsProvider);
    final signinConsoles = ref.watch(appStateProvider).consolesList.where((c) => c.authSignin != null).toList();
    bool authed(Console c) =>
        (settings.consoleSettings[c.id]?.authToken?.isNotEmpty ?? false) || ((c.auth?['token'] as String?)?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.hub_outlined, 'Connections (optional)',
            'Connect accounts for restricted sources. You can do this later in Settings.'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const AccountsSetting(),
          ),
        ),
        for (final c in signinConsoles) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExpansionTile(
                key: ValueKey('signin_${c.id}_${authed(c)}'),
                initiallyExpanded: false,
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(c.name),
                subtitle: Text(authed(c) ? 'Connected' : 'Not connected'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [ConsoleAuthSetting(console: c)],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusRow(ThemeData theme, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    final isLast = _step == _steps.length - 1;
    final canNext = _step != 0 || _catalogReady;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(onPressed: _busy ? null : () => setState(() => _step -= 1), child: const Text('Back')),
          const Spacer(),
          // No catalog yet? Let the user move on and add one later in Settings.
          if (_step == 0 && !_catalogReady) ...[
            TextButton(onPressed: _busy ? null : () => setState(() => _step += 1), child: const Text('Skip for now')),
            const SizedBox(width: 8),
          ],
          if (!isLast)
            FilledButton(
              onPressed: canNext && !_busy ? () => setState(() => _step += 1) : null,
              child: const Text('Next'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _finish,
              icon: const Icon(Icons.check),
              label: const Text('Finish'),
            ),
        ],
      ),
    );
  }
}

