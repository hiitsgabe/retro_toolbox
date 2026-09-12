import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

/// Um `AddonStore` inteiro em memória, para os testes de widget.
///
/// Existe porque IO de disco **trava** dentro de um corpo `testWidgets`: o
/// corpo roda num `FakeAsync` e a resposta do sistema de arquivos chega pelo
/// laço de eventos real, que não avança ali. Quem exercita disco de verdade é
/// `addon_store_test`, em `test()` comum, e é lá que isso tem que ser provado.
///
/// `noSuchMethod` com `implements` evita reescrever `catalogFile`, o único
/// membro que sobra, e o `throw` é o que diferencia este duplo de um mock
/// permissivo: se um caso futuro chamar o que não existe aqui, ele morre
/// dizendo qual método foi, em vez de passar em silêncio.
class FakeAddonStore implements AddonStore {
  List<Addon> _addons;

  /// O que `writeCatalog` gravou, por addon. Público para um caso poder afirmar
  /// que a instalação escreveu o catálogo, e não só que mexeu na lista.
  final Map<String, String> catalogos = {};

  FakeAddonStore(List<Addon> addons) : _addons = List.of(addons);

  @override
  List<Addon> load() => List.of(_addons);

  @override
  Future<void> save(List<Addon> lista) async {
    _addons = List.of(lista);
  }

  @override
  Future<String?> readCatalog(String addonId) async => catalogos[addonId];

  @override
  Future<void> writeCatalog(String addonId, String jsonStr) async {
    catalogos[addonId] = jsonStr;
  }

  @override
  Future<void> deleteCatalog(String addonId) async {
    catalogos.remove(addonId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'FakeAddonStore não responde ${invocation.memberName}.',
      );
}
