import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Como o catálogo chega da rede.
///
/// Entra por parâmetro porque `http` não é dependência deste projeto, então
/// não existe `MockClient` aqui: sem a injeção, testar esta função pediria um
/// servidor de verdade.
typedef CatalogFetcher = Future<String> Function(String url);

/// Baixa o catálogo de [url], guarda os tokens que vierem nele e instala a
/// fonte como um addon.
///
/// A ordem é a metade incondicional da seção 6.3 do spec: colher antes de
/// validar e antes de gravar. Nada toca o disco enquanto
/// [CatalogService.harvestAuthTokens] não devolveu o JSON sem os tokens.
///
/// Quando a validação falha depois da colheita, o segredo fica no cofre e o
/// addon não entra na lista. É de propósito: o token veio do arquivo que o
/// usuário mandou instalar, e uma entrada de cofre sob um id que não está na
/// lista não é lida por ninguém.
///
/// Levanta [FormatException] se o corpo não for um catálogo com pelo menos um
/// console, e o que [fetch] levantar se a rede falhar.
Future<Addon> installAddonFromUrl(
  String url, {
  required AddonNotifier notifier,
  required SecretVault vault,
  CatalogFetcher? fetch,
}) async {
  final body = await (fetch ?? fetchCatalogByHttp)(url);
  final id = Addon.idFromUrl(url);

  final limpo = await CatalogService.harvestAuthTokens(body, vault: vault, addonId: id);
  if (CatalogService.parseConsoles(limpo).isEmpty) {
    throw const FormatException('No consoles found in the provided catalog.');
  }

  final addon = Addon(id: id, name: _nomeDe(url, id), url: url);
  await notifier.install(addon, limpo);
  return addon;
}

/// O nome que aparece na lista de addons: o host, sem `www.`.
///
/// Host e não id porque o id é chave de cofre e nome de arquivo
/// (`myrient_erista_me_files`), e chave é para máquina. Uma url sem host, que
/// `Addon.idFromUrl` aceita, cai no id, que é feio e é melhor que vazio.
String _nomeDe(String url, String id) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return id;
  return host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
}

/// A rede de verdade, igual à de `CatalogService.setCatalogFromUrl`
/// (o corpo de `setCatalogFromUrl`): mesmo teto de 30 segundos para conectar e
/// mesma recusa de qualquer status que não seja 200.
Future<String> fetchCatalogByHttp(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} fetching catalog');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}
