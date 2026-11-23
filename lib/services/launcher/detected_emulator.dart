import 'dart:typed_data';

import 'package:retro_toolbox/services/launcher/launch_choice.dart';

/// What the native `detect` reports about one installed Android package. The
/// native side only reports; [pathAccess] decides in Dart.
class AndroidPackageFacts {
  const AndroidPackageFacts({
    required this.targetSdk,
    required this.sdkInt,
    this.legacyStorage = false,
    this.requestsManage = false,
    this.requestsRead = false,
  });

  final int targetSdk;

  /// The device's API level.
  final int sdkInt;

  /// `hasRequestedLegacyExternalStorage()`, API 29+.
  final bool legacyStorage;
  final bool requestsManage;
  final bool requestsRead;
}

/// Whether the package can open a raw path on shared storage. A requested
/// READ_EXTERNAL_STORAGE only reaches media through a path on Android 11+
/// unless the package has legacy storage, and MANAGE_EXTERNAL_STORAGE is an
/// app op another app cannot read, so a request is taken as the grant.
bool pathAccess(AndroidPackageFacts f) =>
    f.requestsManage ||
    (f.sdkInt < 29 && f.requestsRead) ||
    (f.requestsRead && (f.targetSdk <= 28 || (f.targetSdk == 29 && f.legacyStorage)));

/// Whether [pathAccess] holds only through MANAGE_EXTERNAL_STORAGE on Android
/// 11+, where it is an app op the user turns on in system Settings, not a
/// grant at install. The wizard then offers to open that setting.
bool restsOnManage(AndroidPackageFacts f) =>
    f.requestsManage &&
    f.sdkInt >= 30 &&
    !pathAccess(AndroidPackageFacts(targetSdk: f.targetSdk, sdkInt: f.sdkInt, legacyStorage: f.legacyStorage, requestsRead: f.requestsRead));

/// One preset found installed.
class DetectedEmulator {
  const DetectedEmulator({
    required this.presetId,
    required this.variant,
    required this.label,
    required this.systems,
    this.icon,
    this.version,
    this.dataDir,
    this.requestsManage = false,
    this.pathAccess = true,
    this.manageGrant = false,
    this.exe,
    this.prefixArgs = const [],
  });

  final String presetId;

  /// The Android package, or on desktop the executable (the flatpak id for a
  /// flatpak).
  final String variant;
  final String label;

  /// The console art slugs the preset covers.
  final List<String> systems;
  final Uint8List? icon;
  final String? version;

  /// Android: `ApplicationInfo.dataDir`, for the RetroArch core path.
  final String? dataDir;

  /// Android: whether the package asks for all files access (slice 2 offers
  /// to open that setting).
  final bool requestsManage;

  /// Android: whether a `path` launch can work; otherwise `scopedMode`.
  final bool pathAccess;

  /// Android: [pathAccess] rests on all files access (see [restsOnManage]).
  final bool manageGrant;

  /// Desktop: what to run, and the arguments before the preset's own
  /// (`run <id>` for a flatpak).
  final String? exe;
  final List<String> prefixArgs;

  LaunchChoice get choice => LaunchChoice(presetId: presetId, variant: variant);

  /// This detection opening [systems] instead: a saved one takes them from
  /// the preset file in use, which may have grown since.
  DetectedEmulator withSystems(List<String> systems) => DetectedEmulator(
        presetId: presetId,
        variant: variant,
        label: label,
        systems: systems,
        icon: icon,
        version: version,
        dataDir: dataDir,
        requestsManage: requestsManage,
        pathAccess: pathAccess,
        manageGrant: manageGrant,
        exe: exe,
        prefixArgs: prefixArgs,
      );

  /// Everything but [icon], which only a fresh detection brings back: the
  /// saved list stays small.
  Map<String, Object?> toJson() => {
        'presetId': presetId,
        'variant': variant,
        'label': label,
        'systems': systems,
        if (version != null) 'version': version,
        if (dataDir != null) 'dataDir': dataDir,
        'requestsManage': requestsManage,
        'pathAccess': pathAccess,
        'manageGrant': manageGrant,
        if (exe != null) 'exe': exe,
        'prefixArgs': prefixArgs,
      };

  /// Null for anything that is not a saved detection, so one bad entry never
  /// costs the others.
  static DetectedEmulator? fromJson(Object? j) {
    if (j is! Map) return null;
    final presetId = j['presetId'], variant = j['variant'], label = j['label'], systems = j['systems'];
    if (presetId is! String || variant is! String || label is! String || systems is! List) return null;
    String? string(String key) => j[key] is String ? j[key] as String : null;
    List<String> strings(Object? list) => [if (list is List) for (final e in list) if (e is String) e];
    return DetectedEmulator(
      presetId: presetId,
      variant: variant,
      label: label,
      systems: strings(systems),
      version: string('version'),
      dataDir: string('dataDir'),
      requestsManage: j['requestsManage'] == true,
      // Missing reads as true, the constructor's default: a desktop entry.
      pathAccess: j['pathAccess'] != false,
      manageGrant: j['manageGrant'] == true,
      exe: string('exe'),
      prefixArgs: strings(j['prefixArgs']),
    );
  }
}
