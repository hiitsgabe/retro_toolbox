import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/widgets/launcher/launch_flow.dart';

class FakeLauncher implements GameLauncher {
  final launched = <OwnedGame>[];
  Completer<LaunchResult>? pending;

  @override
  Future<LaunchResult> launch(OwnedGame game, LaunchChoice choice) {
    launched.add(game);
    return pending?.future ?? Future.value(LaunchResult.ok);
  }

  @override
  RomMode? modeFor(OwnedGame game, LaunchChoice choice) => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The Super Nintendo's library dir is [dir].
class DirSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  DirSettings(this.dir) : super(const AppSettings());

  final String dir;

  @override
  String getDownloadDir(String? consoleId) => consoleId == 'nintendo-snes' ? dir : '';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(title: 'Mario World', url: 'https://example.com/snes/Mario%20World.sfc', size: 1, consoleId: 'nintendo-snes');
const _ra = LaunchChoice(presetId: 'ra', variant: 'org.example.ra');

void main() {
  late Directory tmp;
  late FakeLauncher launcher;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-launch-flow-');
    launcher = FakeLauncher();
  });
  tearDown(() => tmp.delete(recursive: true));

  /// A card's context under the app's providers, the real ownedGameProvider
  /// among them; [show] false takes the card away.
  Future<BuildContext> pump(WidgetTester t, {ValueNotifier<bool>? show, List<Override> extra = const []}) async {
    late BuildContext card;
    final shown = show ?? ValueNotifier(true);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => DirSettings(tmp.path)),
        launcherSessionProvider.overrideWith((ref) async => const LauncherSession(presets: [], detected: [
              DetectedEmulator(presetId: 'ra', variant: 'org.example.ra', label: 'RetroArch', systems: ['snes']),
            ])),
        gameLauncherProvider.overrideWith((ref) async => launcher),
        ...extra,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (_, on, __) => on
                ? Builder(builder: (c) {
                    card = c;
                    return const Text('card');
                  })
                : const SizedBox(),
          ),
        ),
      ),
    ));
    return card;
  }

  testWidgets('a launch from a card reads the game\'s files on disk', (t) async {
    File(p.join(tmp.path, 'Mario World.sfc')).writeAsStringSync('x');
    final card = await pump(t);
    await t.runAsync(() => LaunchFlow(card, _game).launch(_ra));
    expect([for (final g in launcher.launched) g.paths], [
      [p.join(tmp.path, 'Mario World.sfc')],
    ]);
  });

  testWidgets('a game with no files on disk says it cannot read the file, and launches nothing', (t) async {
    final card = await pump(t);
    await t.runAsync(() => LaunchFlow(card, _game).launch(_ra));
    await t.pump();
    expect(launcher.launched, isEmpty);
    expect(find.text('Cannot read the file'), findsOneWidget);
  });

  testWidgets('the failure still shows when the card that started the launch is gone', (t) async {
    final show = ValueNotifier(true);
    final card = await pump(t, show: show, extra: [
      ownedGameProvider.overrideWith((ref, game) async => OwnedGame(game: game, dir: tmp.path, paths: [p.join(tmp.path, 'Mario World.sfc')])),
    ]);
    launcher.pending = Completer();
    final starting = <String?>[];
    final launch = LaunchFlow(card, _game, onStarting: starting.add).launch(_ra);
    await t.pump();
    expect(launcher.launched, hasLength(1));
    show.value = false;
    await t.pump();
    launcher.pending!.complete(const LaunchResult(LaunchCode.componentGone));
    await launch;
    await t.pump();
    expect(find.text('RetroArch changed in this version'), findsOneWidget);
    expect(starting, ['RetroArch'], reason: 'nothing is told to a card that is gone');
  });
}
