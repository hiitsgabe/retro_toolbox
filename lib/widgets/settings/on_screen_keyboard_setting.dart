import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';

class OnScreenKeyboardSetting extends ConsumerWidget {
  const OnScreenKeyboardSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSwitchRow(
      title: 'Built-in keyboard',
      subtitle: 'The app keyboard in text fields, made for gamepads',
      value: ref.watch(settingsProvider.select((s) => s.useOnScreenKeyboard)),
      onChanged: (v) => ref.read(settingsProvider.notifier).setUseOnScreenKeyboard(v),
    );
  }
}
