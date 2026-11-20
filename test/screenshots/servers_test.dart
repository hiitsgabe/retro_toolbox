import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/screens/fbi_server_screen.dart';
import 'package:retro_toolbox/screens/fpkgi_server_screen.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:retro_toolbox/screens/rts_server_screen.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:retro_toolbox/screens/tinfoil_server_screen.dart';
import 'package:retro_toolbox/services/fbi_server_service.dart';
import 'package:retro_toolbox/services/smb_service.dart';
import 'package:retro_toolbox/services/webdav_server_service.dart';

import 'support.dart';
import 'fakes.dart';

/// Every server off, on with activity, and failed to start; SMB finding
/// hosts and its Enter address sheet; FTP as client and as server.
///
///   SCREENSHOTS=1 flutter test test/screenshots/servers_test.dart --dart-define=DEVICE=odin2 --dart-define=OUT=/tmp/shots
///
/// ONLY: tinfoil, fbi, fpkgi, rts, jdkv, ftp, smb. On is also shot with the
/// pad as the last input (the hints and the focus ring).

const _ips = ['192.168.1.42', '10.0.0.7'];
const _busy = 'SocketException: Failed to create server socket (OS Error: Address already in use, errno = 98), address = 0.0.0.0, port = 9092';

const _ps4 = Console(id: 'ps4', name: 'PlayStation 4', urls: [], platform: 'ps4', originalFormat: ['.pkg']);
List<Override> _withPs4() => [
      appStateProvider.overrideWith((ref) => FakeApp(AppState(consoles: {for (final c in [...consoles, _ps4]) c.id: c}, selectedConsole: consoles.first))),
    ];

/// Prepares instantly, so a tap on a title shows its QR.
class _ShotFbi extends FbiServerNotifier {
  _ShotFbi(super.ref);
  @override
  Future<String> prepareCatalog(FbiGame g, void Function(double) onProgress) async => 'http://192.168.1.42:9094/cia/${Uri.encodeComponent(g.game.title)}.cia';
}

/// Sets a notifier's state as its service would.
void _set<T>(StateNotifier<T> n, T Function(T) f) {
  // ignore: invalid_use_of_protected_member
  n.state = f(n.state);
}

typedef _Shot = ({Widget Function() screen, void Function(ProviderContainer c)? state, List<Override> Function()? overrides, Future<void> Function(WidgetTester t)? act, bool pad});

_Shot _s(Widget Function() screen, void Function(ProviderContainer c)? state, {List<Override> Function()? overrides, Future<void> Function(WidgetTester t)? act, bool pad = false}) =>
    (screen: screen, state: state, overrides: overrides, act: act, pad: pad);

final _fbiGames = [
  for (final t in ['Pokemon X (USA)', 'Mario Kart 7 (USA)', 'Zelda - A Link Between Worlds (USA)', 'Super Mario 3D Land (USA)', 'Fire Emblem Awakening (USA)'])
    (game: Game(title: t, url: 'https://example.invalid/$t.cia', size: 512 << 20, consoleId: '3ds'), console: consoles.last),
];

const _folders = [
  RtsFolder(path: '/storage/emulated/0/ROMs/snes', name: 'SNES', formats: ['.sfc', '.zip'], romsSubfolder: 'snes', boxartsUrl: 'https://thumbnails.libretro.com/snes'),
  RtsFolder(path: '/storage/emulated/0/ROMs/psx', name: 'PlayStation', formats: ['.chd', '.cue'], romsSubfolder: 'psx'),
];

void _tinfoil(ProviderContainer c, {bool on = true, String? error}) =>
    _set(c.read(tinfoilServerProvider.notifier), (s) => s.copyWith(running: on, addresses: on ? _ips : const [], activeTransfers: on ? 1 : 0, error: error));

final _shots = <String, Map<String, _Shot>>{
  'tinfoil': {
    'off': _s(() => const TinfoilServerScreen(), null),
    'on': _s(() => const TinfoilServerScreen(), (c) => _tinfoil(c)),
    'on_pad': _s(() => const TinfoilServerScreen(), (c) => _tinfoil(c), pad: true),
    'error': _s(() => const TinfoilServerScreen(), (c) => _tinfoil(c, on: false, error: _busy)),
    'setup': _s(() => const TinfoilServerScreen(), (c) => _tinfoil(c), act: (t) async {
      await t.tap(find.text('First time setup'));
      await frames(t, 3);
    }),
  },
  'fbi': {
    'off': _s(() => const FbiServerScreen(), null),
    'on': _s(() => const FbiServerScreen(), (c) => _set(c.read(fbiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, threeDsIp: '192.168.1.77', activeTransfers: 1, games: _fbiGames))),
    'on_pad': _s(() => const FbiServerScreen(), (c) => _set(c.read(fbiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, threeDsIp: '192.168.1.77', games: _fbiGames)), pad: true),
    'qr': _s(
      () => const FbiServerScreen(),
      (c) => _set(c.read(fbiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, threeDsIp: '192.168.1.77', activeTransfers: 1, games: _fbiGames)),
      overrides: () => [...consolesOverrides(), fbiServerProvider.overrideWith((ref) => _ShotFbi(ref))],
      act: (t) async {
        await t.tap(find.text('Pokemon X (USA)'));
        await realWait(t, 300);
      },
    ),
    'error': _s(() => const FbiServerScreen(), (c) => _set(c.read(fbiServerProvider.notifier), (s) => s.copyWith(error: _busy.replaceAll('9092', '9094')))),
  },
  'fpkgi': {
    'blocked': _s(() => const FpkgiServerScreen(), null),
    'off': _s(() => const FpkgiServerScreen(), null, overrides: _withPs4),
    'on': _s(() => const FpkgiServerScreen(), (c) => _set(c.read(fpkgiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, activeTransfers: 2)), overrides: _withPs4),
    'on_pad': _s(() => const FpkgiServerScreen(), (c) => _set(c.read(fpkgiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips)), overrides: _withPs4, pad: true),
    'setup': _s(() => const FpkgiServerScreen(), (c) => _set(c.read(fpkgiServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips)), overrides: _withPs4, act: (t) async {
      await t.tap(find.text('Set up the PS4 (once)'));
      await frames(t, 3);
    }),
    'error': _s(() => const FpkgiServerScreen(), (c) => _set(c.read(fpkgiServerProvider.notifier), (s) => s.copyWith(error: _busy.replaceAll('9092', '9095'))), overrides: _withPs4),
  },
  'rts': {
    'empty': _s(() => const RtsServerScreen(), null),
    'off': _s(() => const RtsServerScreen(), (c) => _set(c.read(rtsServerProvider.notifier), (s) => s.copyWith(folders: _folders))),
    'on': _s(() => const RtsServerScreen(), (c) => _set(c.read(rtsServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, activeTransfers: 1, folders: _folders, forwardLibrary: true))),
    'on_pad': _s(() => const RtsServerScreen(), (c) => _set(c.read(rtsServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, folders: _folders)), pad: true),
    'error': _s(() => const RtsServerScreen(), (c) => _set(c.read(rtsServerProvider.notifier), (s) => s.copyWith(folders: _folders, error: _busy.replaceAll('9092', '9093')))),
  },
  'jdkv': {
    'off': _s(() => const JdkvServerScreen(), null),
    'on': _s(() => const JdkvServerScreen(), (c) => _set(c.read(jdkvServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, folder: '/storage/emulated/0/JKSV', activeTransfers: 1, incoming: const [
          IncomingSave(titleId: '0100F2C0115B6000', displayName: 'The Legend of Zelda: Tears of the Kingdom', bytes: 3 << 20),
          IncomingSave(titleId: '01006A800016E000', displayName: 'Super Smash Bros. Ultimate', bytes: 1 << 20),
        ]))),
    'on_pad': _s(() => const JdkvServerScreen(), (c) => _set(c.read(jdkvServerProvider.notifier), (s) => s.copyWith(running: true, addresses: _ips, folder: '/storage/emulated/0/JKSV', incoming: const [
          IncomingSave(titleId: '0100F2C0115B6000', displayName: 'The Legend of Zelda: Tears of the Kingdom', bytes: 3 << 20),
        ])), pad: true),
    'error': _s(() => const JdkvServerScreen(), (c) => _set(c.read(jdkvServerProvider.notifier), (s) => s.copyWith(folder: '/storage/emulated/0/JKSV', error: _busy.replaceAll('9092', '9091')))),
  },
  'ftp': {
    'client': _s(() => const FtpScreen(), null),
    'client_error': _s(() => const FtpScreen(), (c) => _set(c.read(ftpProvider.notifier), (s) => s.copyWith(host: '192.168.1.50', error: 'SocketException: Connection refused (OS Error: Connection refused, errno = 111), address = 192.168.1.50, port = 21'))),
    'server_off': _s(() => const FtpScreen(), (c) => _set(c.read(ftpProvider.notifier), (s) => s.copyWith(mode: FtpMode.server, serverDir: '/storage/emulated/0/ROMs'))),
    'server_on': _s(() => const FtpScreen(), (c) => _set(c.read(ftpProvider.notifier), (s) => s.copyWith(mode: FtpMode.server, serverRunning: true, serverDir: '/storage/emulated/0/ROMs', serverReadOnly: true, serverAddresses: _ips))),
    'server_on_pad': _s(() => const FtpScreen(), (c) => _set(c.read(ftpProvider.notifier), (s) => s.copyWith(mode: FtpMode.server, serverRunning: true, serverDir: '/storage/emulated/0/ROMs', serverAddresses: _ips)), pad: true),
    'server_error': _s(() => const FtpScreen(), (c) => _set(c.read(ftpProvider.notifier), (s) => s.copyWith(mode: FtpMode.server, serverDir: '/storage/emulated/0/ROMs', serverError: _busy.replaceAll('9092', '2121')))),
  },
  'smb': {
    'start': _s(() => const SmbScreen(), null),
    'scanning': _s(() => const SmbScreen(), (c) => _set(c.read(smbProvider.notifier), (s) => s.copyWith(scanning: true, discovered: const [SmbHost(ip: '192.168.1.10', name: 'NAS')]))),
    'found': _s(() => const SmbScreen(), (c) => _set(c.read(smbProvider.notifier), (s) => s.copyWith(discovered: const [SmbHost(ip: '192.168.1.10', name: 'NAS'), SmbHost(ip: '192.168.1.23', name: 'DESKTOP-PC'), SmbHost(ip: '192.168.1.31')]))),
    'found_pad': _s(() => const SmbScreen(), (c) => _set(c.read(smbProvider.notifier), (s) => s.copyWith(discovered: const [SmbHost(ip: '192.168.1.10', name: 'NAS'), SmbHost(ip: '192.168.1.23', name: 'DESKTOP-PC')])), pad: true),
    'address': _s(() => const SmbScreen(), (c) => _set(c.read(smbProvider.notifier), (s) => s.copyWith(discovered: const [SmbHost(ip: '192.168.1.10', name: 'NAS')], username: 'gabe')), act: (t) async {
      await t.tap(find.text('Enter address').first);
      await frames(t, 6);
    }),
    'address_error': _s(() => const SmbScreen(), (c) => _set(c.read(smbProvider.notifier), (s) => s.copyWith(host: '192.168.1.10', username: 'gabe', error: 'SmbAuthException: Logon failure: unknown user name or bad password')), act: (t) async {
      await t.tap(find.text('Enter address').first);
      await frames(t, 6);
    }),
  },
};

void main() {
  screenshotSetUp();
  final only = const String.fromEnvironment('ONLY');

  for (final MapEntry(key: name, value: shots) in _shots.entries) {
    if (only.isNotEmpty && !only.split(',').contains(name)) continue;
    for (final MapEntry(key: state, value: shot) in shots.entries) {
      testWidgets('server $name $state', (t) async {
        final c = await launch(t, shot.screen(), overrides: shot.overrides?.call() ?? consolesOverrides());
        await realWait(t, 600);
        shot.state?.call(c);
        await realWait(t, 300);
        if (shot.pad) {
          c.read(inputModeProvider.notifier).state = InputMode.gamepad;
          await key(t, LogicalKeyboardKey.arrowDown);
          c.read(inputModeProvider.notifier).state = InputMode.gamepad;
          await frames(t, 3);
        }
        await shot.act?.call(t);
        await snap(t, 'server_${name}_$state');
      }, skip: !screenshotsEnabled);
    }
  }
}
