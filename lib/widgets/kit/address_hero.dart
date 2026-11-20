import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

enum ServerState { off, starting, on, error }

/// A labelled value under the address: Host, Port.
@immutable
class AddressField {
  const AddressField(this.label, this.value);

  final String label;
  final String value;
}

/// A server's address, the first thing read on its screen: the state pill
/// (Off, Starting, On with what is happening, Error), the address large in
/// mono so it can be typed on the other device, its scheme and path small
/// around it, and the parts typed apart (host, port). Copy is offered where
/// there is a clipboard to paste from (not on the Linux handheld).
class AddressHero extends StatelessWidget {
  const AddressHero({
    super.key,
    required this.state,
    required this.address,
    this.label = 'Address',
    this.stateDetail,
    this.prefix,
    this.suffix,
    this.fields = const [],
    this.otherAddresses = 0,
    this.onOtherAddresses,
    this.onChange,
    this.changeLabel = 'Change',
    this.copyable,
    this.placeholder = 'Start the server to see its address',
  });

  /// A URL: the scheme and the path small, host and port large.
  factory AddressHero.url(String url, {Key? key, required ServerState state, String? stateDetail, int otherAddresses = 0, VoidCallback? onOtherAddresses, bool? copyable}) {
    final u = Uri.tryParse(url);
    final scheme = u == null || u.scheme.isEmpty ? null : '${u.scheme}://';
    final host = u == null || u.host.isEmpty ? url : (u.hasPort ? '${u.host}:${u.port}' : u.host);
    final path = u == null || u.host.isEmpty ? '' : '${u.path}${u.hasQuery ? '?${u.query}' : ''}';
    return AddressHero(
      key: key,
      state: state,
      stateDetail: stateDetail,
      address: host,
      prefix: scheme,
      suffix: path.isEmpty || path == '/' ? null : path,
      otherAddresses: otherAddresses,
      onOtherAddresses: onOtherAddresses,
      copyable: copyable,
    );
  }

  /// Typed apart on the other device (Tinfoil's host and port fields).
  factory AddressHero.hostPort({Key? key, required ServerState state, required String host, required int port, String? stateDetail, int otherAddresses = 0, VoidCallback? onOtherAddresses, bool? copyable}) =>
      AddressHero(
        key: key,
        state: state,
        stateDetail: stateDetail,
        address: '$host:$port',
        fields: [AddressField('Host', host), AddressField('Port', '$port')],
        otherAddresses: otherAddresses,
        onOtherAddresses: onOtherAddresses,
        copyable: copyable,
      );

  /// Where this device sends to (FBI: the console's address, typed here).
  factory AddressHero.pushTarget(
          {Key? key, required ServerState state, required String address, String label = 'Send to', String? stateDetail, required VoidCallback? onChange, String placeholder = 'Not set yet'}) =>
      AddressHero(key: key, state: state, stateDetail: stateDetail, address: address, label: label, onChange: onChange, copyable: false, placeholder: placeholder);

  /// The address a config file carries to the console (FPKGi, JDKV).
  factory AddressHero.configFile({Key? key, required ServerState state, required String address, required String fileName, String? stateDetail, bool? copyable}) =>
      AddressHero(key: key, state: state, stateDetail: stateDetail, address: address, label: 'In $fileName', copyable: copyable);

  final ServerState state;

  /// The value shown large.
  final String address;
  final String label;

  /// After the state in the pill: "1 transfer".
  final String? stateDetail;
  final String? prefix;
  final String? suffix;
  final List<AddressField> fields;

  /// More addresses this device has: "Other addresses (n)" opens them.
  final int otherAddresses;
  final VoidCallback? onOtherAddresses;
  final VoidCallback? onChange;
  final String changeLabel;

  /// Null: wherever there is a clipboard (not the Linux handheld).
  final bool? copyable;

  /// Said in place of an empty [address] (a server that is off has none yet).
  final String placeholder;

  static String stateWord(ServerState s) => switch (s) {
        ServerState.off => 'Off',
        ServerState.starting => 'Starting',
        ServerState.on => 'On',
        ServerState.error => 'Error',
      };

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final copy = copyable ?? !Handheld.current;
    final whole = '${prefix ?? ''}$address${suffix ?? ''}';
    final tone = switch (state) {
      ServerState.on => k.success,
      ServerState.starting => k.warning,
      ServerState.error => k.error,
      ServerState.off => t.muted,
    };
    final detail = stateDetail;
    final pill = Container(
      key: const ValueKey('kit-server-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: tone)),
        const SizedBox(width: 6),
        Text(detail == null ? stateWord(state) : '${stateWord(state)} · $detail', style: t.subtitle.copyWith(color: tone, fontWeight: FontWeight.w700)),
      ]),
    );
    final small = t.mono(13).copyWith(color: t.muted);
    final big = t.mono(t.portrait ? 22 : 23);
    final empty = address.isEmpty;
    final value = empty
        ? Text(placeholder, key: const ValueKey('kit-address-placeholder'), style: t.body.copyWith(color: t.muted))
        : Opacity(
            opacity: state == ServerState.on ? 1 : 0.5,
            child: LayoutBuilder(builder: (context, box) {
              final whole = TextSpan(children: [
                if (prefix != null) TextSpan(text: prefix, style: small),
                TextSpan(text: address, style: big),
                if (suffix != null) TextSpan(text: suffix, style: small),
              ]);
              // A path that does not fit goes whole under the address, rather
              // than wrapping after one of its slashes.
              if (suffix == null || _fits(context, whole, box.maxWidth)) return Text.rich(whole, key: const ValueKey('kit-address'), softWrap: true);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text.rich(
                  TextSpan(children: [
                    if (prefix != null) TextSpan(text: prefix, style: small),
                    TextSpan(text: address, style: big),
                  ]),
                  key: const ValueKey('kit-address'),
                  softWrap: true,
                ),
                Text(suffix!, key: const ValueKey('kit-address-path'), style: small),
              ]);
            }),
          );
    return KitPanel(padding: const EdgeInsets.all(14), children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        pill,
        const SizedBox(height: 10),
        Text(label.toUpperCase(), style: t.label),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: value),
          if (onChange != null) _SmallButton(label: changeLabel, onPressed: onChange),
          if (copy && !empty && fields.isEmpty && onChange == null) _CopyButton(text: whole),
        ]),
        if (fields.isNotEmpty && !empty) ...[
          const SizedBox(height: 8),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                SizedBox(width: 48, child: Text(f.label, style: t.subtitle)),
                Expanded(child: Text(f.value, style: t.mono(15))),
                if (copy) _CopyButton(text: f.value),
              ]),
            ),
        ],
        if (otherAddresses > 0) ...[
          const SizedBox(height: 4),
          _SmallButton(label: 'Other addresses ($otherAddresses)', onPressed: onOtherAddresses),
        ],
      ]),
    ]);
  }
}

bool _fits(BuildContext context, InlineSpan span, double width) {
  if (!width.isFinite) return true;
  final tp = TextPainter(
    text: TextSpan(style: DefaultTextStyle.of(context).style, children: [span]),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w <= width;
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Text(label),
      );
}

/// Copy, then "Copied" for a moment: the result shows where it was asked for.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => _SmallButton(label: _copied ? 'Copied' : 'Copy', onPressed: _copy);
}
