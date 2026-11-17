import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';

/// One token or cookie login the loaded catalog asks for, shared by the
/// consoles that send the same one.
class CatalogLogin {
  const CatalogLogin({required this.title, required this.consoles});

  /// The site, from the catalog's sign-in config, else a console's name.
  final String title;

  /// In catalog order; the first one's auth config drives the sign-in.
  final List<Console> consoles;

  List<String> get consoleIds => [for (final c in consoles) c.id];

  /// Every console has a token.
  bool signedInWith(AppSettings s) => consoles.every((c) => (s.consoleSettings[c.id]?.authToken ?? '').isNotEmpty);
}

String? _host(Object? url) {
  if (url is! String || url.isEmpty) return null;
  final host = Uri.tryParse(url)?.host ?? '';
  return host.isEmpty ? null : host;
}

/// The token and cookie logins among [consoles], built only from each
/// console's auth config. Consoles share a login when their sign-in page
/// (auth.signin.register_url) has the same host, else when their auth_message
/// is the same text; any other console has its own.
List<CatalogLogin> catalogLogins(Iterable<Console> consoles) {
  final groups = <String, List<Console>>{};
  for (final c in consoles) {
    if (!c.hasTokenAuth) continue;
    final host = _host(c.authSignin?['register_url']);
    final message = c.authMessage;
    final key = host != null
        ? 'host:$host'
        : message != null && message.isNotEmpty
            ? 'message:$message'
            : 'console:${c.id}';
    groups.putIfAbsent(key, () => []).add(c);
  }
  return [
    for (final g in groups.values)
      CatalogLogin(
        title: _host(g.first.authSignin?['register_url']) ?? _host(g.first.authSignin?['url']) ?? g.first.name,
        consoles: g,
      ),
  ];
}

/// The loaded consoles whose games come from the Internet Archive.
List<Console> internetArchiveConsoles(Iterable<Console> consoles) => [
      for (final c in consoles)
        if (c.usesInternetArchive) c
    ];
