import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/server_busy_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';

class _DL extends StateNotifier<DownloadState> implements DownloadNotifier {
  _DL(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _TQ extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _TQ() : super(const TaskQueueState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EX extends StateNotifier<ExtractionState> implements ExtractionNotifier {
  _EX() : super(const ExtractionState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FBI extends StateNotifier<FbiServerState> implements FbiServerNotifier {
  _FBI() : super(const FbiServerState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _TIN extends StateNotifier<TinfoilServerState> implements TinfoilServerNotifier {
  _TIN() : super(const TinfoilServerState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FPK extends StateNotifier<FpkgiServerState> implements FpkgiServerNotifier {
  _FPK() : super(const FpkgiServerState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RTS extends StateNotifier<RtsServerState> implements RtsServerNotifier {
  _RTS(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _JD extends StateNotifier<JdkvServerState> implements JdkvServerNotifier {
  _JD() : super(const JdkvServerState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FTP extends StateNotifier<FtpState> implements FtpNotifier {
  _FTP() : super(const FtpState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SMB extends StateNotifier<SmbState> implements SmbNotifier {
  _SMB(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SS extends StateNotifier<SaveSyncState> implements SaveSyncNotifier {
  _SS(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container({bool downloading = false, int rts = 0, bool smb = false, bool sync = false}) =>
    ProviderContainer(overrides: [
      downloadProvider.overrideWith((_) => _DL(DownloadState(downloading: downloading))),
      taskQueueProvider.overrideWith((_) => _TQ()),
      extractionProvider.overrideWith((_) => _EX()),
      fbiServerProvider.overrideWith((_) => _FBI()),
      tinfoilServerProvider.overrideWith((_) => _TIN()),
      fpkgiServerProvider.overrideWith((_) => _FPK()),
      rtsServerProvider.overrideWith((_) => _RTS(RtsServerState(activeTransfers: rts))),
      jdkvServerProvider.overrideWith((_) => _JD()),
      ftpProvider.overrideWith((_) => _FTP()),
      smbProvider.overrideWith((_) => _SMB(SmbState(
          transfer: smb ? const SmbTransfer(name: 'a', done: 0, total: 0, upload: true) : null))),
      saveSyncProvider.overrideWith((_) => _SS(SaveSyncState(busyRecipe: sync ? 'r' : null))),
    ]);

void main() {
  test('writeBusyFlag creates and removes the file', () async {
    final f = File('${(await Directory.systemTemp.createTemp()).path}/busy');
    await writeBusyFlag(true, path: f.path);
    expect(f.existsSync(), isTrue);
    await writeBusyFlag(false, path: f.path);
    expect(f.existsSync(), isFalse);
    await writeBusyFlag(false, path: f.path);
  });

  test('rapid unawaited writes end in the last value', () async {
    final f = File('${(await Directory.systemTemp.createTemp()).path}/busy');
    for (var i = 0; i < 20; i++) {
      writeBusyFlag(true, path: f.path);
      writeBusyFlag(false, path: f.path);
    }
    writeBusyFlag(true, path: f.path);
    await writeBusyFlag(true, path: f.path);
    expect(f.existsSync(), isTrue);
    writeBusyFlag(true, path: f.path);
    await writeBusyFlag(false, path: f.path);
    expect(f.existsSync(), isFalse);
  });

  test('a failed write does not block later writes', () async {
    final dir = (await Directory.systemTemp.createTemp()).path;
    File('$dir/file').writeAsStringSync('');
    await writeBusyFlag(true, path: '$dir/file/busy'); // parent is a file: create throws
    final f = File('$dir/busy');
    await writeBusyFlag(true, path: f.path);
    expect(f.existsSync(), isTrue);
  });

  test('writeBusyFlag without a path does nothing', () async {
    await writeBusyFlag(true, path: '');
  });

  test('busy when a download runs, idle otherwise', () {
    final idle = _container();
    addTearDown(idle.dispose);
    expect(idle.read(serverBusyProvider), isFalse);
    final dl = _container(downloading: true);
    addTearDown(dl.dispose);
    expect(dl.read(serverBusyProvider), isTrue);
    final rts = _container(rts: 1);
    addTearDown(rts.dispose);
    expect(rts.read(serverBusyProvider), isTrue);
  });

  test('busy while an SMB transfer runs', () {
    final c = _container(smb: true);
    addTearDown(c.dispose);
    expect(c.read(serverBusyProvider), isTrue);
  });

  test('busy while a save-sync run is in progress', () {
    final c = _container(sync: true);
    addTearDown(c.dispose);
    expect(c.read(serverBusyProvider), isTrue);
  });

  test('busy while a roster patch runs', () {
    final c = _container();
    addTearDown(c.dispose);
    final seen = <bool>[];
    c.listen(serverBusyProvider, (_, b) => seen.add(b), fireImmediately: true);
    SportsService.patchesInFlight.value++;
    expect(c.read(serverBusyProvider), isTrue);
    SportsService.patchesInFlight.value--;
    expect(c.read(serverBusyProvider), isFalse);
    expect(seen, [false, true, false]);
  });
}
