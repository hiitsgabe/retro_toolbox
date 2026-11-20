import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// The reference devices: logical size and pixel ratio.
const odin2 = (Size(731, 411), 2.625);
const phone = (Size(412, 915), 2.625);
const linux640 = (Size(640, 480), 1.0);

/// Pumps [home] as the app shows a screen: the style's theme, the text floor
/// and DpadScope, at [device]'s size, with [mode] as the last input, and
/// [overrides] for the screen's providers. Returns the provider container so
/// a test can switch the input mode.
Future<ProviderContainer> pumpKit(
  WidgetTester t,
  Widget home, {
  CardStyle style = CardStyle.classic,
  (Size, double) device = odin2,
  InputMode mode = InputMode.touch,
  List<Override> overrides = const [],
}) async {
  t.view.devicePixelRatio = device.$2;
  t.view.physicalSize = device.$1 * device.$2;
  addTearDown(t.view.reset);
  final c = ProviderContainer(overrides: [inputModeProvider.overrideWith((ref) => mode), ...overrides]);
  addTearDown(c.dispose);
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [DpadScope.routeObserver],
      theme: appTheme(style),
      // A second pump in another style shows that style at once.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => TextFloor(child: DpadScope(navigatorKey: nav, child: child!)),
      home: home,
    ),
  ));
  await t.pump();
  return c;
}

/// A screen pushed over a plain first page, so it has somewhere to go back.
Widget pushed(Widget screen) => _Pusher(screen: screen);

class _Pusher extends StatefulWidget {
  const _Pusher({required this.screen});

  final Widget screen;

  @override
  State<_Pusher> createState() => _PusherState();
}

class _PusherState extends State<_Pusher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => widget.screen)));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('first page'));
}
