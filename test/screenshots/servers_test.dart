import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
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
import 'package:retro_toolbox/services/smb_service.dart';
import 'package:retro_toolbox/services/webdav_server_service.dart';

import 'support.dart';
import 'fakes.dart';

const _ips = ['192.168.1.42', '10.0.0.7'];

void main() {
  screenshotSetUp();
  final only = const String.fromEnvironment('ONLY');

  // name -> (screen, running-state setter)
  final screens = <String, (Widget Function(), void Function(ProviderContainer c)?)>{
    'ftp': (
      () => const FtpScreen(),
      (c) {
        final n = c.read(ftpProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(mode: FtpMode.server, serverRunning: true, serverDir: '/storage/emulated/0/ROMs', serverAddresses: _ips);
      }
    ),
    'smb': (
      () => const SmbScreen(),
      (c) {
        final n = c.read(smbProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(discovered: const [SmbHost(ip: '192.168.1.10', name: 'NAS'), SmbHost(ip: '192.168.1.23', name: 'DESKTOP-PC'), SmbHost(ip: '192.168.1.31')]);
      }
    ),
    'fbi_server': (
      () => const FbiServerScreen(),
      (c) {
        final n = c.read(fbiServerProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(running: true, addresses: _ips, threeDsIp: '192.168.1.77', activeTransfers: 1, games: [
          for (final t in ['Pokemon X (USA)', 'Mario Kart 7 (USA)', 'Zelda - A Link Between Worlds (USA)'])
            (game: Game(title: t, url: 'https://example.invalid/$t.cia', size: 512 << 20, consoleId: '3ds'), console: consoles.last),
        ]);
      }
    ),
    'fpkgi_server': (
      () => const FpkgiServerScreen(),
      (c) {
        final n = c.read(fpkgiServerProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(running: true, addresses: _ips, activeTransfers: 2);
      }
    ),
    'tinfoil_server': (
      () => const TinfoilServerScreen(),
      (c) {
        final n = c.read(tinfoilServerProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(running: true, addresses: _ips, activeTransfers: 1);
      }
    ),
    'rts_server': (
      () => const RtsServerScreen(),
      (c) {
        final n = c.read(rtsServerProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(running: true, addresses: _ips, activeTransfers: 1, folders: const [
          RtsFolder(path: '/storage/emulated/0/ROMs/snes', name: 'SNES', formats: ['.sfc', '.zip'], romsSubfolder: 'snes'),
          RtsFolder(path: '/storage/emulated/0/ROMs/psx', name: 'PlayStation', formats: ['.chd', '.cue'], romsSubfolder: 'psx'),
        ]);
      }
    ),
    'jdkv_server': (
      () => const JdkvServerScreen(),
      (c) {
        final n = c.read(jdkvServerProvider.notifier);
        // ignore: invalid_use_of_protected_member
        n.state = n.state.copyWith(running: true, addresses: _ips, folder: '/storage/emulated/0/JKSV', incoming: const [
          IncomingSave(titleId: '0100F2C0115B6000', displayName: 'The Legend of Zelda: Tears of the Kingdom', bytes: 3 << 20),
        ]);
      }
    ),
  };

  for (final MapEntry(key: name, value: (build, running)) in screens.entries) {
    if (only.isNotEmpty && !only.split(',').contains(name)) continue;
    testWidgets('server $name stopped', (t) async {
      await launch(t, build(), overrides: consolesOverrides());
      await realWait(t, 800);
      await snap(t, 'server_${name}_stopped');
    }, skip: !screenshotsEnabled);
    if (running != null) {
      testWidgets('server $name running', (t) async {
        final c = await launch(t, build(), overrides: consolesOverrides());
        await realWait(t, 800);
        running(c);
        await realWait(t, 400);
        await snap(t, 'server_${name}_running');
      }, skip: !screenshotsEnabled);
    }
  }
}
