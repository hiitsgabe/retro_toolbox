import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the last input came from: button hints show only for a gamepad.
enum InputMode { gamepad, touch }

/// The last input's kind, kept by [InputModeListener]. Before any input:
/// touch, since Android cannot tell a phone from a handheld with a pad, and a
/// hint shows only once a button has been pressed. The Linux build runs on a
/// handheld with no touchscreen, where buttons are all there is: gamepad.
final inputModeProvider = StateProvider<InputMode>((ref) => _initial());

InputMode _initial() => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux ? InputMode.gamepad : InputMode.touch;

/// Sets [inputModeProvider] from every key event (gamepad) and every pointer
/// down (touch) under it; the app puts one round all its routes.
class InputModeListener extends ConsumerStatefulWidget {
  const InputModeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InputModeListener> createState() => _InputModeListenerState();
}

class _InputModeListenerState extends ConsumerState<InputModeListener> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Only listens: the key still goes on to focus and shortcuts.
  bool _onKey(KeyEvent _) {
    _set(InputMode.gamepad);
    return false;
  }

  void _set(InputMode mode) {
    final n = ref.read(inputModeProvider.notifier);
    if (n.state != mode) n.state = mode;
  }

  @override
  Widget build(BuildContext context) => Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _set(InputMode.touch), child: widget.child);
}
