import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

const _defaults = AppStyle();
const _swatchSize = 36.0;

Future<String?> _pickImage() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  return result?.files.single.path;
}

/// Settings > Style: the menus' background, the card style and the games
/// layout. [pickImage] stands in for the file picker (tests).
class StyleSettingRows extends ConsumerWidget {
  const StyleSettingRows({super.key, this.pickImage});

  final Future<String?> Function()? pickImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(styleProvider);
    final notifier = ref.read(styleProvider.notifier);
    final backdrop = style.shownBackdrop;
    // The card style's own: what Reset goes back to.
    final own = StyleTokens.forStyle(style.cards).backdrop;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsHeader('Background', top: 0),
      SettingsSegmentedRow<BackdropKind>(
        title: 'Background',
        options: [for (final k in BackdropKind.values) (k, k.label)],
        selected: backdrop.kind,
        changed: backdrop.kind != own.kind,
        onChanged: (k) => notifier.setBackdrop(backdrop.copyWith(kind: k)),
        onReset: () => notifier.setBackdrop(backdrop.copyWith(kind: own.kind)),
      ),
      if (backdrop.kind != BackdropKind.image)
        _ColoursRow(
          top: backdrop.top,
          bottom: backdrop.bottom,
          own: (own.top, own.bottom),
          onPick: (pair) => notifier.setBackdrop(backdrop.copyWith(top: pair.$1, bottom: pair.$2)),
        )
      else
        _PictureRow(
          path: backdrop.imagePath,
          onChoose: () async {
            final path = await (pickImage ?? _pickImage)();
            if (path != null) await notifier.setBackdrop(backdrop.copyWith(imagePath: path));
          },
          onReset: () => notifier.setBackdrop(backdrop.copyWith(clearImage: true)),
        ),
      const SettingsHeader('Cards'),
      SettingsSegmentedRow<CardStyle>(
        title: 'Cards',
        options: [for (final c in CardStyle.values) (c, c.label)],
        selected: style.cards,
        changed: style.cards != _defaults.cards,
        onChanged: notifier.setCards,
        onReset: () => notifier.setCards(_defaults.cards),
      ),
      SettingsSegmentedRow<GameLayout>(
        title: 'Game list',
        options: [for (final l in GameLayout.values) (l, l.label)],
        selected: style.gameLayout,
        changed: style.gameLayout != _defaults.gameLayout,
        onChanged: notifier.setGameLayout,
        onReset: () => notifier.setGameLayout(_defaults.gameLayout),
      ),
    ]);
  }
}

/// The seven presets as swatches: one focus stop each, left/right moves
/// between them, A (or a tap) picks.
class _ColoursRow extends StatelessWidget {
  const _ColoursRow({required this.top, required this.bottom, required this.own, required this.onPick});

  final Color top;
  final Color bottom;

  /// The card style's own pair, which Reset picks.
  final (Color, Color) own;
  final ValueChanged<(Color, Color)> onPick;

  @override
  Widget build(BuildContext context) {
    final changed = (top, bottom) != own;
    return SettingsRowFrame(
      minHeight: changed ? 72 : 64,
      onReset: changed ? () => onPick(own) : null,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SettingsRowText(title: 'Colours', changed: changed),
            const SizedBox(height: 10),
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final e in backdropPresets.entries)
                  _Swatch(
                    name: e.key,
                    top: e.value.$1,
                    bottom: e.value.$2,
                    picked: e.value.$1 == top && e.value.$2 == bottom,
                    onPick: () => onPick(e.value),
                  ),
              ]),
            ),
          ]),
        ),
        if (changed) ...[const SizedBox(width: 16), ResetPill(onPressed: () => onPick(own))],
      ]),
    );
  }
}

class _Swatch extends StatefulWidget {
  const _Swatch({required this.name, required this.top, required this.bottom, required this.picked, required this.onPick});

  final String name;
  final Color top;
  final Color bottom;
  final bool picked;
  final VoidCallback onPick;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = widget.picked || (_focused && settingsFocusShows);
    return Tooltip(
      message: widget.name,
      child: InkResponse(
        key: Key('swatch-${widget.name}'),
        customBorder: const CircleBorder(),
        focusColor: Colors.transparent,
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onPick,
        child: Container(
          width: _swatchSize + 8,
          height: _swatchSize + 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring ? (widget.picked ? scheme.onSurface : scheme.primary) : Colors.transparent, width: 2),
          ),
          child: Container(
            width: _swatchSize,
            height: _swatchSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.5, 0.5],
                colors: [widget.top, widget.bottom],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PictureRow extends StatelessWidget {
  const _PictureRow({required this.path, required this.onChoose, required this.onReset});

  final String? path;
  final VoidCallback onChoose;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final changed = path != null;
    return SettingsRowFrame(
      onTap: onChoose,
      onReset: changed ? onReset : null,
      minHeight: changed ? 72 : 64,
      child: Row(children: [
        Expanded(child: SettingsRowText(title: 'Picture', changed: changed)),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            path == null ? 'None' : p.basename(path!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: scheme.onSurface),
          ),
        ),
        const SizedBox(width: 12),
        const RowPill(label: 'Choose'),
        if (changed) ...[const SizedBox(width: 12), ResetPill(onPressed: onReset)],
      ]),
    );
  }
}
