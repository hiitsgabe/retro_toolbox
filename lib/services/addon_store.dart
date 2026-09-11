import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Onde a lista de addons e os catálogos de cada um moram.
///
/// A raiz de disco entra por construtor porque `getApplicationSupportDirectory`
/// é `path_provider`, que num teste sem plataforma lança
/// `MissingPluginException`. Com ela injetada, o teste usa
/// `Directory.systemTemp.createTemp()` e exercita IO de verdade.
class AddonStore {
  /// A chave do `shared_preferences` onde a lista ordenada é serializada.
  static const String prefsKey = 'addons';

  final SharedPreferences _prefs;
  final Directory _root;

  AddonStore(this._prefs, this._root);

  static Future<AddonStore> open() async => AddonStore(
        await SharedPreferences.getInstance(),
        await getApplicationSupportDirectory(),
      );

  /// A lista instalada, na ordem de prioridade.
  ///
  /// Quando a chave não existe, devolve a lista de migração (o embutido
  /// sozinho) **sem gravar nada**. Gravar aqui faria uma leitura ter efeito
  /// colateral, e o teste "ler NÃO grava" existe para prender isso: quem
  /// persiste é a primeira instalação, remoção ou arrasto.
  ///
  /// Lista vazia salva é estado legítimo, e diferente de chave ausente: o
  /// usuário que removeu todos os addons não pode ver o embutido voltar
  /// sozinho no próximo boot.
  List<Addon> load() {
    final cru = _prefs.getString(prefsKey);
    if (cru == null) return [_builtinMigrado()];
    try {
      final decoded = jsonDecode(cru);
      if (decoded is! List) return [_builtinMigrado()];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> && item['id'] is String) Addon.fromJson(item),
      ];
    } catch (e) {
      debugPrint('Lista de addons ilegível, caindo na migração: $e');
      return [_builtinMigrado()];
    }
  }

  Future<void> save(List<Addon> lista) async {
    await _prefs.setString(prefsKey, jsonEncode([for (final addon in lista) addon.toJson()]));
  }

  /// O addon que representa o `consoles.json` de antes da fatia 4.
  ///
  /// A url sai do `catalogSourceUrl` que o usuário já tinha salvo, quando ele
  /// instalou o catálogo por endereço. É só nome de tela: `app_settings`
  /// ilegível ou campo ausente dão um addon sem url, e o app funciona igual.
  Addon _builtinMigrado() {
    String? url;
    try {
      final cru = _prefs.getString(SettingsService.settingsKey);
      if (cru != null) {
        final decoded = jsonDecode(cru);
        final valor = decoded is Map ? decoded['catalogSourceUrl'] : null;
        if (valor is String && valor.isNotEmpty) url = valor;
      }
    } catch (e) {
      debugPrint('catalogSourceUrl ilegível na migração de addons: $e');
    }
    return Addon(id: kBuiltinAddonId, name: 'Catálogo embutido', url: url);
  }

  /// Onde mora o catálogo de cada addon.
  ///
  /// O embutido continua em `config/consoles.json`, que é exatamente onde
  /// `CatalogService.setCatalogFromJson`, `addConsole` e `resetCatalog` já
  /// escrevem (`catalog_service.dart:104-107`). É por isso que a migração não
  /// move byte nenhum de disco: ela só escreve uma lista no
  /// `shared_preferences`, e migração que não mexe em arquivo não tem como
  /// perder o catálogo do usuário.
  File catalogFile(String addonId) => addonId == kBuiltinAddonId
      ? File(path.join(_root.path, 'config', 'consoles.json'))
      : File(path.join(_root.path, 'config', 'addons', '$addonId.json'));

  Future<String?> readCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeCatalog(String addonId, String jsonStr) async {
    final file = catalogFile(addonId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> deleteCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (await file.exists()) await file.delete();
  }
}
