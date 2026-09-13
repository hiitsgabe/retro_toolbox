import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

const _target = PackTarget('snes', 'Super Nintendo');
const crystalUsa = 0x2D206BF7;

SourceVerificationRequest _request({String? url = 'https://example/ct.zip'}) => (
      sourceId: 'listing',
      filename: 'Crystal Vanguard (USA).zip',
      url: url,
      gameId: 'snes/crystal-vanguard',
    );

SourceVerificationService _service(FakeRangeServer server) =>
    SourceVerificationService(matcher: PackMatcher(buildPack()), fetch: server.fetch);

ProviderContainer _container({
  PackTarget? target = _target,
  SourceVerificationService? service,
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(target),
    if (service != null)
      sourceVerificationServiceProvider(_target).overrideWith((ref) => service),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('no selected console verifies nothing', () async {
    final container = _container(target: null);

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.notVerified,
    );
  });

  test('console without a pack stays notVerified', () async {
    final container = ProviderContainer(overrides: [
      packTargetProvider.overrideWithValue(_target),
      packMatcherProvider(_target).overrideWith((ref) => null),
    ]);
    addTearDown(container.dispose);

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.notVerified,
    );
  });

  test('a source without a url is impossible', () async {
    final container = _container();

    expect(
      await container.read(sourceVerificationProvider(_request(url: null)).future),
      SourceVerification.impossible,
    );
  });

  test('a url that does not parse is impossible', () async {
    final container = _container();

    expect(
      await container.read(sourceVerificationProvider(_request(url: 'http://[')).future),
      SourceVerification.impossible,
    );
  });

  test('the service verdict passes through intact', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.crcOk,
    );
  });

  test('the state is verifying while the read runs', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    expect(
      verificationOf(container.read(sourceVerificationProvider(_request()))),
      SourceVerification.verifying,
    );

    await container.read(sourceVerificationProvider(_request()).future);

    expect(
      verificationOf(container.read(sourceVerificationProvider(_request()))),
      SourceVerification.crcOk,
    );
  });

  test('the same source and file pair is read only once', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    await container.read(sourceVerificationProvider(_request()).future);
    await container.read(sourceVerificationProvider(_request()).future);

    // Two requests, not four: the cache is the live Riverpod family.
    expect(server.asked.length, 2);
  });

  test('an error becomes impossible, not a red screen', () async {
    expect(
      verificationOf(AsyncError(Exception('pack did not load'), StackTrace.empty)),
      SourceVerification.impossible,
    );
  });
}
