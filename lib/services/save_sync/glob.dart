/// A recipe pattern over `/`-separated relative paths. `*` and `?` stay
/// inside one segment, `**` spans segments (`**/` also matches none),
/// `[...]` is a character class (`[!...]` negates), and `\x` is a literal x.
class Glob {
  Glob(this.pattern) : _re = RegExp('^${_toRegex(pattern)}\$');

  final String pattern;
  final RegExp _re;

  bool matches(String path) => _re.hasMatch(path);

  static String _toRegex(String g) {
    final b = StringBuffer();
    for (var i = 0; i < g.length; i++) {
      final c = g[i];
      if (c == r'\' && i + 1 < g.length) {
        b.write(RegExp.escape(g[++i]));
      } else if (c == '*') {
        if (i + 1 < g.length && g[i + 1] == '*') {
          i++;
          if (i + 1 < g.length && g[i + 1] == '/') {
            i++;
            b.write('(?:.*/)?');
          } else {
            b.write('.*');
          }
        } else {
          b.write('[^/]*');
        }
      } else if (c == '?') {
        b.write('[^/]');
      } else if (c == '[') {
        final end = g.indexOf(']', i + 1);
        if (end < 0) {
          b.write(r'\[');
          continue;
        }
        var body = g.substring(i + 1, end);
        if (body.startsWith('!')) body = '^${body.substring(1)}';
        b.write('[${body.replaceAll(r'\', r'\\')}]');
        i = end;
      } else {
        b.write(RegExp.escape(c));
      }
    }
    return b.toString();
  }
}

/// Puts the unit [key] in place of `{folder}` and `{file}`, escaped so glob
/// characters in a real file name match literally.
String expandPlaceholders(String pattern, String key) {
  final literal = key.replaceAllMapped(RegExp(r'[*?\[\]\\]'), (m) => '\\${m[0]}');
  return pattern.replaceAll('{folder}', literal).replaceAll('{file}', literal);
}
