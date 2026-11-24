import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/launch_command.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// The command an emulator added with "Just open the file" is started with,
/// for the user to change. Save pops the command (null when it is the
/// default again); Back pops nothing.
class LauncherCommandScreen extends ConsumerStatefulWidget {
  const LauncherCommandScreen({super.key, required this.manual, this.saveLabel = 'Save'});

  final ManualEmulator manual;

  /// "Add" while the emulator is being added.
  final String saveLabel;

  @override
  ConsumerState<LauncherCommandScreen> createState() => _LauncherCommandScreenState();
}

class _LauncherCommandScreenState extends ConsumerState<LauncherCommandScreen> {
  late final String _os = ref.read(launcherOsProvider);
  late final String _default = widget.manual.withCommand(null).commandFor(_os);
  late final _text = TextEditingController(text: widget.manual.commandFor(_os));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _error => _os == 'android' ? parseAndroidCommand(_text.text, package: widget.manual.variant).error : parseDesktopCommand(_text.text).error;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final error = _error;
    final android = _os == 'android';
    final help = android
        ? [
            '-n ${widget.manual.variant}/<activity>   the screen that gets the game (.Name for one in the app)',
            '-a <action>   the intent action (default android.intent.action.VIEW)',
            '-d {rom.uri}   the game as a content URI with a read grant (sent even if left out)',
            '-t <mime>   -c <category>',
            '-e <key> <text>   --ez <key> true|false   --ei / --el <key> <number>   --esa <key> a,b',
            '--activity-clear-task   --activity-clear-top   --activity-no-history',
            'With only {rom.path} in an extra, the game goes as a path in it: the app needs access to your storage.',
          ]
        : [
            'The arguments after ${widget.manual.variant}.',
            'Quote a value with spaces: "{rom}".',
          ];
    return KitScaffold(
      title: 'Launch command',
      subtitle: widget.manual.label,
      icon: Icons.terminal,
      glyph: PixelIcons.games,
      area: AppArea.games,
      body: KitColumns(
        start: [
          const KitLabel('Command'),
          KitPanel(children: [
            FieldSlot(
              key: const ValueKey('launcher-command'),
              label: android ? 'Like am start' : 'Arguments',
              controller: _text,
              autofocus: true,
              icon: Icons.terminal,
              error: error,
              message: error == null ? 'Placeholders: ${commandPlaceholders.join(' ')}' : null,
              onChanged: (_) => setState(() {}),
            ),
          ]),
        ],
        end: [
          const KitLabel('Options'),
          for (final line in help) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line, style: t.subtitle)),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction(widget.saveLabel, error != null ? null : _save, icon: Icons.check),
        secondary: KitAction('Default', _text.text == _default ? null : () => setState(() => _text.text = _default), icon: Icons.restart_alt),
        hints: const [KitHint(PadButton.b, 'Back')],
      ),
    );
  }

  void _save() {
    final text = _text.text.trim();
    Navigator.of(context).pop<({String? command})>((command: text == _default ? null : text));
  }
}

/// Opens the command of [manual] and saves what the user keeps; the session
/// and detection follow, as on an add.
Future<void> editManualCommand(BuildContext context, WidgetRef ref, ManualEmulator manual) async {
  final r = await Navigator.of(context).push<({String? command})>(MaterialPageRoute(builder: (_) => LauncherCommandScreen(manual: manual)));
  if (r == null) return;
  await ref.read(addManualEmulatorProvider)(manual.withCommand(r.command));
}
