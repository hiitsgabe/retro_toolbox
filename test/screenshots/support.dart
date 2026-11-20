// Screenshot harness: renders screens at a device's size to PNGs, for looking
// at the UI, not for golden comparisons. Every test under test/screenshots is
// skipped unless SCREENSHOTS=1, so a plain `flutter test` only counts skips.
//
//   SCREENSHOTS=1 flutter test test/screenshots/menu_test.dart --dart-define=DEVICE=odin2
//   SCREENSHOTS=1 flutter test test/screenshots/styles_test.dart --dart-define=DEVICE=phone --dart-define=CARDS=vita --dart-define=BACKDROP=aurora
//   SCREENSHOTS=1 flutter test test/screenshots/tools_test.dart --dart-define=DEVICE=linux640 --dart-define=ONLY=m3u,chd_convert --dart-define=OUT=/tmp/shots
//
// DEVICE: phone (412x915), odin2 (731x411) or linux640 (640x480, the Linux
// handheld framebuffer build); empty renders 1280x720.
// OUT: where the PNGs and overflows.txt go (default build/screenshots).
// CARDS: one card style for styles_test, and the theme every other test
// renders in (default classic). BACKDROP: the backdrop for styles_test
// (default drift; `style` picks none, so each card style shows its own).
// ONLY: comma separated screen names for tools_test and servers_test.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

final bool screenshotsEnabled = Platform.environment['SCREENSHOTS'] == '1';

const shotDevice = String.fromEnvironment('DEVICE');
const outDir = String.fromEnvironment('OUT', defaultValue: 'build/screenshots');
const _cards = String.fromEnvironment('CARDS');

/// The style a test renders in when it does not pick one.
final shotStyle = AppStyle(cards: _cards.isEmpty ? CardStyle.classic : CardStyle.values.byName(_cards));

/// (logical size, devicePixelRatio, Linux handheld framebuffer build)
const _devices = <String, (Size, double, bool)>{
  'phone': (Size(412, 915), 2.625, false),
  'odin2': (Size(731, 411), 2.625, false),
  'linux640': (Size(640, 480), 1.0, true),
};
final _dev = shotDevice.isEmpty ? (const Size(1280, 720), 1.5, false) : _devices[shotDevice]!;
Size get _logical => _dev.$1;
double get _dpr => shotDevice.isEmpty ? 1.0 : _dev.$2;
double get _capture => _dev.$2;
bool get _linuxHandheld => _dev.$3;

/// Runs [body] with the desktop picker path even on the Linux handheld (which
/// otherwise opens the in-app browser): the fake picker fills the fields.
Future<T> withNativePicker<T>(Future<T> Function() body) async {
  final was = Handheld.current;
  Handheld.current = false;
  try {
    return await body();
  } finally {
    Handheld.current = was;
  }
}

FlutterExceptionHandler? _savedOnError;
final _overflows = <String>[];

void _restoreDevice() {
  if (_savedOnError != null) {
    FlutterError.onError = _savedOnError;
    _savedOnError = null;
  }
  Handheld.current = false;
  Handheld.framebuffer = false;
  debugDefaultTargetPlatformOverride = null;
  debugDisableShadows = true;
}

/// Answers path_provider and holds the ROM fixtures; one per run, removed at
/// the end of each file.
Directory? _tmp;
Directory get _tmpDir => _tmp ??= Directory.systemTemp.createTempSync('rt_screenshots_');
late Directory supportDir;
const _channels = [
  'plugins.flutter.io/path_provider',
];

void screenshotSetUp() {
  setUp(() {
    supportDir = Directory('${_tmpDir.path}/support')..createSync(recursive: true);
    for (final c in _channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(c), (_) async => supportDir.path);
    }
  });
  tearDownAll(() {
    _tmp?.deleteSync(recursive: true);
    _tmp = null;
  });
}

/// Saved settings: library on, extra servers on.
Map<String, Object> basePrefs({AppStyle style = const AppStyle(), Map<String, Object> extra = const {}}) => {
      'app_settings': jsonEncode({
        'generalSettings': {'downloadDir': '/storage/emulated/0/ROMs', 'autoExtract': true},
        'libraryEnabled': true,
        'tinfoilEnabled': true,
        'fbiEnabled': true,
        'fpkgiEnabled': true,
      }),
      'app_style': jsonEncode(style.toJson()),
      'setup_wizard_seen': true,
      'link_download_dir': '/storage/emulated/0/Download',
      ...extra,
    };

bool _fontsLoaded = false;
Future<void> loadFonts(WidgetTester t) async {
  if (_fontsLoaded) return;
  await t.runAsync(() async {
    Future<ByteData> bytes(String path) => File(path).readAsBytes().then((b) => b.buffer.asByteData());
    final chakra = FontLoader('ChakraPetch');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      chakra.addFont(bytes('assets/fonts/ChakraPetch-$w.ttf'));
    }
    await chakra.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter';
    final mf = '$root/bin/cache/artifacts/material_fonts';
    await (FontLoader('MaterialIcons')..addFont(bytes('$mf/MaterialIcons-Regular.otf'))).load();
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(bytes('$mf/Roboto-$w.ttf'));
    }
    await roboto.load();
    const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf';
    if (File(mono).existsSync()) {
      await (FontLoader('monospace')..addFont(bytes(mono))).load();
      await (FontLoader('DejaVuSansMono')..addFont(bytes(mono))).load();
    }
  });
  _fontsLoaded = true;
}

/// The app theme, with a fallback for glyphs ChakraPetch lacks (a device
/// falls back to its system font).
ThemeData shotTheme(CardStyle cards, {BackdropStyle? backdrop}) {
  final t = appTheme(cards, backdrop: backdrop);
  const fb = ['Roboto', 'DejaVuSansMono'];
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: fb),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: fb),
  );
}

var _boundary = GlobalKey();

/// Pumps [home] as the app does (theme, DpadScope) at the device's size.
Future<ProviderContainer> launch(
  WidgetTester t,
  Widget home, {
  List<Override> overrides = const [],
  Map<String, Object>? prefs,
  AppStyle? style,
}) async {
  await loadFonts(t);
  SharedPreferences.setMockInitialValues(prefs ?? basePrefs(style: style ?? shotStyle));
  t.view.devicePixelRatio = _dpr;
  t.view.physicalSize = _logical * _dpr;
  addTearDown(t.view.reset);
  // The Linux handheld build: Handheld.current and the framebuffer fallback
  // (still backdrops, no page transitions), on a Linux target platform.
  Handheld.current = _linuxHandheld;
  Handheld.framebuffer = _linuxHandheld;
  if (_linuxHandheld) debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  // Tests paint elevation as a solid black ring; a device paints a shadow.
  debugDisableShadows = false;
  addTearDown(_restoreDevice);
  // Overflows are findings at device sizes: log them, keep the stripes.
  _overflows.clear();
  _savedOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('overflowed')) {
      final lines = text.split('\n');
      final what = lines.firstWhere((l) => l.contains('overflowed'), orElse: () => '').trim();
      final i = lines.indexWhere((l) => l.contains('relevant error-causing widget'));
      final where = i >= 0 ? lines.skip(i + 1).take(2).map((l) => l.trim()).join(' ') : '';
      _overflows.add('$what | $where');
      return;
    }
    _savedOnError?.call(details);
  };
  _boundary = GlobalKey();
  final c = ProviderContainer(overrides: overrides);
  addTearDown(c.dispose);
  await t.runAsync(() async {
    try {
      await c.read(settingsProvider.notifier).loaded;
    } catch (_) {}
    await c.read(styleProvider.notifier).loaded;
  });
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    // Follows the style as the app does, so Settings > Style restyles it.
    child: Consumer(
      builder: (context, ref, _) {
        final style = ref.watch(styleProvider);
        return MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [DpadScope.routeObserver],
        debugShowCheckedModeBanner: false,
        theme: shotTheme(style.cards, backdrop: style.backdrop),
        // The input mode listener as the app has it: hints follow the last input.
        builder: (context, child) => RepaintBoundary(
          key: _boundary,
          child: TextFloor(child: InputModeListener(child: DpadScope(navigatorKey: nav, onScreenKeyboard: Handheld.current, child: child!))),
        ),
        home: home,
      );
      },
    ),
  ));
  await frames(t);
  return c;
}

/// Advances time in steps (animated backdrops never settle).
Future<void> frames(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await frames(t, 4);
}

/// Lets image and SVG decoding (real async) finish.
Future<void> settleImages(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Writes the screen to `OUT/<name>.png`. With [keep] the tree stays mounted
/// so the test can go on (open a sheet, move focus) and snap again; the last
/// snap of a test leaves [keep] off.
Future<void> snap(WidgetTester t, String name, {bool keep = false}) async {
  await frames(t, 3);
  await settleImages(t);
  final render = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await t.runAsync(() => render.toImage(pixelRatio: _capture));
  final bytes = await t.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  final log = File('$outDir/overflows.txt');
  final seen = _overflows.toSet();
  if (seen.isNotEmpty) log.writeAsStringSync('${seen.map((o) => '$name: $o').join('\n')}\n', mode: FileMode.append);
  _overflows.clear();
  if (keep) return;
  // Unmount here: a screen whose dispose throws must not fail the shot or
  // poison the next test.
  await t.pumpWidget(const SizedBox());
  t.takeException();
  // Library timers (image cache cleanup) outlive the tree.
  await t.pump(const Duration(seconds: 15));
  t.takeException();
  _restoreDevice();
}

/// Pushes [screen] on the app navigator.
Future<void> push(WidgetTester t, Widget screen) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(builder: (_) => screen));
  await frames(t, 6);
}

/// Lets real async work (processes, file IO) started by a screen finish.
Future<void> realWait(WidgetTester t, [int ms = 1500]) async {
  for (var waited = 0; waited < ms; waited += 100) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// A small fake ROM folder for the tools' filled states.
String romFixtures() {
  final root = Directory('${_tmpDir.path}/fs/ROMs');
  if (root.existsSync()) return root.path;
  void touch(String rel, [int size = 0]) => File('${root.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(size, 0));
  for (final d in [1, 2, 3]) {
    touch('psx/Final Fantasy VII (USA) (Disc $d).cue');
    touch('psx/Final Fantasy VII (USA) (Disc $d).bin', 4096);
  }
  for (final d in [1, 2]) {
    touch('psx/Metal Gear Solid (USA) (Disc $d) (Rev 1).cue');
    touch('psx/Metal Gear Solid (USA) (Disc $d) (Rev 1).bin', 4096);
  }
  touch('psx/Crash Bandicoot (USA).cue');
  touch('psx/Crash Bandicoot (USA).bin', 4096);
  touch('snes/Super Mario World (USA).sfc', 2048);
  touch('snes/Super Mario World (USA) (Rev 1).sfc', 2048);
  touch('snes/Super Mario World (Europe).sfc', 2048);
  touch('snes/Chrono Trigger (USA) [!].sfc', 4096);
  touch('snes/EarthBound (USA) (Virtual Console).sfc', 4096);
  touch('snes/.DS_Store', 10);
  touch('snes/Thumbs.db', 10);
  touch('3ds/Pokemon X (USA).3ds', 8192);
  touch('switch/Celeste [0100A410000E0000][v0].nsz', 8192);
  touch('switch/Hollow Knight [0100633007D48000][v0].nsp', 8192);
  touch('gba/Metroid Fusion (USA).gba', 1024);
  touch('gba/Golden Sun (USA).gba', 1024);
  return root.path;
}
