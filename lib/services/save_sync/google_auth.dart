import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';

/// The Web OAuth client id this build was made with
/// (`--dart-define=GDRIVE_SERVER_CLIENT_ID=...`). Empty in forks and plain
/// local builds: Google Drive is then hidden and the folder hub offered.
const googleServerClientId = String.fromEnvironment('GDRIVE_SERVER_CLIENT_ID');

/// The only scope the app asks for: files the app itself created.
const driveFileScope = 'https://www.googleapis.com/auth/drive.file';

class GoogleAccount {
  const GoogleAccount({required this.id, required this.email});

  final String id;
  final String email;
}

enum GoogleAuthProblem { canceled, notRegistered, noPlayServices, offline, other }

/// A sign-in that did not finish. [toString] is for the user.
class GoogleAuthError implements Exception {
  const GoogleAuthError(this.problem, [this.detail = '']);

  final GoogleAuthProblem problem;

  /// What google_sign_in said, for the "other" case and for bug reports.
  final String detail;

  @override
  String toString() => switch (problem) {
        GoogleAuthProblem.canceled => 'Sign-in canceled.',
        GoogleAuthProblem.notRegistered => 'This build is not registered with Google, so it cannot use Google Drive. Use a folder instead.',
        GoogleAuthProblem.noPlayServices => 'Google sign-in needs Google Play services, which this device does not have. Use a folder instead.',
        GoogleAuthProblem.offline => 'Could not reach Google. Check the connection and try again.',
        GoogleAuthProblem.other => 'Google sign-in failed: $detail',
      };
}

final _statusCode = RegExp(r'(?<![0-9])([0-9]+): ');

/// Texts Google gives a build whose package and signing key are not registered
/// (a fork signed with another key). Credential Manager reports
/// `[16] Account reauth failed.` as a cancel, so these are checked before the code.
final _unregistered = RegExp(r'DEVELOPER_ERROR|\[28444\]|Developer console is not set up correctly|Account reauth failed');

/// What a google_sign_in failure means for the user. Play services puts its
/// status code in the description (`Authorization failed: 10: ...`): 10 is
/// DEVELOPER_ERROR (this package and signing key are not registered with the
/// app's Google Cloud project), 16 is CANCELED, 7 is NETWORK_ERROR.
GoogleAuthError googleAuthError(GoogleSignInException e) {
  final d = e.description ?? '';
  final status = int.tryParse(_statusCode.firstMatch(d)?.group(1) ?? '');
  return switch (e.code) {
    _ when status == 10 || _unregistered.hasMatch(d) => GoogleAuthError(GoogleAuthProblem.notRegistered, d),
    GoogleSignInExceptionCode.canceled => GoogleAuthError(GoogleAuthProblem.canceled, d),
    GoogleSignInExceptionCode.clientConfigurationError => GoogleAuthError(GoogleAuthProblem.notRegistered, d),
    GoogleSignInExceptionCode.providerConfigurationError => GoogleAuthError(GoogleAuthProblem.noPlayServices, d),
    GoogleSignInExceptionCode.interrupted => GoogleAuthError(GoogleAuthProblem.offline, d),
    _ when status == 16 => GoogleAuthError(GoogleAuthProblem.canceled, d),
    _ when status == 7 => GoogleAuthError(GoogleAuthProblem.offline, d),
    _ => GoogleAuthError(GoogleAuthProblem.other, d.isEmpty ? e.code.name : d),
  };
}

/// Google sign-in for the Drive hub. [PluginGoogleAuth] is the real one; tests use fakes.
abstract class GoogleAuth {
  /// This build has a Google client id and runs where google_sign_in works (Android).
  bool get available;

  /// The account sheet, then the Drive consent screen. Throws [GoogleAuthError].
  Future<GoogleAccount> signIn();

  /// A Drive token for [account] without any UI; null when only the user can grant one.
  /// Throws [GoogleAuthError].
  Future<String?> token(GoogleAccount account);

  /// Drops [token] from the cache, so the next [token] call gets a new one.
  Future<void> clearToken(String token);

  /// Forgets the account on this device. The Drive grant stays, so files the
  /// app made stay visible to it after the next sign-in.
  Future<void> signOut();
}

/// Tokens for [DriveApi]: no token without UI means "sign in again". A token
/// is kept until Drive refuses it, so a refresh asks Play services once.
class AccountTokens implements DriveTokens {
  AccountTokens(this.auth, this.account);

  final GoogleAuth auth;
  final GoogleAccount account;
  String? _token;

  @override
  Future<String> token() async => _token ??= await auth.token(account) ?? (throw DriveSignInNeeded());

  @override
  Future<void> invalidate(String stale) async {
    if (_token == stale) _token = null;
    await auth.clearToken(stale);
  }
}

/// google_sign_in 7 on Android, with the Web client id as serverClientId.
class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth({this.clientId = googleServerClientId, bool? android}) : _android = android ?? Platform.isAndroid;

  final String clientId;
  final bool _android;

  /// google_sign_in must be initialized exactly once per process.
  static Future<void>? _ready;

  @override
  bool get available => _android && clientId.isNotEmpty;

  Future<void> _init() {
    // Off Android there is no implementation (Linux, Windows) or a native one that crashes on a bad
    // configuration (macOS), and an empty serverClientId fails on Android: never get that far.
    if (!available) throw StateError('Google sign-in is not available in this build');
    return _ready ??= GoogleSignIn.instance.initialize(serverClientId: clientId).then((_) {}, onError: (Object e, StackTrace st) {
      _ready = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  @override
  Future<GoogleAccount> signIn() async {
    await _init();
    try {
      final user = await GoogleSignIn.instance.authenticate(scopeHint: const [driveFileScope]);
      await user.authorizationClient.authorizeScopes(const [driveFileScope]);
      return GoogleAccount(id: user.id, email: user.email);
    } on GoogleSignInException catch (e) {
      throw googleAuthError(e);
    }
  }

  @override
  Future<String?> token(GoogleAccount account) async {
    await _init();
    try {
      // The platform interface, because the app-facing client cannot be rebuilt for a stored account
      // after a restart, and a request without the email would let Play services pick any account.
      final t = await GoogleSignInPlatform.instance.clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(scopes: const [driveFileScope], userId: account.id, email: account.email, promptIfUnauthorized: false),
      ));
      return t?.accessToken;
    } on GoogleSignInException catch (e) {
      throw googleAuthError(e);
    }
  }

  @override
  Future<void> clearToken(String token) async {
    await _init();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: token);
  }

  @override
  Future<void> signOut() async {
    if (!available) return;
    await _init();
    await GoogleSignIn.instance.signOut();
  }
}
