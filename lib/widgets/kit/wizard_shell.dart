import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/action_bar.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/kit_scaffold.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';

/// The frame of every wizard: the wizard's [name], "Step n of m · Name" and
/// the progress in the header, the step's [body], and the action bar with
/// Back on B and Next on Start. Navigation never goes in the header.
class WizardShell extends StatelessWidget {
  const WizardShell({
    super.key,
    required this.name,
    required this.step,
    required this.count,
    required this.stepName,
    required this.body,
    required this.onNext,
    this.onBack,
    this.nextLabel = 'Next',
    this.backLabel = 'Back',
    this.summary,
    this.hints = const [],
    this.icon,
    this.glyph,
    this.info,
    this.area,
  });

  final String name;

  /// From 0. Steps that do not apply are skipped, not counted.
  final int step;
  final int count;
  final String stepName;
  final Widget body;

  /// Null: Next is disabled (and Start does nothing).
  final VoidCallback? onNext;

  /// B and the Back button. Null: B leaves the wizard (the route pops) and
  /// no Back button shows.
  final VoidCallback? onBack;
  final String nextLabel;
  final String backLabel;
  final String? summary;
  final List<KitHint> hints;
  final IconData? icon;
  final PixelGlyph? glyph;
  final Widget? info;
  final AppArea? area;

  /// "Step 2 of 3 · Downloads".
  String get stepLine => 'Step ${step + 1} of $count · $stepName';

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return PopScope(
      canPop: back == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: KitScaffold(
        title: name,
        subtitle: stepLine,
        icon: icon,
        glyph: glyph,
        info: info,
        area: area,
        showBack: false,
        progress: KitProgress(step, count),
        body: body,
        actionBar: ActionBar(
          primary: KitAction(nextLabel, onNext),
          secondary: back == null ? null : KitAction(backLabel, back, button: PadButton.b),
          hints: hints,
          summary: summary,
        ),
      ),
    );
  }
}
