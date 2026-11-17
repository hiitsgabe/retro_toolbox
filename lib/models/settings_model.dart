class AppSettings {
  static const String downloadDir = 'downloadDir';
  static const String autoExtract = 'autoExtract';
  static const String maxParallelDownloads = 'maxParallelDownloads';
  static const String maxParallelExtractions = 'maxParallelExtractions';
  static const String extractToFolder = 'extractToFolder';
  static const String autoApplyFormations = 'autoApplyFormations';
  static const String additionalHandler = 'additionalHandler';
  static const String chdIsoAsCd = 'chdIsoAsCd';
  static const String groupVersions = 'groupVersions';
  static const String downloadAllDiscs = 'downloadAllDiscs';
  static const String updatesDir = 'updatesDir';
  static const String updateDecompress = 'updateDecompress';
  static const String updateHandler = 'updateHandler';

  static const Map<String, Type> settingsSchema = {
    downloadDir: String,
    autoExtract: bool,
    maxParallelDownloads: int,
    maxParallelExtractions: int,
    extractToFolder: bool,
    autoApplyFormations: bool,
    additionalHandler: String,
    chdIsoAsCd: bool,
    groupVersions: bool,
    downloadAllDiscs: bool,
    updatesDir: String,
    updateDecompress: String,
    updateHandler: String,
  };

  final Map<String, BaseSettings> consoleSettings;
  final BaseSettings generalSettings;
  final String? iaAccessKey;
  final String? iaSecretKey;
  final String? iaCookies; // "logged-in-user=..; logged-in-sig=.." for restricted downloads
  final bool nszDecompressEnabled;
  final bool useOnScreenKeyboard; // built-in keyboard instead of the platform IME (gamepads)
  final String? nszKeysPath;
  final String? chdmanPath; // user-set path to a chdman binary, if any
  final String? catalogSourceUrl; // remote consoles JSON source, if the user pointed at a URL
  final String? preferredLocalIp; // LAN IP all servers advertise/use, if chosen
  final String? boot9Path; // user-set boot9.bin or aes_keys.txt for 3DS->CIA conversion
  // Games Library and downloads, opt-in. Null until the first load decides it
  // (on when a user catalog already exists, see SettingsNotifier).
  final bool? libraryEnabled;
  // Console install servers, opt-in (Settings → Extra servers). Off until the
  // user turns one on; the switch also gates its Servers-menu tile.
  final bool? tinfoilEnabled;
  final bool? fbiEnabled;
  final bool? fpkgiEnabled;

  const AppSettings({
    this.consoleSettings = const {},
    this.generalSettings = const BaseSettings(),
    this.iaAccessKey,
    this.iaSecretKey,
    this.iaCookies,
    this.nszDecompressEnabled = true,
    this.useOnScreenKeyboard = false,
    this.nszKeysPath,
    this.chdmanPath,
    this.catalogSourceUrl,
    this.preferredLocalIp,
    this.boot9Path,
    this.libraryEnabled,
    this.tinfoilEnabled,
    this.fbiEnabled,
    this.fpkgiEnabled,
  });

  bool get isLibraryEnabled => libraryEnabled ?? false;
  bool get isTinfoilEnabled => tinfoilEnabled ?? false;
  bool get isFbiEnabled => fbiEnabled ?? false;
  bool get isFpkgiEnabled => fpkgiEnabled ?? false;

  bool get hasIaCredentials =>
      iaAccessKey != null && iaAccessKey!.isNotEmpty &&
      iaSecretKey != null && iaSecretKey!.isNotEmpty;

  bool get hasNszKeys => nszKeysPath != null && nszKeysPath!.isNotEmpty;

  AppSettings copyWith({
    Map<String, BaseSettings>? consoleSettings,
    BaseSettings? generalSettings,
    String? iaAccessKey,
    String? iaSecretKey,
    String? iaCookies,
    bool clearIaCredentials = false,
    bool? nszDecompressEnabled,
    bool? useOnScreenKeyboard,
    String? nszKeysPath,
    bool clearNszKeysPath = false,
    String? chdmanPath,
    bool clearChdmanPath = false,
    String? catalogSourceUrl,
    bool clearCatalogSourceUrl = false,
    String? preferredLocalIp,
    bool clearPreferredLocalIp = false,
    String? boot9Path,
    bool clearBoot9Path = false,
    bool? libraryEnabled,
    bool? tinfoilEnabled,
    bool? fbiEnabled,
    bool? fpkgiEnabled,
  }) {
    return AppSettings(
      consoleSettings: consoleSettings ?? this.consoleSettings,
      generalSettings: generalSettings ?? this.generalSettings,
      iaAccessKey: clearIaCredentials ? null : (iaAccessKey ?? this.iaAccessKey),
      iaSecretKey: clearIaCredentials ? null : (iaSecretKey ?? this.iaSecretKey),
      iaCookies: clearIaCredentials ? null : (iaCookies ?? this.iaCookies),
      nszDecompressEnabled: nszDecompressEnabled ?? this.nszDecompressEnabled,
      useOnScreenKeyboard: useOnScreenKeyboard ?? this.useOnScreenKeyboard,
      nszKeysPath: clearNszKeysPath ? null : (nszKeysPath ?? this.nszKeysPath),
      chdmanPath: clearChdmanPath ? null : (chdmanPath ?? this.chdmanPath),
      catalogSourceUrl: clearCatalogSourceUrl ? null : (catalogSourceUrl ?? this.catalogSourceUrl),
      preferredLocalIp: clearPreferredLocalIp ? null : (preferredLocalIp ?? this.preferredLocalIp),
      boot9Path: clearBoot9Path ? null : (boot9Path ?? this.boot9Path),
      libraryEnabled: libraryEnabled ?? this.libraryEnabled,
      tinfoilEnabled: tinfoilEnabled ?? this.tinfoilEnabled,
      fbiEnabled: fbiEnabled ?? this.fbiEnabled,
      fpkgiEnabled: fpkgiEnabled ?? this.fpkgiEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'consoleSettings': consoleSettings.map((key, value) => MapEntry(key, value.toJson())),
      'generalSettings': generalSettings.toJson(),
      if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
      if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
      if (iaCookies != null) 'iaCookies': iaCookies,
      'nszDecompressEnabled': nszDecompressEnabled,
      'useOnScreenKeyboard': useOnScreenKeyboard,
      if (nszKeysPath != null) 'nszKeysPath': nszKeysPath,
      if (chdmanPath != null) 'chdmanPath': chdmanPath,
      if (catalogSourceUrl != null) 'catalogSourceUrl': catalogSourceUrl,
      if (preferredLocalIp != null) 'preferredLocalIp': preferredLocalIp,
      if (boot9Path != null) 'boot9Path': boot9Path,
      if (libraryEnabled != null) 'libraryEnabled': libraryEnabled,
      if (tinfoilEnabled != null) 'tinfoilEnabled': tinfoilEnabled,
      if (fbiEnabled != null) 'fbiEnabled': fbiEnabled,
      if (fpkgiEnabled != null) 'fpkgiEnabled': fpkgiEnabled,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      consoleSettings: (json['consoleSettings'] as Map<String, dynamic>?)?.map((key, value) => MapEntry(key, BaseSettings.fromJson(value))) ?? {},
      generalSettings: BaseSettings.fromJson(json['generalSettings'] ?? {}),
      iaAccessKey: json['iaAccessKey'] as String?,
      iaSecretKey: json['iaSecretKey'] as String?,
      iaCookies: json['iaCookies'] as String?,
      nszDecompressEnabled: json['nszDecompressEnabled'] as bool? ?? true,
      useOnScreenKeyboard: json['useOnScreenKeyboard'] as bool? ?? false,
      nszKeysPath: json['nszKeysPath'] as String?,
      chdmanPath: json['chdmanPath'] as String?,
      catalogSourceUrl: json['catalogSourceUrl'] as String?,
      preferredLocalIp: json['preferredLocalIp'] as String?,
      boot9Path: json['boot9Path'] as String?,
      libraryEnabled: json['libraryEnabled'] as bool?,
      tinfoilEnabled: json['tinfoilEnabled'] as bool?,
      fbiEnabled: json['fbiEnabled'] as bool?,
      fpkgiEnabled: json['fpkgiEnabled'] as bool?,
    );
  }
}

class BaseSettings {
  final String? downloadDir;
  final bool? autoExtract;
  final int? maxParallelDownloads;
  final int? maxParallelExtractions;
  final bool? extractToFolder;
  final String? authToken;
  final bool? autoApplyFormations;
  /// Per-console handler choice: a GameHandler id, or 'none'. Null = catalog's.
  final String? additionalHandler;
  /// Per-console: the CHD handler packs an .iso as a CD CHD (AetherSX2) instead of a DVD one.
  final bool? chdIsoAsCd;
  /// The game list shows one entry per game (its versions, discs and extras inside). Null = on.
  final bool? groupVersions;
  /// Download on a grouped game gets every disc. Null = on.
  final bool? downloadAllDiscs;
  /// Per console: where its updates go. Null = a folder named updates in its
  /// download folder.
  final String? updatesDir;
  /// Per console: how its updates are unpacked, a Decompress name. Null = as
  /// the game.
  final String? updateDecompress;
  /// Per console: what runs on its updates, a GameHandler id or 'none'. Null
  /// = as the game.
  final String? updateHandler;

  const BaseSettings({
    this.downloadDir,
    this.autoExtract,
    this.maxParallelDownloads,
    this.maxParallelExtractions,
    this.extractToFolder,
    this.authToken,
    this.autoApplyFormations,
    this.additionalHandler,
    this.chdIsoAsCd,
    this.groupVersions,
    this.downloadAllDiscs,
    this.updatesDir,
    this.updateDecompress,
    this.updateHandler,
  });

  BaseSettings copyWith({
    String? downloadDir,
    bool? autoExtract,
    int? maxParallelDownloads,
    int? maxParallelExtractions,
    bool? extractToFolder,
    String? authToken,
    bool clearAuthToken = false,
    bool? autoApplyFormations,
    String? additionalHandler,
    bool clearAdditionalHandler = false,
    bool? chdIsoAsCd,
    bool? groupVersions,
    bool? downloadAllDiscs,
    String? updatesDir,
    String? updateDecompress,
    String? updateHandler,
  }) {
    return BaseSettings(
      downloadDir: downloadDir == '' ? null : downloadDir ?? this.downloadDir,
      autoExtract: autoExtract ?? this.autoExtract ?? true,
      maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads ?? 5,
      maxParallelExtractions: maxParallelExtractions ?? this.maxParallelExtractions ?? 2,
      extractToFolder: extractToFolder ?? this.extractToFolder,
      authToken: clearAuthToken ? null : (authToken ?? this.authToken),
      autoApplyFormations: autoApplyFormations ?? this.autoApplyFormations ?? true,
      additionalHandler: clearAdditionalHandler ? null : (additionalHandler ?? this.additionalHandler),
      chdIsoAsCd: chdIsoAsCd ?? this.chdIsoAsCd,
      groupVersions: groupVersions ?? this.groupVersions,
      downloadAllDiscs: downloadAllDiscs ?? this.downloadAllDiscs,
      updatesDir: updatesDir ?? this.updatesDir,
      updateDecompress: updateDecompress ?? this.updateDecompress,
      updateHandler: updateHandler ?? this.updateHandler,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      AppSettings.downloadDir: downloadDir,
      AppSettings.autoExtract: autoExtract,
      AppSettings.maxParallelDownloads: maxParallelDownloads,
      AppSettings.maxParallelExtractions: maxParallelExtractions,
      if (extractToFolder != null) AppSettings.extractToFolder: extractToFolder,
      if (authToken != null) 'authToken': authToken,
      if (autoApplyFormations != null) AppSettings.autoApplyFormations: autoApplyFormations,
      if (additionalHandler != null) AppSettings.additionalHandler: additionalHandler,
      if (chdIsoAsCd != null) AppSettings.chdIsoAsCd: chdIsoAsCd,
      if (groupVersions != null) AppSettings.groupVersions: groupVersions,
      if (downloadAllDiscs != null) AppSettings.downloadAllDiscs: downloadAllDiscs,
      if (updatesDir != null) AppSettings.updatesDir: updatesDir,
      if (updateDecompress != null) AppSettings.updateDecompress: updateDecompress,
      if (updateHandler != null) AppSettings.updateHandler: updateHandler,
    };
  }

  T? getSetting<T>(String key) {
    switch (key) {
      case AppSettings.downloadDir:
        return downloadDir as T?;
      case AppSettings.autoExtract:
        return autoExtract as T?;
      case AppSettings.maxParallelDownloads:
        return maxParallelDownloads as T?;
      case AppSettings.maxParallelExtractions:
        return maxParallelExtractions as T?;
      case AppSettings.extractToFolder:
        return extractToFolder as T?;
      case AppSettings.autoApplyFormations:
        return (autoApplyFormations ?? true) as T?;
      case AppSettings.additionalHandler:
        return additionalHandler as T?;
      case AppSettings.chdIsoAsCd:
        return chdIsoAsCd as T?;
      case AppSettings.groupVersions:
        return groupVersions as T?;
      case AppSettings.downloadAllDiscs:
        return downloadAllDiscs as T?;
      case AppSettings.updatesDir:
        return updatesDir as T?;
      case AppSettings.updateDecompress:
        return updateDecompress as T?;
      case AppSettings.updateHandler:
        return updateHandler as T?;
      default:
        throw ArgumentError('Unknown setting key: $key');
    }
  }

  /// A copy with [key] set to [value]. Unlike [copyWith], the other keys keep
  /// a null (following the general setting) instead of taking a default, so
  /// setting one thing for a console does not pin the rest.
  BaseSettings setSetting<T>(String key, T? value) {
    final next = _set(key, value);
    return BaseSettings(
      downloadDir: next.downloadDir,
      autoExtract: key == AppSettings.autoExtract ? next.autoExtract : autoExtract,
      maxParallelDownloads: key == AppSettings.maxParallelDownloads ? next.maxParallelDownloads : maxParallelDownloads,
      maxParallelExtractions: key == AppSettings.maxParallelExtractions ? next.maxParallelExtractions : maxParallelExtractions,
      extractToFolder: next.extractToFolder,
      authToken: next.authToken,
      autoApplyFormations: key == AppSettings.autoApplyFormations ? next.autoApplyFormations : autoApplyFormations,
      additionalHandler: next.additionalHandler,
      chdIsoAsCd: next.chdIsoAsCd,
      groupVersions: next.groupVersions,
      downloadAllDiscs: next.downloadAllDiscs,
      updatesDir: next.updatesDir,
      updateDecompress: next.updateDecompress,
      updateHandler: next.updateHandler,
    );
  }

  /// A copy without a value for [key]: a console's copy then follows the
  /// general setting again.
  BaseSettings cleared(String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return BaseSettings.fromJson(toJson()..remove(key));
  }

  BaseSettings _set<T>(String key, T? value) {
    switch (key) {
      case AppSettings.downloadDir:
        return copyWith(downloadDir: value as String?);
      case AppSettings.autoExtract:
        return copyWith(autoExtract: value as bool?);
      case AppSettings.maxParallelDownloads:
        return copyWith(maxParallelDownloads: value as int?);
      case AppSettings.maxParallelExtractions:
        return copyWith(maxParallelExtractions: value as int?);
      case AppSettings.extractToFolder:
        return copyWith(extractToFolder: value as bool?);
      case AppSettings.autoApplyFormations:
        return copyWith(autoApplyFormations: value as bool?);
      case AppSettings.additionalHandler:
        return copyWith(additionalHandler: value as String?, clearAdditionalHandler: value == null);
      case AppSettings.chdIsoAsCd:
        return copyWith(chdIsoAsCd: value as bool?);
      case AppSettings.groupVersions:
        return copyWith(groupVersions: value as bool?);
      case AppSettings.downloadAllDiscs:
        return copyWith(downloadAllDiscs: value as bool?);
      case AppSettings.updatesDir:
        return copyWith(updatesDir: value as String?);
      case AppSettings.updateDecompress:
        return copyWith(updateDecompress: value as String?);
      case AppSettings.updateHandler:
        return copyWith(updateHandler: value as String?);
      default:
        throw ArgumentError('Unknown setting key: $key');
    }
  }

  factory BaseSettings.fromJson(Map<String, dynamic> json) {
    return BaseSettings(
      downloadDir: json[AppSettings.downloadDir] as String?,
      autoExtract: json[AppSettings.autoExtract] as bool?,
      maxParallelDownloads: json[AppSettings.maxParallelDownloads] as int?,
      maxParallelExtractions: json[AppSettings.maxParallelExtractions] as int?,
      extractToFolder: json[AppSettings.extractToFolder] as bool?,
      authToken: json['authToken'] as String?,
      autoApplyFormations: json[AppSettings.autoApplyFormations] as bool?,
      additionalHandler: json[AppSettings.additionalHandler] as String?,
      chdIsoAsCd: json[AppSettings.chdIsoAsCd] as bool?,
      // 'groupDiscs' is the key before grouping covered versions; a saved choice carries over.
      groupVersions: (json[AppSettings.groupVersions] ?? json['groupDiscs']) as bool?,
      downloadAllDiscs: json[AppSettings.downloadAllDiscs] as bool?,
      updatesDir: json[AppSettings.updatesDir] as String?,
      updateDecompress: json[AppSettings.updateDecompress] as String?,
      updateHandler: json[AppSettings.updateHandler] as String?,
    );
  }
}
