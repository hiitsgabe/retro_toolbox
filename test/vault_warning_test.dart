import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

import 'support/fake_addon_store.dart';

const _aviso = 'As credenciais ficam em texto puro neste aparelho.';

/// Semeia as prefs antes de montar qualquer coisa que leia `settingsProvider`.
///
/// Função de topo e não duas linhas dentro do `_host` porque o último caso não
/// usa o `_host` e precisa disto do mesmo jeito: ele monta a
/// `AddonDetailScreen`, que monta `ConsoleAuthSetting`, que lê
/// `settingsProvider` (`console_auth_setting.dart:48`). Sem semear, aquele caso
/// só passa porque os quatro anteriores rodaram antes e deixaram o mock de pé,
/// e quebra quando alguém o roda sozinho com `--plain-name`.
void _semearPrefs() {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
}

Widget _host(Override cofre, {Widget child = const VaultWarning()}) {
  _semearPrefs();
  return ProviderScope(
    overrides: [cofre],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Override _cofre({required bool cifra}) =>
    vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: cifra));

void main() {
  testWidgets('cofre que não cifra avisa', (tester) async {
    await tester.pumpWidget(_host(_cofre(cifra: false)));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsOneWidget);
  });

  testWidgets('cofre que cifra não avisa nada', (tester) async {
    await tester.pumpWidget(_host(_cofre(cifra: true)));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsNothing);
    // Nem um espaço: o aviso ausente não pode deixar buraco no layout da tela
    // de contas, que é onde ele mais aparece.
    expect(tester.getSize(find.byType(VaultWarning)), Size.zero);
  });

  testWidgets('enquanto sonda o chaveiro, não avisa', (tester) async {
    // Um aviso que pisca em todo boot de máquina que tem chaveiro é um aviso
    // que o usuário aprende a ignorar.
    final travado = Completer<VaultChoice>();
    // Sem `const`: `MemoryVault` guarda um mapa mutável e não tem construtor
    // const. E o `complete` no teardown existe para o `Completer` pendurado
    // não deixar o teste vazando um future para sempre.
    addTearDown(() => travado.complete(VaultChoice(MemoryVault(), encryptedAtRest: true)));

    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) => travado.future)));
    await tester.pump();

    expect(find.text(_aviso), findsNothing);
  });

  testWidgets('cofre nenhum abriu avisa, e avisa pior', (tester) async {
    // O ramo de `error` **não** é o chaveiro falhando. Chaveiro que não abre é
    // o caminho previsto: a sonda engole a exceção, devolve `false`, e a
    // escolha cai para a reserva, o que chega aqui como `data` com
    // `encryptedAtRest: false`, que é o primeiro caso deste arquivo. Para o
    // `error` acontecer é preciso a **reserva** levantar, ou seja
    // `PrefsVault.open()` (`vault_provider.dart:33`, fora de qualquer `try`).
    // Por isso o que se espera fala em cofre e não em chaveiro, e por isso o
    // erro levantado aqui não é "sem D-Bus": sem D-Bus não chega neste ramo.
    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) async => throw StateError('nem a reserva abriu'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não deu para abrir cofre nenhum'), findsOneWidget);
  });

  testWidgets('o detalhe do addon avisa junto do formulário de conta', (tester) async {
    // O aviso tem que estar onde o segredo é digitado. Só em Accounts, ele não
    // alcança quem configura o token pela tela do addon, que é o caminho novo.
    _semearPrefs();
    const console = Console(id: 'switch', name: 'Switch', urls: ['https://m/switch/'], auth: {'requires_token': true});
    const fundido = MergedCatalog(
      consoles: {'switch': console},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://m/switch/', auth: {'requires_token': true})],
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _cofre(cifra: false),
        addonProvider.overrideWith((ref) => AddonNotifier(
              Future.value(FakeAddonStore(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://m/c.json')])),
              invalidarCache: () async {},
            )),
        mergedCatalogProvider.overrideWith((ref) async => fundido),
      ],
      child: const MaterialApp(home: AddonDetailScreen(addonId: 'myrient')),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsOneWidget);
  });
}
