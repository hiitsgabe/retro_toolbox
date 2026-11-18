import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/widgets/backdrop/backdrop.dart';

/// The Style background behind a menu screen. The scaffold inside must be
/// transparent ([MenuBackdrop.scaffoldColor]) for it to show.
class MenuBackdrop extends ConsumerWidget {
  const MenuBackdrop({super.key, required this.child});
  final Widget child;
  static const scaffoldColor = Colors.transparent;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Backdrop(style: ref.watch(styleProvider.select((s) => s.backdrop)), child: child);
}
