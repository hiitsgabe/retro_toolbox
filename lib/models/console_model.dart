class Console {
  final String id;
  final String name;
  final List<String> urls;
  final String? regex;
  final String? boxarts;
  final List<String>? fileFormat;
  final String? romsFolder;
  final bool shouldUnzip;
  final bool extractContents;
  final bool shouldFilterUsa;
  final String? usaRegex;
  final bool shouldDecompressNsz;
  final bool ignoreExtensionFiltering;
  final String? downloadUrl;
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
    this.fileFormat,
    this.romsFolder,
    this.shouldUnzip = false,
    this.extractContents = true,
    this.shouldFilterUsa = true,
    this.usaRegex,
    this.shouldDecompressNsz = false,
    this.ignoreExtensionFiltering = false,
    this.downloadUrl,
    this.auth,
    this.listUrl,
    this.listJsonFileLocation = 'files',
    this.listItemId = 'name',
    this.listSystems = false,
    this.added = false,
  });

  /// The primary URL (first in the list). Use [urls] when multiple URLs are needed.
  String get url => urls.isNotEmpty ? urls.first : '';

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

    return Console(
      id: json['id'] as String,
      name: json['name'] as String,
      urls: urls,
      regex: json['regex'] as String?,
      boxarts: json['boxarts'] as String?,
      fileFormat: json['file_format'] != null ? List<String>.from(json['file_format'] as List) : null,
      romsFolder: json['roms_folder'] as String?,
      shouldUnzip: json['should_unzip'] as bool? ?? false,
      extractContents: json['extract_contents'] as bool? ?? true,
      shouldFilterUsa: json['should_filter_usa'] as bool? ?? true,
      usaRegex: json['usa_regex'] as String?,
      shouldDecompressNsz: json['should_decompress_nsz'] as bool? ?? false,
      ignoreExtensionFiltering: json['ignore_extension_filtering'] as bool? ?? false,
      downloadUrl: json['download_url'] as String?,
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
      if (fileFormat != null) 'file_format': fileFormat,
      if (romsFolder != null) 'roms_folder': romsFolder,
      'should_unzip': shouldUnzip,
      'extract_contents': extractContents,
      'should_filter_usa': shouldFilterUsa,
      if (usaRegex != null) 'usa_regex': usaRegex,
      'should_decompress_nsz': shouldDecompressNsz,
      'ignore_extension_filtering': ignoreExtensionFiltering,
      if (downloadUrl != null) 'download_url': downloadUrl,
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

  String get cacheFile => 'catalog_${id.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.json';
}
