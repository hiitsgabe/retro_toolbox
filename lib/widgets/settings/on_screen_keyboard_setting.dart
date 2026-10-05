import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';

class OnScreenKeyboardSetting extends ConsumerWidget {
  const OnScreenKeyboardSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Use built-in keyboard'),
      value: ref.watch(settingsProvider.select((s) => s.useOnScreenKeyboard)),
      onChanged: (v) => ref.read(settingsProvider.notifier).setUseOnScreenKeyboard(v),
    );
  }
}
