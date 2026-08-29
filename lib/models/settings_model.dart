class AppSettings {
  static const String downloadDir = 'downloadDir';
  static const String autoExtract = 'autoExtract';
  static const String maxParallelDownloads = 'maxParallelDownloads';
  static const String maxParallelExtractions = 'maxParallelExtractions';

  static const Map<String, Type> settingsSchema = {
    downloadDir: String,
    autoExtract: bool,
    maxParallelDownloads: int,
    maxParallelExtractions: int,
  };

  final Map<String, BaseSettings> consoleSettings;
  final BaseSettings generalSettings;
  final String? iaAccessKey;
  final String? iaSecretKey;
  final bool nszDecompressEnabled;
  final String? nszKeysPath;

  const AppSettings({
    this.consoleSettings = const {},
    this.generalSettings = const BaseSettings(),
    this.iaAccessKey,
    this.iaSecretKey,
    this.nszDecompressEnabled = false,
    this.nszKeysPath,
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
    bool clearIaCredentials = false,
    bool? nszDecompressEnabled,
    String? nszKeysPath,
    bool clearNszKeysPath = false,
  }) {
    return AppSettings(
      consoleSettings: consoleSettings ?? this.consoleSettings,
      generalSettings: generalSettings ?? this.generalSettings,
      iaAccessKey: clearIaCredentials ? null : (iaAccessKey ?? this.iaAccessKey),
      iaSecretKey: clearIaCredentials ? null : (iaSecretKey ?? this.iaSecretKey),
      nszDecompressEnabled: nszDecompressEnabled ?? this.nszDecompressEnabled,
      nszKeysPath: clearNszKeysPath ? null : (nszKeysPath ?? this.nszKeysPath),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'consoleSettings': consoleSettings.map((key, value) => MapEntry(key, value.toJson())),
      'generalSettings': generalSettings.toJson(),
      if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
      if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
      'nszDecompressEnabled': nszDecompressEnabled,
      if (nszKeysPath != null) 'nszKeysPath': nszKeysPath,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      consoleSettings: (json['consoleSettings'] as Map<String, dynamic>?)?.map((key, value) => MapEntry(key, BaseSettings.fromJson(value))) ?? {},
      generalSettings: BaseSettings.fromJson(json['generalSettings'] ?? {}),
      iaAccessKey: json['iaAccessKey'] as String?,
      iaSecretKey: json['iaSecretKey'] as String?,
      nszDecompressEnabled: json['nszDecompressEnabled'] as bool? ?? false,
      nszKeysPath: json['nszKeysPath'] as String?,
    );
  }
}

class BaseSettings {
  final String? downloadDir;
  final bool? autoExtract;
  final int? maxParallelDownloads;
  final int? maxParallelExtractions;
  final String? authToken;

  const BaseSettings({
    this.downloadDir,
    this.autoExtract,
    this.maxParallelDownloads,
    this.maxParallelExtractions,
    this.authToken,
  });

  BaseSettings copyWith({
    String? downloadDir,
    bool? autoExtract,
    int? maxParallelDownloads,
    int? maxParallelExtractions,
    String? authToken,
    bool clearAuthToken = false,
  }) {
    return BaseSettings(
      downloadDir: downloadDir == '' ? null : downloadDir ?? this.downloadDir,
      autoExtract: autoExtract ?? this.autoExtract ?? true,
      maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads ?? 5,
      maxParallelExtractions: maxParallelExtractions ?? this.maxParallelExtractions ?? 2,
      authToken: clearAuthToken ? null : (authToken ?? this.authToken),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      AppSettings.downloadDir: downloadDir,
      AppSettings.autoExtract: autoExtract,
      AppSettings.maxParallelDownloads: maxParallelDownloads,
      AppSettings.maxParallelExtractions: maxParallelExtractions,
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
      authToken: json['authToken'] as String?,
    );
  }
}
