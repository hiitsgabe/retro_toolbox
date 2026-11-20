import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/rts_server_screen.dart';

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeRts extends StateNotifier<RtsServerState> implements RtsServerNotifier {
  _FakeRts(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('the copy points to the catalog source setting, not New Catalog Source', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        rtsServerProvider.overrideWith((ref) => _FakeRts(const RtsServerState(running: true, addresses: ['10.0.0.2'], forwardLibrary: true))),
      ],
      child: const MaterialApp(home: RtsServerScreen()),
    ));
    await t.pump();

    // The hero may put the path on its own line when the link does not fit.
    expect(find.textContaining('http://10.0.0.2:9093'), findsOneWidget, reason: 'the link is shown');
    expect(find.textContaining('/consoles.json'), findsOneWidget);
    expect(find.textContaining('Settings > Library > Catalog source'), findsOneWidget, reason: 'the steps');
    expect(find.textContaining('New Catalog Source'), findsNothing);

    // The explanation behind the (i) says the same.
    await t.tap(find.byTooltip('About this screen'));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('Settings > Library > Catalog source')), findsOneWidget);
    expect(find.textContaining('New Catalog Source'), findsNothing);
  });
}
