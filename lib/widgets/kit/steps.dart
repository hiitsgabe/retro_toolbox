import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// How to connect: the steps needed every time, numbered, and the one-time
/// setup ([firstTime]) folded under one row that opens it in place.
class Steps extends StatefulWidget {
  const Steps({super.key, required this.steps, this.firstTime = const [], this.firstTimeLabel = 'First time setup'});

  /// Keep these to the few lines needed on every visit.
  final List<String> steps;
  final List<String> firstTime;
  final String firstTimeLabel;

  @override
  State<Steps> createState() => _StepsState();
}

class _StepsState extends State<Steps> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    return KitPanel(children: [
      if (widget.steps.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: _Numbered(widget.steps)),
      if (widget.firstTime.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            expanded: _open,
            child: InkWell(
              borderRadius: kitRowRadius(k),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 42),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(widget.firstTimeLabel, style: t.row.copyWith(fontSize: t.size(13)))),
                    Text('${widget.firstTime.length}', style: t.subtitle),
                    const SizedBox(width: 4),
                    AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: Icon(Icons.expand_more, size: 20, color: t.muted)),
                  ]),
                ),
              ),
            ),
          ),
          if (_open) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: _Numbered(widget.firstTime, key: const ValueKey('kit-steps-first-time'))),
        ]),
    ]);
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered(this.steps, {super.key});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final side = t.size(11) + 9;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: k.accent.withValues(alpha: 0.16)),
              child: Text('${i + 1}', style: TextStyle(fontFamily: k.titleFont, fontWeight: FontWeight.w700, fontSize: t.size(11), height: 1, color: k.accent)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 1), child: Text(steps[i], style: t.body))),
          ]),
        ),
    ]);
  }
}
