/// The vault keys, in one place.
///
/// Warning: these keys live in the user's OS keychain, so changing the format
/// orphans existing credentials with no way to find them back.
class SecretRef {
  /// The token for a console served by an addon. Carries the addon, not just
  /// the console, because two addons can serve the same console id.
  static String addonToken(String addonId, String consoleId) =>
      '${addonPrefix(addonId)}${_sane(consoleId)}';

  /// Everything belonging to an addon, for bulk deletion when it is removed.
  /// Warning: must end in `/`, or `ultranx` would match `ultranx_2` keys.
  static String addonPrefix(String addonId) => 'addon:${_sane(addonId)}/';

  static const iaAccessKey = 'ia/accessKey';
  static const iaSecretKey = 'ia/secretKey';
  static const iaCookies = 'ia/cookies';

  /// Per provider, because Real-Debrid will not be the only one.
  static String debrid(String provider) => 'debrid/${_sane(provider)}';

  /// Replaces the structural chars (`:` and `/`) with `_` so no id can forge
  /// another's key. Warning: not injective, but real ids never distinguish the
  /// collapsed forms because `_nameToId` already collapses non-alphanumerics.
  static String _sane(String part) => part.replaceAll(RegExp(r'[:/]'), '_');
}
