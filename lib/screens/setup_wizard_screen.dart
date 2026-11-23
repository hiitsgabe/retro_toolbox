import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/console_auth_setting.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:retro_toolbox/widgets/settings/launcher_setting.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Where the console catalog comes from: the one in the app, or the user's.
enum _Source { builtIn, link, file, paste }

/// First-run onboarding: catalog source, download directory and defaults,
/// then optional logins and LaunchBox metadata.
class SetupWizardScreen extends ConsumerStatefulWidget {
  /// Start on this step. Lets tests and screenshots render later steps.
  @visibleForTesting
  final int initialStep;

  const SetupWizardScreen({super.key, this.initialStep = 0});

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

  late int _step = widget.initialStep;
  bool _busy = false;
  String? _catalogError;
  _Source _source = _Source.builtIn;

  /// Where the catalog in use came from, when this screen loaded one; null:
  /// the one that was there when it opened (the built-in one on a first run).
  _Source? _loaded;
  String? _loadedFile;

  /// Only a choice until Finish: the import is a 110 MB download.
  bool _wantLaunchbox = false;

  /// Only a choice until Finish, which pops with it: the caller opens the
  /// launcher wizard once this route is gone.
  bool _wantLauncher = false;

  /// Holds the step's body, so a new step can take focus from the button
  /// that moved to it.
  final _body = FocusNode(debugLabel: 'setup-step');

  @override
  void initState() {
    super.initState();
    final savedUrl = ref.read(settingsProvider).catalogSourceUrl;
    if (savedUrl != null) _urlController.text = savedUrl;
    // Whether metadata is already on, for the Connections step.
    ref.read(launchboxProvider.notifier).refresh();
  }

  @override
  void dispose() {
    _body.dispose();
    _urlController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  /// Moves to [step] and, with a pad, onto its first control: focus left on
  /// the (i) or the bar would make the d-pad hunt for the question.
  void _go(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      // Not a text field: on a pad that opens the keyboard before the user
      // has chosen to type.
      bool field(FocusNode n) => n.context?.findAncestorWidgetOfExactType<EditableText>() != null;
      _body.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal && !field(n)).firstOrNull?.requestFocus();
    });
  }

  Future<void> _installCatalog(Future<void> Function() action, _Source? from) async {
    setState(() {
      _busy = true;
      _catalogError = null;
    });
    try {
      await action();
      await ref.read(appStateProvider.notifier).reloadConsoles();
      if (mounted) setState(() => _loaded = from);
    } catch (e) {
      if (mounted) setState(() => _catalogError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final path = await pickFile(context, title: 'Select a catalog JSON file', extensions: ['json']);
    if (path == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _installCatalog(() => _catalogService.setCatalogFromJson(File(path).readAsStringSync()), _Source.file);
    if (mounted && _loaded == _Source.file) setState(() => _loadedFile = path);
  }

  Future<void> _loadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(url);
    await _installCatalog(() => _catalogService.setCatalogFromUrl(url), _Source.link);
  }

  Future<void> _loadPaste() async {
    final json = _pasteController.text.trim();
    if (json.isEmpty) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _installCatalog(() => _catalogService.setCatalogFromJson(json), _Source.paste);
  }

  /// Back to the catalog that comes with the app, after loading another.
  Future<void> _useBuiltIn() async {
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _installCatalog(_catalogService.resetCatalog, null);
  }

  void _choose(_Source source) {
    setState(() {
      _source = source;
      _catalogError = null;
    });
    if (source == _Source.builtIn && _loaded != null) _useBuiltIn();
  }

  // B on step 0 and Finish both leave; a second press before markSeen
  // returns must not pop the route below.
  bool _leaving = false;

  Future<void> _finish() => _leave(importMetadata: true);

  /// B on step 0 leaves as a skip: nothing is imported, and the launcher
  /// wizard is not asked for. Pops true when Finish asks for it.
  Future<void> _leave({bool importMetadata = false}) async {
    if (_leaving) return;
    _leaving = true;
    await SetupWizardScreen.markSeen();
    if (importMetadata && _wantLaunchbox && mounted) await _importLaunchbox();
    if (mounted) Navigator.of(context).pop(importMetadata && _wantLauncher);
  }

  Future<void> _importLaunchbox() async {
    final launchbox = ref.read(launchboxProvider.notifier);
    // The catalog may have changed since the screen opened, and with it the
    // platforms to import.
    await launchbox.refresh();
    if (!mounted) return;
    final s = ref.read(launchboxProvider);
    if (s.manifest != null) return;
    if (s.wanted.isEmpty) {
      // Nothing to import: say so. A SnackBar shown now stays up on the
      // screen the wizard closes to.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(noLaunchboxConsolesMessage)));
      return;
    }
    launchbox.startImport(ref, context);
  }

  /// B: previous step; on the first step, leave as skipped.
  void _back() {
    if (_busy) return;
    if (_step > 0) {
      _go(_step - 1);
    } else {
      _leave();
    }
  }

  /// The catalog in use is the one the chosen row stands for.
  bool _ready(int count) => count > 0 && (_source == _Source.builtIn ? _loaded == null : _loaded == _source);

  /// Start on the Catalog step: on to the next step once the chosen catalog
  /// is in, else what the chosen row needs (load the link, pick the file).
  /// With no catalog at all, Skip for now: one can be added in Settings.
  KitAction _catalogPrimary(int count) {
    void next() => _go(1);
    if (_ready(count)) return KitAction('Next', next);
    return switch (_source) {
      _Source.builtIn => KitAction('Skip for now', next),
      _Source.link => KitAction('Load', _urlController.text.trim().isEmpty ? null : _loadUrl),
      _Source.file => KitAction('Choose file', _importFile),
      _Source.paste => KitAction('Use pasted JSON', _pasteController.text.trim().isEmpty ? null : _loadPaste),
    };
  }

  static String _sourceName(_Source s) => switch (s) {
        _Source.builtIn => 'Built-in',
        _Source.link => 'From a link',
        _Source.file => 'From a file',
        _Source.paste => 'Pasted',
      };

  @override
  Widget build(BuildContext context) {
    final consoles = ref.watch(appStateProvider).consolesList;
    final count = consoles.length;
    final KitAction primary = switch (_step) {
      0 => _catalogPrimary(count),
      1 => KitAction('Next', () => _go(2)),
      _ => KitAction('Finish', _finish),
    };
    final step = switch (_step) {
      0 => _catalogStep(context, consoles),
      1 => _downloadsStep(context),
      _ => _connectionsStep(context, consoles),
    };
    return WizardShell(
      name: 'Games Library setup',
      step: _step,
      count: _steps.length,
      stepName: _steps[_step],
      icon: Icons.download,
      glyph: PixelIcons.games,
      area: AppArea.games,
      info: const InfoButton(
        icon: Icons.download,
        title: 'Games Library setup',
        text: 'Three quick choices before the first visit: where the consoles come from, where games are saved, and the logins and game info '
            'you want. The built-in catalog works out of the box; you can switch to your own JSON later in Settings > Library. '
            'Everything here can be changed later in Settings.',
      ),
      body: Focus(focusNode: _body, skipTraversal: true, canRequestFocus: false, child: step),
      onNext: _busy ? null : primary.onPressed,
      nextLabel: primary.label,
      onBack: _back,
      backLabel: _step == 0 ? 'Not now' : 'Back',
      backEnabled: !_busy,
      summary: _step == 0 && _ready(count) ? '${_sourceName(_source)} · $count console${count == 1 ? '' : 's'}' : null,
    );
  }

  Widget _catalogStep(BuildContext context, List<Console> consoles) {
    final count = consoles.length;
    final builtInLine = _loaded == null && count > 0 ? '$count console${count == 1 ? '' : 's'}, works right away' : 'The catalog that comes with the app';
    final choices = <(_Source, String, String)>[
      (_Source.builtIn, 'Built-in catalog', builtInLine),
      (_Source.link, 'From a link', 'A catalog JSON URL'),
      (_Source.file, 'From a file', 'Import a JSON file'),
      // A handheld has no clipboard worth pasting from.
      if (!Handheld.current) (_Source.paste, 'Paste JSON', 'Type or paste it here'),
    ];
    final input = switch (_source) {
      _Source.builtIn => null,
      _Source.link => KitPanel(children: [
          FieldSlot(
            label: 'Catalog URL',
            controller: _urlController,
            hint: 'https://…/consoles.json',
            icon: Icons.link,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _loadUrl(),
          ),
        ]),
      _Source.file => KitPanel(children: [
          Slot(
            label: 'Catalog file',
            value: _loaded == _Source.file && _loadedFile != null ? p.basename(_loadedFile!) : null,
            emptyText: 'Import from file',
            onPick: _busy ? null : _importFile,
          ),
        ]),
      _Source.paste => KitPanel(children: [
          FieldSlot(
            label: 'Catalog JSON',
            controller: _pasteController,
            hint: '[ { "name": "…", "url": "…" } ]',
            icon: Icons.data_object,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
        ]),
    };
    final status = _busy
        ? const StatusPanel.working(items: [WorkItem('Loading the catalog')])
        : _catalogError != null
            ? StatusPanel.error(line: "Couldn't load that catalog", details: _catalogError)
            : _loaded != null && _ready(count)
                ? StatusPanel.done(summary: '$count console${count == 1 ? '' : 's'} loaded')
                : const StatusPanel.hidden();
    return KitColumns(
      start: [
        const KitLabel('Where the consoles come from'),
        OptionList(children: [
          for (final (i, (source, title, line)) in choices.indexed)
            OptionChoice<_Source>(
              autofocus: i == 0,
              title: title,
              subtitle: line,
              value: source,
              groupValue: _source,
              onSelected: _busy ? null : _choose,
            ),
        ]),
        if (input != null) input,
      ],
      // Status first in its column: under the choices it would load below
      // the fold on a short screen.
      end: [status, const KitLabel("You'll get"), _ConsolePreview(consoles: consoles)],
    );
  }

  Widget _downloadsStep(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dir = settings.generalSettings.downloadDir ?? '';
    final autoExtract = settings.generalSettings.autoExtract ?? true;
    return KitColumns(start: [
      const KitLabel('Where games go'),
      KitPanel(children: [
        Slot(
          label: 'Download folder',
          path: dir.isEmpty ? null : dir,
          emptyText: 'Choose a folder',
          folder: true,
          autofocus: true,
          onPick: () async {
            final picked = await pickDirectory(context, title: 'Select download folder');
            if (picked == null) return;
            await notifier.saveDownloadDirectory(picked);
            await notifier.setGeneralSetting(AppSettings.downloadDir, picked);
          },
        ),
      ]),
      const KitLabel('After a download'),
      OptionList(children: [
        OptionToggle(
          title: 'Extract after download',
          subtitle: 'Unzip archives automatically',
          value: autoExtract,
          onChanged: (v) => notifier.setGeneralSetting(AppSettings.autoExtract, v),
        ),
      ]),
    ]);
  }

  Widget _connectionsStep(BuildContext context, List<Console> consoles) {
    // Consoles whose catalog defines a sign-in form (username/password). Listed
    // only here in the wizard so users can connect them during onboarding.
    final settings = ref.watch(settingsProvider);
    final signinConsoles = consoles.where((c) => c.authSignin != null).toList();
    // The IA login only matters when some console's games come from IA.
    final needsIa = consoles.any((c) => c.usesInternetArchive);
    bool authed(Console c) =>
        (settings.consoleSettings[c.id]?.authToken?.isNotEmpty ?? false) || ((c.auth?['token'] as String?)?.isNotEmpty ?? false);
    final metadataOn = ref.watch(launchboxProvider).manifest != null;
    final launcherOn = ref.watch(launchConfigProvider.select((c) => c.enabled));
    String state(bool on) => on ? 'Connected' : 'Not connected';

    final logins = [
      if (needsIa)
        OptionAction(
          title: 'Internet Archive',
          subtitle: state(settings.hasIaCredentials),
          onTap: () => showKitSheet<void>(context, area: AppArea.games, title: 'Internet Archive', subtitle: 'For consoles whose games come from it', builder: (_) => const IaCredentialsSetting()),
        ),
      for (final c in signinConsoles)
        OptionAction(
          title: c.name,
          subtitle: state(authed(c)),
          onTap: () => showKitSheet<void>(context, area: AppArea.games, title: '${c.name} sign-in', subtitle: 'Needed to download its games', builder: (_) => ConsoleAuthSetting(console: c)),
        ),
    ];
    return KitColumns(
      start: [
        const KitLabel('Logins'),
        if (logins.isEmpty)
          KitPanel(children: [
            Padding(padding: const EdgeInsets.all(12), child: Text('No accounts needed for this catalog.', style: KitType.of(context).body)),
          ])
        else ...[
          OptionList(children: logins),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Optional. You can sign in later in Settings.', style: KitType.of(context).subtitle),
          ),
        ],
      ],
      end: [
        const KitLabel('Game info'),
        OptionList(children: [
          OptionToggle(
            title: 'Download LaunchBox metadata',
            subtitle: metadataOn ? 'Already on' : 'Ratings, genres, descriptions and artwork. About 110 MB, once.',
            value: metadataOn || _wantLaunchbox,
            onChanged: metadataOn ? null : (v) => setState(() => _wantLaunchbox = v),
          ),
          if (ref.watch(launcherCardProvider))
            OptionToggle(
              title: 'Launcher mode',
              subtitle: launcherOn ? 'Already on' : 'Play opens the games you have in an emulator. Set up right after this.',
              value: launcherOn || _wantLauncher,
              onChanged: launcherOn ? null : (v) => setState(() => _wantLauncher = v),
            ),
        ]),
      ],
    );
  }
}

/// The consoles the catalog in use brings, as small tags.
class _ConsolePreview extends StatelessWidget {
  const _ConsolePreview({required this.consoles});

  static const _shown = 18;

  final List<Console> consoles;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final more = consoles.length - _shown;
    Widget tag(String s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 6).toDouble())),
          child: Text(s, style: t.subtitle.copyWith(color: t.ink)),
        );
    return KitPanel(padding: const EdgeInsets.all(12), divided: false, children: [
      if (consoles.isEmpty)
        Text('No consoles yet. A catalog can be added later in Settings > Library.', style: t.body)
      else ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in consoles.take(_shown)) tag(c.name),
          if (more > 0) tag('+$more more'),
        ]),
        const SizedBox(height: 10),
        Text('You can change it later in Settings > Library.', style: t.subtitle),
      ],
    ]);
  }
}
