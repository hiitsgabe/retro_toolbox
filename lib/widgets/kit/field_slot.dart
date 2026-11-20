import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';

/// A typed input of a tool (a link, a name, a search), drawn like a [Slot]:
/// the icon, the label over the value, and [trailing] (Paste, a spinner) at
/// the end. [error] replaces [message] under the field; [message] is shown
/// whole, never cut, so a pasted link reads in full.
class FieldSlot extends StatelessWidget {
  const FieldSlot({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.glyph,
    this.trailing,
    this.error,
    this.message,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final PixelGlyph? glyph;
  final Widget? trailing;
  final String? error;
  final String? message;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final error = this.error, message = this.message;
    final under = error ?? message;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 8).toDouble())),
            child: k.pixelIcons && glyph != null ? PixelIcon(glyph!, size: 18, color: k.accent) : Icon(icon ?? Icons.edit_outlined, size: 18, color: k.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                enabled: enabled,
                autocorrect: false,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                inputFormatters: inputFormatters,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: t.row,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: t.row.copyWith(color: t.muted, fontWeight: FontWeight.w400),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: k.accent, width: 2)),
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
              if (under != null && under.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(under, key: ValueKey(error != null ? 'kit-field-error' : 'kit-field-message'), style: t.subtitle.copyWith(color: error != null ? k.error : null)),
                ),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ]),
      ),
    );
  }
}
