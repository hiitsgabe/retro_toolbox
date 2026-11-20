import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/action_bar.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/status_panel.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// Where a wizard is: step [index] (from 0) of [count].
@immutable
class KitProgress {
  const KitProgress(this.index, this.count);

  final int index;
  final int count;
}

/// The frame of every tool, server and kit screen: a one-row header (back,
/// icon, title, one-line subtitle, the (i), trailing actions), the body, and
/// the [ActionBar] fixed at the bottom with Start bound to its primary.
/// [area] gives the screen its area's accent in styles that use one.
class KitScaffold extends StatelessWidget {
  const KitScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.glyph,
    this.info,
    this.actions = const [],
    required this.body,
    this.actionBar,
    this.area,
    this.onBack,
    this.showBack = true,
    this.progress,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final String title;

  /// One line, about 50 characters at most; the long text goes in [info].
  final String? subtitle;

  /// The screen's icon; [glyph] in styles drawn with pixel icons.
  final IconData? icon;
  final PixelGlyph? glyph;

  /// The (i): an InfoButton.
  final Widget? info;

  /// Icon buttons after the (i).
  final List<Widget> actions;
  final Widget body;
  final ActionBar? actionBar;
  final AppArea? area;

  /// Null: pop the route.
  final VoidCallback? onBack;
  final bool showBack;

  /// Wizards: the step, shown as segments in the header (a bar under it in
  /// portrait). Navigation never goes in the header.
  final KitProgress? progress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return KitArea(
      area: area,
      child: Builder(builder: (context) {
        final portrait = DeviceClass.of(context) == DeviceClass.portrait;
        final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
        final progress = this.progress;
        final scaffold = Scaffold(
          body: SafeArea(
            bottom: actionBar == null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _KitHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                glyph: glyph,
                info: info,
                actions: actions,
                onBack: showBack && (onBack != null || canPop) ? (onBack ?? () => Navigator.of(context).maybePop()) : null,
                progress: portrait ? null : progress,
              ),
              if (portrait && progress != null) _ProgressBar(progress: progress),
              Expanded(child: Padding(padding: padding, child: body)),
            ]),
          ),
          bottomNavigationBar: actionBar,
        );
        return KitBarActions(bar: actionBar, child: scaffold);
      }),
    );
  }
}

class _KitHeader extends StatelessWidget {
  const _KitHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.glyph,
    required this.info,
    required this.actions,
    required this.onBack,
    required this.progress,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final PixelGlyph? glyph;
  final Widget? info;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final KitProgress? progress;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final subtitle = this.subtitle;
    final progress = this.progress;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack == null ? 16 : 4, t.portrait ? 8 : 4, 8, t.portrait ? 6 : 2),
      child: Row(children: [
        if (onBack != null)
          IconButton(
            key: const ValueKey('kit-back'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: k.pixelIcons ? const PixelIcon(PixelIcons.back, size: 20) : const Icon(Icons.arrow_back, size: 22),
          ),
        if (icon != null || glyph != null) ...[KitIconTile(icon: icon, glyph: glyph), const SizedBox(width: 10)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t.caps(title), style: t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, key: const ValueKey('kit-subtitle'), style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (progress != null) ...[const SizedBox(width: 10), _Segments(progress: progress)],
        if (info != null) ...[const SizedBox(width: 4), info!],
        ...actions,
      ]),
    );
  }
}

/// A screen's icon on a tile of its accent: the pixel glyph on the accent in
/// styles drawn with pixel icons, else the icon on an accent wash.
class KitIconTile extends StatelessWidget {
  const KitIconTile({super.key, this.icon, this.glyph, this.size = 34});

  final IconData? icon;
  final PixelGlyph? glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final pixel = k.pixelIcons && glyph != null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pixel ? k.accent : k.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 10).toDouble()),
      ),
      child: pixel ? PixelIcon(glyph!, size: size * 0.7, color: k.onAccent) : Icon(icon ?? Icons.widgets_outlined, size: size * 0.55, color: k.accent),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.progress});

  final KitProgress progress;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    return Row(key: const ValueKey('kit-progress'), mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < progress.count; i++)
        Container(
          width: 22,
          height: 5,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
          decoration: BoxDecoration(color: i <= progress.index ? k.accent : Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(2)),
        ),
    ]);
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final KitProgress progress;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final f = progress.count <= 0 ? 0.0 : ((progress.index + 1) / progress.count).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: ClipRRect(
        key: const ValueKey('kit-progress'),
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
            FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: ColoredBox(color: k.accent)),
          ]),
        ),
      ),
    );
  }
}

/// Whether kit bodies stack into one column here (portrait).
bool kitStacked(BuildContext context) => DeviceClass.of(context) == DeviceClass.portrait || MediaQuery.sizeOf(context).width < 520;

/// The kit's two-column body: [start] (inputs and options, or the server's
/// address) on the left and [end] (status, steps) on the right, each column
/// scrolling on its own; one scrolling column in portrait, with [end] first
/// when [endFirstWhenStacked] (a running tool's status strip). [fillEnd]: [end]
/// is a single widget that scrolls itself (a results list) and fills its
/// column, or the rest of the screen when stacked.
class KitColumns extends StatelessWidget {
  const KitColumns({super.key, required this.start, this.end = const [], this.endFirstWhenStacked = false, this.fillEnd = false, this.startFlex = 6, this.endFlex = 5});

  final List<Widget> start;
  final List<Widget> end;
  final bool endFirstWhenStacked;
  final bool fillEnd;
  final int startFlex;
  final int endFlex;

  static List<Widget> _spaced(Iterable<Widget> children) {
    final out = <Widget>[];
    for (final c in children) {
      // A hidden status panel takes no slot (and no gap).
      if (c is StatusPanel && c.isHidden) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: kitGap));
      out.add(c);
    }
    return out;
  }

  static Widget _column(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children)),
      );

  @override
  Widget build(BuildContext context) {
    assert(!fillEnd || end.length == 1, 'fillEnd takes one widget that scrolls itself');
    if (kitStacked(context)) {
      if (fillEnd) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(flex: 2, child: _column(start)),
          const SizedBox(height: kitGap),
          Expanded(flex: 3, child: end.single),
        ]);
      }
      return _column(endFirstWhenStacked ? [...end, ...start] : [...start, ...end]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: startFlex, child: _column(start)),
      if (end.isNotEmpty) ...[
        const SizedBox(width: 10),
        Expanded(flex: endFlex, child: fillEnd ? Padding(padding: const EdgeInsets.only(top: 4), child: end.single) : _column(end)),
      ],
    ]);
  }
}
