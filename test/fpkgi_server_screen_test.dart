import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/fpkgi_server_screen.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFpkgi extends StateNotifier<FpkgiServerState> implements FpkgiServerNotifier {
  _FakeFpkgi(super.state);
  var enables = 0;
  @override
  Future<void> enable() async => enables++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], gameFilesFormat: ['.sfc']);
const _ps4 = Console(id: 'ps4', name: 'PlayStation 4', urls: [], platform: 'ps4', originalFormat: ['.pkg']);

Future<_FakeFpkgi> _pump(WidgetTester t, Map<String, Console> consoles, {FpkgiServerState state = const FpkgiServerState()}) async {
  final fpkgi = _FakeFpkgi(state);
  await t.pumpWidget(ProviderScope(
    overrides: [
      appStateProvider.overrideWith((ref) => _FakeApp(AppState(consoles: consoles))),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      fpkgiServerProvider.overrideWith((ref) => fpkgi),
    ],
    child: const MaterialApp(home: FpkgiServerScreen()),
  ));
  await t.pump();
  return fpkgi;
}

SwitchListTile _switch(WidgetTester t) => t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Enable server'));

void main() {
  testWidgets('the switch is disabled without a PS4 system, with the notice as the reason', (t) async {
    final fpkgi = await _pump(t, const {'snes': _snes});
    expect(find.text('No PS4 system in the catalog'), findsOneWidget);
    expect(_switch(t).onChanged, isNull);
    await t.tap(find.text('Enable server'));
    await t.pump();
    expect(fpkgi.enables, 0);
  });

  testWidgets('the switch works with a PS4 system in the catalog', (t) async {
    final fpkgi = await _pump(t, const {'ps4': _ps4});
    expect(find.text('No PS4 system in the catalog'), findsNothing);
    await t.tap(find.text('Enable server'));
    await t.pump();
    expect(fpkgi.enables, 1);
  });

  testWidgets('a running server can still be switched off after the PS4 system is gone', (t) async {
    await _pump(t, const {'snes': _snes}, state: const FpkgiServerState(running: true, addresses: ['10.0.0.2']));
    expect(_switch(t).onChanged, isNotNull);
  });
  testWidgets('the PS4 steps are all in English', (t) async {
    await _pump(t, const {'ps4': _ps4}, state: const FpkgiServerState(running: true, addresses: ['10.0.0.2']));
    expect(find.textContaining('On the PS4'), findsOneWidget, reason: 'the steps are shown');
    expect(find.textContaining('(L2/R2 switch category)'), findsOneWidget);
    expect(find.textContaining('troca'), findsNothing);
    expect(find.textContaining('—'), findsNothing, reason: 'no em dash in the steps');
  });
}
