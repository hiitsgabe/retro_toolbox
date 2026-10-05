import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/update_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, ready, error }

class UpdateState {
  const UpdateState(this.phase, {this.release, this.asset, this.progress = 0, this.message});
  final UpdatePhase phase;
  final ReleaseInfo? release;

  /// The file to download; null on desktop (the release page is opened instead).
  final ReleaseAsset? asset;
  final double progress;
  final String? message;

  bool get busy => phase == UpdatePhase.checking || phase == UpdatePhase.downloading;
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>(
  (ref) => UpdateNotifier(ref.watch(updateServiceProvider)),
);

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier(this._service, {bool? handheld, String? os, Abi? abi})
      : handheld = handheld ?? Handheld.current,
        _os = os ?? Platform.operatingSystem,
        _assetName = updateAssetName(
          handheld: handheld ?? Handheld.current,
          os: os ?? Platform.operatingSystem,
          abi: abi ?? Abi.current(),
        ),
        super(const UpdateState(UpdatePhase.idle));

  final UpdateService _service;
  final bool handheld;
  final String _os;
  final String? _assetName;
  File? _apk;

  /// About opened: check unless an update is already under way.
  Future<void> checkOnOpen(String currentVersion) async {
    if (state.busy || state.phase == UpdatePhase.available || state.phase == UpdatePhase.ready) return;
    await check(currentVersion);
  }

  Future<void> check(String currentVersion) async {
    if (state.busy) return;
    state = const UpdateState(UpdatePhase.checking);
    try {
      final release = await _service.fetchLatest();
      if (!isValidVersion(release.version)) {
        throw UpdateException("Can't read the latest version (\"${release.version}\").");
      }
      if (!isNewerVersion(release.version, currentVersion)) {
        state = UpdateState(UpdatePhase.upToDate, release: release);
        return;
      }
      // Play installs update through Play (its signing key differs from the
      // GitHub APK's anyway): link out like desktop.
      final name = await _fromPlay() ? null : _assetName;
      final asset = name == null ? null : release.asset(name);
      if (name != null && asset == null) {
        state = UpdateState(UpdatePhase.error,
            release: release, message: 'Version ${release.version} has no download for this device yet.');
        return;
      }
      if (asset != null && asset.sha256 == null) {
        state = UpdateState(UpdatePhase.error, release: release, message: cantVerifyMessage);
        return;
      }
      state = UpdateState(UpdatePhase.available, release: release, asset: asset);
    } catch (e) {
      state = UpdateState(UpdatePhase.error, message: _describe(e));
    }
  }

  Future<void> download() async {
    final release = state.release, asset = state.asset;
    if (state.phase != UpdatePhase.available || release == null || asset == null) return;
    state = UpdateState(UpdatePhase.downloading, release: release, asset: asset);
    try {
      await _service.ensureSpace(asset, handheld: handheld);
      final file = await _service.download(asset, (progress) {
        if (mounted) state = UpdateState(UpdatePhase.downloading, release: release, asset: asset, progress: progress);
      });
      if (handheld) {
        await _service.stageHandheld(file);
        state = UpdateState(UpdatePhase.ready, release: release, asset: asset);
        return;
      }
      _apk = file;
      state = UpdateState(UpdatePhase.ready, release: release, asset: asset);
      await install();
    } catch (e) {
      state = UpdateState(UpdatePhase.error, release: release, message: _describe(e));
    }
  }

  /// Android: (re)opens the system installer for the downloaded APK.
  Future<void> install() async {
    final apk = _apk, release = state.release;
    if (apk == null || state.phase != UpdatePhase.ready) return;
    try {
      final launched = await _service.installApk(apk);
      state = UpdateState(UpdatePhase.ready,
          release: release,
          asset: state.asset,
          message: launched ? null : 'Allow Retro Toolbox to install apps, then press Install again.');
    } catch (e) {
      state = UpdateState(UpdatePhase.ready, release: release, asset: state.asset, message: _describe(e));
    }
  }

  Future<bool> _fromPlay() async {
    if (handheld || _os != 'android') return false;
    try {
      return await _service.installerPackage() == playStoreInstaller;
    } catch (_) {
      return false;
    }
  }

  static String _describe(Object e) => e is UpdateException ? e.message : 'Update failed: $e';
}
