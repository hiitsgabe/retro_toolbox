import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/address_hero.dart';
import 'package:retro_toolbox/widgets/kit/field_slot.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/option_list.dart';

/// What a server's pill says: on wins, then a start in flight, then the last
/// start's error, else off.
ServerState serverStateOf({required bool running, bool starting = false, String? error}) {
  if (running) return ServerState.on;
  if (starting) return ServerState.starting;
  return error != null && error.isNotEmpty ? ServerState.error : ServerState.off;
}

/// "1 transfer", "3 transfers"; null when nothing moves (the pill then says
/// only On).
String? transfersLabel(int n) => n <= 0 ? null : (n == 1 ? '1 transfer' : '$n transfers');

/// Said by a control that cannot change while the server runs.
const lockedWhileRunning = 'Stop the server to change';

/// The primary of every server screen: Start server, Stop server, and
/// nothing to press while a start is in flight.
KitAction serverAction({required bool running, bool starting = false, required VoidCallback? onToggle}) => KitAction(
      running ? 'Stop server' : (starting ? 'Starting…' : 'Start server'),
      starting ? null : onToggle,
      icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
    );

/// Start and stop for a server screen, and whether a start is in flight (the
/// pill's Starting).
mixin ServerToggle<T extends StatefulWidget> on State<T> {
  bool starting = false;

  Future<void> toggleServer({required bool running, required Future<void> Function() start, required Future<void> Function() stop}) async {
    if (starting) return;
    if (running) return stop();
    setState(() => starting = true);
    try {
      await start();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }
}

/// The server's port: a row that opens a field in place, with an error for a
/// port out of range. Locked, it shows the port and why it cannot change.
class PortOption extends StatefulWidget {
  const PortOption({super.key, required this.port, required this.onChanged, this.lockedReason, this.message});

  final int port;
  final ValueChanged<int> onChanged;
  final String? lockedReason;

  /// Under the field: "Use a port above 1024 (21 needs root)".
  final String? message;

  @override
  State<PortOption> createState() => _PortOptionState();
}

class _PortOptionState extends State<PortOption> {
  late final _field = TextEditingController(text: '${widget.port}');
  bool _invalid = false;

  @override
  void didUpdateWidget(PortOption old) {
    super.didUpdateWidget(old);
    // A port loaded after the first build, not one being typed.
    if (widget.port != old.port && int.tryParse(_field.text) != widget.port) _field.text = '${widget.port}';
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _typed(String v) {
    final p = int.tryParse(v);
    final ok = p != null && p > 0 && p < 65536;
    if (ok != !_invalid) setState(() => _invalid = !ok);
    if (ok) widget.onChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lockedReason != null) {
      return OptionAction(title: 'Port', value: '${widget.port}', onTap: null, lockedReason: widget.lockedReason);
    }
    return OptionExpander(title: 'Port', subtitle: '${widget.port}', children: [
      FieldSlot(
        label: 'Port',
        controller: _field,
        icon: Icons.settings_ethernet,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: _typed,
        error: _invalid ? 'Use a port from 1 to 65535' : null,
        message: widget.message,
      ),
    ]);
  }
}

/// One address in the Other addresses sheet, and what can be done with it
/// besides Copy (Save webdav.json for that address).
@immutable
class AddressChoice {
  const AddressChoice(this.address, {this.copyText, this.actions = const []});

  final String address;

  /// What Copy puts on the clipboard; null: [address].
  final String? copyText;
  final List<KitAction> actions;
}

/// Every address this device answers on, for when the first one is not on
/// the console's network. Copy where there is a clipboard.
Future<void> showOtherAddresses(BuildContext context, {required List<AddressChoice> addresses, AppArea? area}) {
  return showKitSheet<void>(
    context,
    area: area,
    title: 'Other addresses',
    // The handheld has no Address setting to point to.
    subtitle: Handheld.current ? null : 'Settings > Network & servers > Address picks the one shown first',
    builder: (context) {
      final t = KitType.of(context);
      return KitPanel(children: [
        for (final (i, a) in addresses.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              Expanded(child: Text(a.address, style: t.mono(15))),
              for (final x in a.actions) TextButton(onPressed: x.onPressed, child: Text(x.label)),
              if (!Handheld.current)
                TextButton(
                  autofocus: i == 0 && a.actions.isEmpty,
                  onPressed: () => Clipboard.setData(ClipboardData(text: a.copyText ?? a.address)),
                  child: const Text('Copy'),
                ),
            ]),
          ),
      ]);
    },
  );
}

/// A kit bottom sheet: a title, a line under it, the content, and Close. The
/// first control inside takes focus where it asks for it; B closes. It keeps
/// the theme of the screen that opened it, in [area] when the caller sits
/// above its KitScaffold (the area's accent in Classic).
Future<T?> showKitSheet<T>(BuildContext context, {required String title, String? subtitle, AppArea? area, required WidgetBuilder builder}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => Theme(data: theme, child: KitArea(area: area, child: Builder(builder: (context) {
      final t = KitType.of(context);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: t.row.copyWith(fontSize: t.size(16))),
            if (subtitle != null) Text(subtitle, style: t.subtitle),
            const SizedBox(height: 10),
            builder(context),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
          ]),
        ),
      );
    }))),
  );
}
