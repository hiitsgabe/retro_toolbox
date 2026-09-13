import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// How the catalog arrives from the network.
typedef CatalogFetcher = Future<String> Function(String url);

/// Fetches the catalog at [url], stores any tokens it carries, and installs
/// the source as an addon.
///
/// Harvest runs before validating and before writing: nothing touches disk
/// until [CatalogService.harvestAuthTokens] returned the token-free JSON.
///
/// Throws [FormatException] when the body has no console, and whatever [fetch]
/// throws on network failure.
Future<Addon> installAddonFromUrl(
  String url, {
  required AddonNotifier notifier,
  required SecretVault vault,
  CatalogFetcher? fetch,
}) async {
  final body = await (fetch ?? fetchCatalogByHttp)(url);
  final id = Addon.idFromUrl(url);

  final cleaned = await CatalogService.harvestAuthTokens(body, vault: vault, addonId: id);
  if (CatalogService.parseConsoles(cleaned).isEmpty) {
    throw const FormatException('No consoles found in the provided catalog.');
  }

  final addon = Addon(id: id, name: _nameOf(url, id), url: url);
  await notifier.install(addon, cleaned);
  return addon;
}

/// The name shown in the addon list: the host, without `www.`.
String _nameOf(String url, String id) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return id;
  return host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
}

/// The production network fetch: 30 second connect timeout, refuses any
/// status other than 200.
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
