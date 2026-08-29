import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Follows redirects manually, re-sending [headers] on every hop, and returns
/// the final URL. HTTP clients strip Authorization/Cookie on cross-host
/// redirects (e.g. archive.org -> its data nodes), so authenticated downloads
/// must be enqueued against the resolved URL.
Future<String> resolveRedirects(String url, Map<String, String> headers, {int maxHops = 5}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);
  try {
    var current = url;
    for (var i = 0; i < maxHops; i++) {
      final request = await client.getUrl(Uri.parse(current));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (response.isRedirect && location != null) {
        current = Uri.parse(current).resolve(location).toString();
        continue;
      }
      break;
    }
    return current;
  } finally {
    client.close();
  }
}

/// Builds request headers for a console's token auth config (`auth`).
/// Cookie-based when `cookies: true`, otherwise a Bearer header.
/// IA S3 auth is handled separately.
Map<String, String> buildConsoleAuthHeaders(Map<String, dynamic>? auth, {String? tokenOverride}) {
  if (auth == null) return {};
  if (auth['type'] == 'ia_s3') return {};

  final token = tokenOverride ?? auth['token'] as String?;
  if (token == null || token.isEmpty) return {};

  if (auth['cookies'] == true) {
    final cookieName = auth['cookie_name'] as String? ?? 'auth_token';
    return {'Cookie': '$cookieName=$token'};
  }
  return {'Authorization': 'Bearer $token'};
}

/// Signs in against a console's `auth.signin` config and returns the token
/// extracted from the response via `token_regex` (group 1, or the whole match).
Future<String> signinForToken(Map<String, dynamic> signin, Map<String, String> fields) async {
  final url = signin['url'] as String;
  final method = (signin['method'] as String? ?? 'POST').toUpperCase();
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    final body = fields.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    request.write(body);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Sign in failed (HTTP ${response.statusCode})');
    }
    final match = RegExp(signin['token_regex'] as String).firstMatch(text);
    final token = match == null ? null : (match.groupCount >= 1 ? match.group(1) : match.group(0));
    if (token == null || token.isEmpty) {
      throw Exception('Sign in succeeded but no token matched token_regex');
    }
    return token;
  } finally {
    client.close();
  }
}

Map<String, String> buildDownloadHeaders(String url, [Map<String, String>? extra]) {
  final rand = Random();

  const languages = [
    'en-US,en;q=0.9',
    'en-GB,en;q=0.9',
    'en-US,en;q=0.8,es;q=0.6',
    'en-US,en;q=0.9,de;q=0.7',
    'en-US,en;q=0.9,pt;q=0.8,gl;q=0.7,es;q=0.6',
  ];

  const platforms = ['"Windows"', '"macOS"', '"Linux"'];

  String randomChromeUA() {
    final major = 135 + rand.nextInt(5);
    final build = 0 + rand.nextInt(10);
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/'
        '$major.0.$build.0 Safari/537.36';
  }

  String randomFirefoxUA() {
    final major = 125 + rand.nextInt(4);
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$major.0) Gecko/20100101 Firefox/$major.0';
  }

  String randomSafariUA() {
    final major = 17;
    final minor = 0 + rand.nextInt(6);
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/'
        '$major.$minor Safari/605.1.15';
  }

  String uaForHost() {
    final pick = rand.nextInt(100);
    if (pick < 55) return randomChromeUA();
    if (pick < 80) return randomFirefoxUA();
    return randomSafariUA();
  }

  String randomSecChUa() {
    final chromeVer = 135 + rand.nextInt(5);
    return '"Not)A;Brand";v="8", "Chromium";v="$chromeVer", "Google Chrome";v="$chromeVer"';
  }

  String randomSecChUaMobile() => rand.nextBool() ? '?0' : '?1';
  String randomSecChUaPlatform() => platforms[rand.nextInt(platforms.length)];
  String randomSecFetchSite() => rand.nextInt(10) < 8 ? 'same-origin' : 'none';

  return {
    'User-Agent': uaForHost(),
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
    'Accept-Language': languages[rand.nextInt(languages.length)],
    // Only gzip: Dart's HttpClient auto-decompresses gzip only; advertising
    // br/zstd makes servers send bodies utf8.decoder can't read.
    'Accept-Encoding': 'gzip',
    'Connection': 'keep-alive',
    'Pragma': 'no-cache',
    'Cache-Control': 'no-cache',
    // 'Host': Uri.tryParse(url)?.host ?? 'localhost', // Dont set 'Host', it can lead to 404 errors in Android
    // No 'Referer': redirect targets (e.g. Yandex storage behind ultranx) reject
    // requests carrying one ("Invalid Referer"); downloaders forward it on redirect.
    'sec-ch-ua': randomSecChUa(),
    'sec-ch-ua-mobile': randomSecChUaMobile(),
    'sec-ch-ua-platform': randomSecChUaPlatform(),
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': randomSecFetchSite(),
    'sec-fetch-user': '?1',
    'upgrade-insecure-requests': '1',
    if (extra != null) ...extra,
  };
}
