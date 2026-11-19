import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends CatalogService {
  _FakeCatalog(this.consoles);
  final Map<String, Console> consoles;
  @override
  Future<Map<String, Console>> getConsoles([String consolesFilePath = 'consoles.json']) async => consoles;
}

const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], gameFilesFormat: ['.sfc']);
const _ps4 = Console(id: 'ps4', name: 'PlayStation 4', urls: [], platform: 'ps4', originalFormat: ['.pkg']);

Future<FpkgiServerNotifier> _notifier(Map<String, Console> consoles) async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer(overrides: [fpkgiServerProvider.overrideWith((ref) => FpkgiServerNotifier(ref, catalog: _FakeCatalog(consoles)))]);
  addTearDown(c.dispose);
  final n = c.read(fpkgiServerProvider.notifier);
  await n.setPort(0); // any free port
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enable refuses to start without a PS4 system in the catalog', () async {
    final n = await _notifier(const {'snes': _snes});
    await n.enable();
    addTearDown(n.disable);
    expect(n.state.running, isFalse);
    expect(n.state.error, contains('no PS4 system'));
  });

  test('enable starts with a PS4 system in the catalog', () async {
    final n = await _notifier(const {'snes': _snes, 'ps4': _ps4});
    await n.enable();
    addTearDown(n.disable);
    expect(n.state.running, isTrue);
    expect(n.state.error, isNull);
  });
}
