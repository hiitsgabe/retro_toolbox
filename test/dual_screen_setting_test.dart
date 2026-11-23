import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/widgets/settings/dual_screen_setting.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

class FakeDualScreen extends StateNotifier<DualScreenState> implements DualScreenNotifier {
  FakeDualScreen(super.state);
  final modes = <DualScreenMode>[];

  @override
  Future<void> setMode(DualScreenMode mode) async => modes.add(mode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeDualScreen> pumpCard(WidgetTester tester, DualScreenState state, {bool home = false}) async {
  final fake = FakeDualScreen(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [dualScreenProvider.overrideWith((ref) => fake), homeModeProvider.overrideWithValue(home)],
    child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DualScreenSetting()))),
  ));
  return fake;
}

void main() {
  testWidgets('shows the three choices with the current one selected', (tester) async {
    await pumpCard(tester, const DualScreenState(mode: DualScreenMode.mainOnTop, hasSecondDisplay: true));
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Main on top'), findsOneWidget);
    expect(find.text('Main on bottom'), findsOneWidget);
    expect(find.text('Only shown when a second display is found'), findsOneWidget);
    expect(find.textContaining('Changing which screen is the main one restarts the app there.'), findsOneWidget);
    expect(tester.widget<SettingsSegmentedRow<DualScreenMode>>(find.byType(SettingsSegmentedRow<DualScreenMode>)).selected, DualScreenMode.mainOnTop);
  });

  testWidgets('tapping Main on bottom sets that mode', (tester) async {
    final fake = await pumpCard(tester, const DualScreenState(hasSecondDisplay: true));
    await tester.tap(find.text('Main on bottom'));
    await tester.pump();
    expect(fake.modes, [DualScreenMode.mainOnBottom]);
  });

  testWidgets('with Retro Toolbox the home screen, Main on bottom cannot be picked, and the card says why', (tester) async {
    final fake = await pumpCard(tester, const DualScreenState(mode: DualScreenMode.mainOnTop, hasSecondDisplay: true), home: true);
    expect(find.text(mainOnBottomLockedReason), findsOneWidget);
    await tester.tap(find.text('Main on bottom'));
    await tester.pump();
    expect(fake.modes, isEmpty);
    Focus.of(tester.element(find.text('Layout'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fake.modes, isEmpty, reason: 'right from Main on top would land on it');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(fake.modes, [DualScreenMode.off]);
  });

  testWidgets('not the home screen: no reason line', (tester) async {
    await pumpCard(tester, const DualScreenState(hasSecondDisplay: true));
    expect(find.text(mainOnBottomLockedReason), findsNothing);
  });

  testWidgets('shows no error by default', (tester) async {
    await pumpCard(tester, const DualScreenState(hasSecondDisplay: true));
    expect(find.text(unavailableMessage), findsNothing);
  });

  testWidgets('shows an error in the error color', (tester) async {
    await pumpCard(tester, const DualScreenState(hasSecondDisplay: true, error: unavailableMessage));
    final text = tester.widget<Text>(find.text(unavailableMessage));
    // The style's own error colour, not Material's.
    expect(text.style?.color, StyleTokens.of(tester.element(find.text(unavailableMessage))).error);
  });

  test('the card needs Android and a second display', () {
    expect(showDualScreenCard(isAndroid: true, hasSecondDisplay: true), isTrue);
    expect(showDualScreenCard(isAndroid: true, hasSecondDisplay: false), isFalse);
    expect(showDualScreenCard(isAndroid: false, hasSecondDisplay: true), isFalse);
  });
}
