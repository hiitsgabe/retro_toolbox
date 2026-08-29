class AppSettings {
  static const String downloadDir = 'downloadDir';
  static const String autoExtract = 'autoExtract';
  static const String maxParallelDownloads = 'maxParallelDownloads';
  static const String maxParallelExtractions = 'maxParallelExtractions';
  static const String extractToFolder = 'extractToFolder';

  static const Map<String, Type> settingsSchema = {
    downloadDir: String,
    autoExtract: bool,
    maxParallelDownloads: int,
    maxParallelExtractions: int,
    extractToFolder: bool,
  };

  final Map<String, BaseSettings> consoleSettings;
  final BaseSettings generalSettings;
  final String? iaAccessKey;
  final String? iaSecretKey;
  final String? iaCookies; // "logged-in-user=..; logged-in-sig=.." for restricted downloads
  final bool nszDecompressEnabled;
  final String? nszKeysPath;
  final String? catalogSourceUrl; // remote consoles JSON source, if the user pointed at a URL
  final bool steamToolEnabled;
  final bool tinfoilToolEnabled;
  final bool nszToolEnabled;
  final bool jdkvToolEnabled;

  const AppSettings({
    this.consoleSettings = const {},
    this.generalSettings = const BaseSettings(),
    this.iaAccessKey,
    this.iaSecretKey,
    this.iaCookies,
    this.nszDecompressEnabled = true,
    this.nszKeysPath,
    this.catalogSourceUrl,
    this.steamToolEnabled = false,
    this.tinfoilToolEnabled = false,
    this.nszToolEnabled = false,
    this.jdkvToolEnabled = false,
  });

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
    String? nszKeysPath,
    bool clearNszKeysPath = false,
    String? catalogSourceUrl,
    bool clearCatalogSourceUrl = false,
    bool? steamToolEnabled,
    bool? tinfoilToolEnabled,
    bool? nszToolEnabled,
    bool? jdkvToolEnabled,
  }) {
    return AppSettings(
      consoleSettings: consoleSettings ?? this.consoleSettings,
      generalSettings: generalSettings ?? this.generalSettings,
      iaAccessKey: clearIaCredentials ? null : (iaAccessKey ?? this.iaAccessKey),
      iaSecretKey: clearIaCredentials ? null : (iaSecretKey ?? this.iaSecretKey),
      iaCookies: clearIaCredentials ? null : (iaCookies ?? this.iaCookies),
      nszDecompressEnabled: nszDecompressEnabled ?? this.nszDecompressEnabled,
      nszKeysPath: clearNszKeysPath ? null : (nszKeysPath ?? this.nszKeysPath),
      catalogSourceUrl: clearCatalogSourceUrl ? null : (catalogSourceUrl ?? this.catalogSourceUrl),
      steamToolEnabled: steamToolEnabled ?? this.steamToolEnabled,
      tinfoilToolEnabled: tinfoilToolEnabled ?? this.tinfoilToolEnabled,
      nszToolEnabled: nszToolEnabled ?? this.nszToolEnabled,
      jdkvToolEnabled: jdkvToolEnabled ?? this.jdkvToolEnabled,
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
      if (nszKeysPath != null) 'nszKeysPath': nszKeysPath,
      if (catalogSourceUrl != null) 'catalogSourceUrl': catalogSourceUrl,
      'steamToolEnabled': steamToolEnabled,
      'tinfoilToolEnabled': tinfoilToolEnabled,
      'nszToolEnabled': nszToolEnabled,
      'jdkvToolEnabled': jdkvToolEnabled,
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
      nszKeysPath: json['nszKeysPath'] as String?,
      catalogSourceUrl: json['catalogSourceUrl'] as String?,
      steamToolEnabled: json['steamToolEnabled'] as bool? ?? false,
      tinfoilToolEnabled: json['tinfoilToolEnabled'] as bool? ?? false,
      nszToolEnabled: json['nszToolEnabled'] as bool? ?? false,
      jdkvToolEnabled: json['jdkvToolEnabled'] as bool? ?? false,
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

  const BaseSettings({
    this.downloadDir,
    this.autoExtract,
    this.maxParallelDownloads,
    this.maxParallelExtractions,
    this.extractToFolder,
    this.authToken,
  });

  BaseSettings copyWith({
    String? downloadDir,
    bool? autoExtract,
    int? maxParallelDownloads,
    int? maxParallelExtractions,
    bool? extractToFolder,
    String? authToken,
    bool clearAuthToken = false,
  }) {
    return BaseSettings(
      downloadDir: downloadDir == '' ? null : downloadDir ?? this.downloadDir,
      autoExtract: autoExtract ?? this.autoExtract ?? true,
      maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads ?? 5,
      maxParallelExtractions: maxParallelExtractions ?? this.maxParallelExtractions ?? 2,
      extractToFolder: extractToFolder ?? this.extractToFolder,
      authToken: clearAuthToken ? null : (authToken ?? this.authToken),
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
      default:
        throw ArgumentError('Unknown setting key: $key');
    }
  }

  BaseSettings setSetting<T>(String key, T? value) {
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
    );
  }
}
