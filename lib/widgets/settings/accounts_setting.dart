import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/ia_credentials_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// Connected accounts, one accordion per provider. Collapsed once connected so
/// it stays out of the way; opens when the user still needs to log in.
///
/// A visão consolidada da seção 9 do spec de UI: as contas que não são de
/// addon (hoje, o Internet Archive) e uma por par (addon, console) que pede
/// credencial. A mesma credencial é editável aqui e no detalhe do addon, e
/// isso é custo aceito e não descuido.
class AccountsSetting extends ConsumerWidget {
  const AccountsSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(settingsProvider).hasIaCredentials;
    final contas = ref.watch(addonAccountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
          // Rebuild so the status subtitle updates after login/logout.
          key: ValueKey('ia_$loggedIn'),
          initiallyExpanded: false,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          // account_balance is the columned-building glyph — matches the IA logo.
          leading: const Icon(Icons.account_balance),
          title: const Text('Internet Archive'),
          subtitle: Text(loggedIn ? 'Connected' : 'Not connected'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: const [IaCredentialsSetting()],
        ),
        // Carga e erro não desenham nada: esta é uma seção dentro da tela de
        // settings, e uma barra de progresso piscando aqui a cada abertura
        // custa mais do que a espera de um quadro.
        ...contas.maybeWhen(
          data: (lista) => [for (final conta in lista) _ContaDeAddon(conta: conta)],
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

/// Uma conta de addon, com o estado de conexão no subtítulo.
///
/// Tem estado porque o token vem do cofre, que é assíncrono, e porque o
/// formulário de dentro pode gravar enquanto esta linha está montada.
class _ContaDeAddon extends ConsumerStatefulWidget {
  final AddonAccount conta;

  const _ContaDeAddon({required this.conta});

  @override
  ConsumerState<_ContaDeAddon> createState() => _ContaDeAddonState();
}

class _ContaDeAddonState extends ConsumerState<_ContaDeAddon> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(
          widget.conta.addon.id,
          widget.conta.console.id,
        );
    if (!mounted) return;
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.conta.console;
    // Enquanto o cofre não respondeu, o subtítulo é só o nome do console. Não
    // é "Not connected": dizer que não tem conta para quem tem, durante um
    // quadro, é a única das três respostas que é mentira.
    final estado = _token == null ? console.name : '${console.name}: ${_token!.isEmpty ? 'Not connected' : 'Connected'}';

    return ExpansionTile(
      initiallyExpanded: false,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text(widget.conta.addon.name),
      subtitle: Text(estado),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        ConsoleAuthSetting(
          console: console,
          addonId: widget.conta.addon.id,
          onSaved: (token) {
            if (mounted) setState(() => _token = token);
          },
        ),
      ],
    );
  }
}
