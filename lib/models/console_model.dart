import 'package:retro_toolbox/models/game_handler.dart';

class Console {
  final String id;
  final String name;
  final List<String> urls;
  final String? regex;
  /// Boxart source: either an HTML-listing URL (String) or a JSON-map
  /// descriptor ({url, list?, name, image}). See README.
  final Object? boxarts;
  /// clrmamepro-format DAT files whose release years/months date the games
  /// (config key release_dates: one URL or a list).
  final List<String> releaseDates;
  /// Batocera system id (`psx`, `switch`…); see ConsolePlatform for the
  /// resolved value with fallbacks.
  final String? platform;
  /// LaunchBox platform name for metadata lookups; unset uses the built-in map.
  final String? launchboxPlatform;
  /// What the server delivers (`.zip`, `.rar` or the game's own format).
  final List<String>? originalFormat;
  final Decompress decompress;
  /// What stays after decompressing; the rest is pruned. Null keeps all.
  final List<String>? gameFilesFormat;
  final GameHandler? additionalHandler;
  final String? romsFolder;
  final bool extractContents;
  final bool shouldFilterUsa;
  final String? usaRegex;
  final bool ignoreExtensionFiltering;
  final String? downloadUrl;
  /// Run over each game's part of the feed; every match is one update
  /// (named groups label, size, url or id).
  final String? updateRegex;
  /// An update's link when its match has no url: `<id>` is the update's id
  /// group, else the game's; `<game_id>` is always the game's.
  final String? updateDownloadUrl;
  /// The update file's extension; null uses the first original_format.
  final String? updateFormat;
  /// Like updateRegex and updateDownloadUrl, for DLC and for mods. These
  /// matches may also name the file (group name).
  final String? dlcRegex;
  final String? dlcDownloadUrl;
  final String? modRegex;
  final String? modDownloadUrl;
  final Map<String, dynamic>? auth;
  final String? listUrl;
  final String listJsonFileLocation;
  final String listItemId;
  final bool listSystems;
  final bool added;

  const Console({
    required this.id,
    required this.name,
    required this.urls,
    this.regex,
    this.boxarts,
    this.releaseDates = const [],
    this.platform,
    this.launchboxPlatform,
    this.originalFormat,
    this.decompress = Decompress.none,
    this.gameFilesFormat,
    this.additionalHandler,
    this.romsFolder,
    this.extractContents = true,
    this.shouldFilterUsa = true,
    this.usaRegex,
    this.ignoreExtensionFiltering = false,
    this.downloadUrl,
    this.updateRegex,
    this.updateDownloadUrl,
    this.updateFormat,
    this.dlcRegex,
    this.dlcDownloadUrl,
    this.modRegex,
    this.modDownloadUrl,
    this.auth,
    this.listUrl,
    this.listJsonFileLocation = 'files',
    this.listItemId = 'name',
    this.listSystems = false,
    this.added = false,
  });

  /// Handlers that can run on this console's game files, plus the catalog's
  /// own handler, in enum order.
  List<GameHandler> get applicableHandlers {
    final formats = (gameFilesFormat ?? originalFormat ?? const []).map((e) => e.toLowerCase()).toSet();
    return [
      for (final h in GameHandler.values)
        if (h == additionalHandler || h.inputs.any(formats.contains)) h,
    ];
  }

  /// What this console's folder can hold of its games, lowercased with the
  /// dot: what the server sends, what unpacking keeps, and what each handler
  /// that can run here writes. A `.chd`-only PlayStation folder and a kept
  /// `.zip` both count.
  Set<String> get onDiskFormats => {
        for (final f in [...?originalFormat, ...?gameFilesFormat]) f.toLowerCase(),
        for (final h in applicableHandlers) h.output.toLowerCase(),
      };

  bool get hasUpdates => updateRegex != null;

  /// The primary URL (first in the list). Use [urls] when multiple URLs are needed.
  String get url => urls.isNotEmpty ? urls.first : '';

  /// True when this console's games come from the Internet Archive (an IA
  /// listing URL or IA S3 auth), so an IA login can matter for it.
  bool get usesInternetArchive => auth?['type'] == 'ia_s3' || urls.any((u) => u.contains('archive.org'));

  /// True when this console uses a user-editable bearer/cookie token for auth.
  /// IA S3 auth is managed separately via the Internet Archive login flow.
  bool get hasTokenAuth {
    if (auth == null) return false;
    if (auth!['type'] == 'ia_s3') return false;
    return auth!.containsKey('token') || auth!.containsKey('auth_message');
  }

  /// Human-readable instructions for obtaining the auth token.
  String? get authMessage => auth?['auth_message'] as String?;

  /// Whether the token is sent as a cookie (true) or a Bearer header (false).
  bool get authUsesCookies => auth?['cookies'] == true;

  /// Optional username/password sign-in config (auth.signin) that exchanges
  /// credentials for a token via the console's login API.
  Map<String, dynamic>? get authSignin => auth?['signin'] as Map<String, dynamic>?;

  /// Cookie name used when [authUsesCookies] is true.
  String get authCookieName => auth?['cookie_name'] as String? ?? 'auth_token';

  factory Console.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['url'];
    final List<String> urls;
    if (rawUrl is List) {
      urls = List<String>.from(rawUrl);
    } else if (rawUrl is String && rawUrl.isNotEmpty) {
      urls = [rawUrl];
    } else {
      urls = [];
    }
    final rawDates = json['release_dates'];
    // Legacy keys (file_format/should_unzip/…) fill each new key that is
    // missing. With a download_url template should_unzip never had an effect.
    final legacyFormats = (json['file_format'] as List?)?.cast<String>();
    final legacyZip = json['should_unzip'] == true && json['download_url'] == null;
    List<String>? list(String key) => (json[key] as List?)?.cast<String>().toList();

    return Console(
      id: json['id'] as String,
      name: json['name'] as String,
      urls: urls,
      regex: json['regex'] as String?,
      boxarts: json['boxarts'],
      releaseDates: rawDates is List ? List<String>.from(rawDates) : [if (rawDates is String && rawDates.isNotEmpty) rawDates],
      platform: json['platform'] as String?,
      launchboxPlatform: json['launchbox_platform'] as String?,
      originalFormat: list('original_format') ?? (legacyZip ? ['.zip'] : legacyFormats?.toList()),
      decompress: json.containsKey('decompress')
          ? Decompress.fromId(json['decompress'] as String?)
          : (legacyZip ? Decompress.unzip : Decompress.none),
      gameFilesFormat: list('game_files_format') ?? (legacyZip ? legacyFormats?.toList() : null),
      additionalHandler: json.containsKey('additional_handler')
          ? GameHandler.fromId(json['additional_handler'] as String?)
          // Old configs: every .nsz download was decompressed (global switch).
          : json['should_decompress_nsz'] == true || (legacyFormats?.any((f) => f.toLowerCase() == '.nsz') ?? false)
              ? GameHandler.nszDecompress
              : json['convert_3ds_to_cia'] == true
                  ? GameHandler.cia3ds
                  : null,
      romsFolder: json['roms_folder'] as String?,
      extractContents: json['extract_contents'] as bool? ?? true,
      shouldFilterUsa: json['should_filter_usa'] as bool? ?? true,
      usaRegex: json['usa_regex'] as String?,
      ignoreExtensionFiltering: json['ignore_extension_filtering'] as bool? ?? false,
      downloadUrl: json['download_url'] as String?,
      updateRegex: json['update_regex'] as String?,
      updateDownloadUrl: json['update_download_url'] as String?,
      updateFormat: json['update_format'] as String?,
      dlcRegex: json['dlc_regex'] as String?,
      dlcDownloadUrl: json['dlc_download_url'] as String?,
      modRegex: json['mod_regex'] as String?,
      modDownloadUrl: json['mod_download_url'] as String?,
      auth: json['auth'] as Map<String, dynamic>?,
      listUrl: json['list_url'] as String?,
      listJsonFileLocation: json['list_json_file_location'] as String? ?? 'files',
      listItemId: json['list_item_id'] as String? ?? 'name',
      listSystems: json['list_systems'] as bool? ?? false,
      added: json['added'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': urls.length == 1 ? urls.first : urls,
      if (regex != null) 'regex': regex,
      if (boxarts != null) 'boxarts': boxarts,
      if (releaseDates.isNotEmpty) 'release_dates': releaseDates,
      if (platform != null) 'platform': platform,
      if (launchboxPlatform != null) 'launchbox_platform': launchboxPlatform,
      if (originalFormat != null) 'original_format': originalFormat,
      if (decompress != Decompress.none) 'decompress': decompress.name,
      if (gameFilesFormat != null) 'game_files_format': gameFilesFormat,
      if (additionalHandler != null) 'additional_handler': additionalHandler!.id,
      if (romsFolder != null) 'roms_folder': romsFolder,
      'extract_contents': extractContents,
      'should_filter_usa': shouldFilterUsa,
      if (usaRegex != null) 'usa_regex': usaRegex,
      'ignore_extension_filtering': ignoreExtensionFiltering,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (updateRegex != null) 'update_regex': updateRegex,
      if (updateDownloadUrl != null) 'update_download_url': updateDownloadUrl,
      if (updateFormat != null) 'update_format': updateFormat,
      if (dlcRegex != null) 'dlc_regex': dlcRegex,
      if (dlcDownloadUrl != null) 'dlc_download_url': dlcDownloadUrl,
      if (modRegex != null) 'mod_regex': modRegex,
      if (modDownloadUrl != null) 'mod_download_url': modDownloadUrl,
      if (auth != null) 'auth': auth,
      if (listUrl != null) 'list_url': listUrl,
      'list_json_file_location': listJsonFileLocation,
      'list_item_id': listItemId,
      if (listSystems) 'list_systems': listSystems,
      if (added) 'added': added,
    };
  }

  // Default regex matches Myrient-style HTML directory listings.
  // Format: <tr><td class="link"><a href="URL" title="TITLE">TEXT</a></td><td class="size">SIZE</td>...
  String get defaultRegex =>
      '<tr><td class="link"><a href="(?<href>[^"]+)" title="(?<title>[^"]+)">(?<text>[^<]+)</a></td><td class="size">(?<size>[^<]+)</td><td class="date">[^<]*</td></tr>';

  // v4: games saved with their DLC and mods (dlc_regex, mod_regex); older
  // files are ignored, so the first load after the update re-fetches.
  // ponytail: the old files stay behind in the cache dir until it is cleared.
  String get cacheFile => 'catalog_v4_${id.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.json';
}
