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

const _alvo = PackTarget('snes', 'Super Nintendo');
const chronoUsa = 0x2D206BF7;

SourceVerificationRequest _pedido({String? url = 'https://exemplo/ct.zip'}) => (
      sourceId: 'listagem',
      filename: 'Chrono Trigger (USA).zip',
      url: url,
      gameId: 'snes/chrono-trigger',
    );

SourceVerificationService _servico(FakeRangeServer server) =>
    SourceVerificationService(matcher: PackMatcher(buildPack()), fetch: server.fetch);

ProviderContainer _container({
  PackTarget? alvo = _alvo,
  SourceVerificationService? servico,
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(alvo),
    if (servico != null)
      sourceVerificationServiceProvider(_alvo).overrideWith((ref) => servico),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('sem console selecionado ninguém verifica nada', () async {
    final container = _container(alvo: null);

    // Nenhuma sobrescrita de serviço aqui: se o provider tentasse construir
    // um, ele iria à rede de verdade dentro do teste.
    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.notVerified,
    );
  });

  test('console sem pacote fica em notVerified', () async {
    final container = ProviderContainer(overrides: [
      packTargetProvider.overrideWithValue(_alvo),
      packMatcherProvider(_alvo).overrideWith((ref) => null),
    ]);
    addTearDown(container.dispose);

    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.notVerified,
    );
  });

  test('fonte sem url tem verificação impossível', () async {
    final container = _container();

    expect(
      await container.read(sourceVerificationProvider(_pedido(url: null)).future),
      SourceVerification.impossible,
    );
  });

  test('url que não parseia tem verificação impossível', () async {
    final container = _container();

    // `Uri.tryParse` devolve null aqui por causa do colchete sem par.
    expect(
      await container.read(sourceVerificationProvider(_pedido(url: 'http://[')).future),
      SourceVerification.impossible,
    );
  });

  test('o veredito do serviço chega inteiro', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    expect(
      await container.read(sourceVerificationProvider(_pedido()).future),
      SourceVerification.crcOk,
    );
  });

  test('enquanto a leitura roda o estado é verificando', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    // `verifying` não sai do provider: ele é o `AsyncLoading` traduzido.
    expect(
      verificationOf(container.read(sourceVerificationProvider(_pedido()))),
      SourceVerification.verifying,
    );

    await container.read(sourceVerificationProvider(_pedido()).future);

    expect(
      verificationOf(container.read(sourceVerificationProvider(_pedido()))),
      SourceVerification.crcOk,
    );
  });

  test('o mesmo par fonte e arquivo é lido uma vez só', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final container = _container(servico: _servico(server));

    await container.read(sourceVerificationProvider(_pedido()).future);
    await container.read(sourceVerificationProvider(_pedido()).future);

    // Duas requisições, não quatro. É o cache da seção 8, e ele é a família
    // viva do Riverpod, não um `Map` escrito à mão.
    expect(server.asked.length, 2);
  });

  test('erro vira impossível, e não tela vermelha', () async {
    expect(
      verificationOf(AsyncError(Exception('pacote não carregou'), StackTrace.empty)),
      SourceVerification.impossible,
    );
  });
}
