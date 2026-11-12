import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/google_auth.dart';

/// google_sign_in's platform side, answered in Dart. One instance serves the whole
/// file because google_sign_in may be initialized only once per process.
class FakePlatform extends GoogleSignInPlatform {
  final inits = <InitParameters>[];
  final requests = <AuthorizationRequestDetails>[];
  final cleared = <String>[];
  int signOuts = 0;
  GoogleSignInException? authenticateFails;
  GoogleSignInException? authorizeFails;
  String? silentToken = 'ya29.silent';

  void reset() {
    requests.clear();
    cleared.clear();
    signOuts = 0;
    authenticateFails = null;
    authorizeFails = null;
    silentToken = 'ya29.silent';
  }

  @override
  Future<void> init(InitParameters params) async => inits.add(params);

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) async => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    if (authenticateFails != null) throw authenticateFails!;
    return const AuthenticationResults(
      user: GoogleSignInUserData(email: 'player@gmail.com', id: '1234567890'),
      authenticationTokens: AuthenticationTokenData(idToken: null),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters params) async {
    requests.add(params.request);
    if (authorizeFails != null) throw authorizeFails!;
    if (params.request.promptIfUnauthorized) return const ClientAuthorizationTokenData(accessToken: 'ya29.granted');
    return silentToken == null ? null : ClientAuthorizationTokenData(accessToken: silentToken!);
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(ServerAuthorizationTokensForScopesParameters params) async => null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async => cleared.add(params.accessToken);

  @override
  Future<void> signOut(SignOutParams params) async => signOuts++;

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

GoogleSignInException failure(GoogleSignInExceptionCode code, [String? description]) => GoogleSignInException(code: code, description: description);

void main() {
  final platform = FakePlatform();
  const clientId = 'web-client.apps.googleusercontent.com';
  const account = GoogleAccount(id: '1234567890', email: 'player@gmail.com');

  setUpAll(() => GoogleSignInPlatform.instance = platform);
  setUp(platform.reset);

  PluginGoogleAuth auth() => PluginGoogleAuth(clientId: clientId, android: true);

  test('available only with a client id, and only on Android', () async {
    expect(auth().available, isTrue);
    expect(PluginGoogleAuth(clientId: '', android: true).available, isFalse);
    expect(PluginGoogleAuth(clientId: clientId, android: false).available, isFalse);
    expect(PluginGoogleAuth(android: true).available, isFalse, reason: 'tests run without --dart-define');
    await expectLater(PluginGoogleAuth(clientId: '', android: true).signIn(), throwsStateError);
    await PluginGoogleAuth(clientId: '', android: true).signOut();
    expect(platform.signOuts, 0);
  });

  test('sign-in initializes once with the client id, then asks for drive.file with prompts allowed', () async {
    expect((await auth().signIn()).email, 'player@gmail.com');
    final again = await auth().signIn();
    expect(again.id, '1234567890');
    expect(platform.inits.map((i) => i.serverClientId), [clientId]);
    expect(platform.requests.map((r) => '${r.scopes} ${r.email} ${r.promptIfUnauthorized}'), [
      '[$driveFileScope] player@gmail.com true',
      '[$driveFileScope] player@gmail.com true',
    ]);
  });

  test('a token is asked for silently and for the stored account; null means the user is needed', () async {
    expect(await auth().token(account), 'ya29.silent');
    expect(platform.requests.single.email, 'player@gmail.com');
    expect(platform.requests.single.userId, '1234567890');
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    platform.silentToken = null;
    expect(await auth().token(account), isNull);
  });

  test('clearToken and signOut reach the plugin', () async {
    await auth().clearToken('ya29.old');
    await auth().signOut();
    expect(platform.cleared, ['ya29.old']);
    expect(platform.signOuts, 1);
  });

  test('plugin failures come out as GoogleAuthError', () async {
    platform.authenticateFails = failure(GoogleSignInExceptionCode.unknownError, 'No credential available: During get sign-in intent, failure response from one tap: 10: ');
    await expectLater(auth().signIn(), throwsA(isA<GoogleAuthError>().having((e) => e.problem, 'problem', GoogleAuthProblem.notRegistered)));
    platform.reset();
    platform.authorizeFails = failure(GoogleSignInExceptionCode.unknownError, 'Authorization failed: 7: ');
    await expectLater(auth().token(account), throwsA(isA<GoogleAuthError>().having((e) => e.problem, 'problem', GoogleAuthProblem.offline)));
  });

  test('every failure the plugin reports maps to what the user should do', () {
    GoogleAuthProblem of(GoogleSignInExceptionCode code, [String? d]) => googleAuthError(failure(code, d)).problem;
    expect(of(GoogleSignInExceptionCode.canceled, 'user canceled'), GoogleAuthProblem.canceled);
    expect(of(GoogleSignInExceptionCode.clientConfigurationError, 'serverClientId must be provided on Android'), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.providerConfigurationError, 'getCredentialAsync no provider dependencies found'), GoogleAuthProblem.noPlayServices);
    expect(of(GoogleSignInExceptionCode.providerConfigurationError, 'Credential Manager not supported. x'), GoogleAuthProblem.noPlayServices);
    expect(of(GoogleSignInExceptionCode.interrupted), GoogleAuthProblem.offline);
    expect(of(GoogleSignInExceptionCode.unknownError, 'Authorization failed: 10: DEVELOPER_ERROR'), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.unknownError, 'SDK reported an exception: 16: '), GoogleAuthProblem.canceled);
    expect(of(GoogleSignInExceptionCode.unknownError, 'SDK reported an exception: 110: '), GoogleAuthProblem.other);
    expect(of(GoogleSignInExceptionCode.uiUnavailable, 'No activity available'), GoogleAuthProblem.other);
    expect(googleAuthError(failure(GoogleSignInExceptionCode.userMismatch)).toString(), 'Google sign-in failed: userMismatch');
    expect(googleAuthError(failure(GoogleSignInExceptionCode.unknownError, 'Authorization failed: 10: ')).toString(),
        contains('build is not registered with Google'));
  });

  test('a build signed with an unregistered key is "not registered", even when Credential Manager calls it a cancel', () async {
    GoogleAuthProblem of(GoogleSignInExceptionCode code, String d) => googleAuthError(failure(code, d)).problem;
    expect(of(GoogleSignInExceptionCode.canceled, '[16] Account reauth failed.'), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.unknownError, '[28444] Developer console is not set up correctly.'), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.unknownError, 'Developer console is not set up correctly.'), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.unknownError, 'No credential available: [28444] '), GoogleAuthProblem.notRegistered);
    expect(of(GoogleSignInExceptionCode.canceled, 'activity is cancelled by the user.'), GoogleAuthProblem.canceled);
    platform.authenticateFails = failure(GoogleSignInExceptionCode.canceled, '[16] Account reauth failed.');
    await expectLater(auth().signIn(), throwsA(isA<GoogleAuthError>().having((e) => '$e', 'text', startsWith('This build is not registered with Google'))));
  });

  test('Drive tokens: kept until refused, then cleared; none without UI means signing in again', () async {
    final tokens = AccountTokens(auth(), account);
    expect(await tokens.token(), 'ya29.silent');
    expect(await tokens.token(), 'ya29.silent');
    expect(platform.requests, hasLength(1));
    await tokens.invalidate('ya29.silent');
    expect(platform.cleared, ['ya29.silent']);
    platform.silentToken = null;
    await expectLater(tokens.token(), throwsA(isA<DriveSignInNeeded>()));
    expect(platform.requests, hasLength(2));
  });
}
