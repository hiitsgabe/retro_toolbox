import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// Os cinco blocos que a seção 9 do spec de UI pede para um addon:
/// identificação, conta, cobertura, prioridade e remover.
///
/// A cobertura mostra quais consoles o addon atende, e **não** quantos itens
/// em cada. A contagem por console é uma requisição de listagem por console
/// (`CatalogService._fetchCatalog`), e o app carrega listagem sob demanda
/// justamente porque ela é cara: um addon com 25 consoles pagaria 25
/// requisições ao abrir uma tela de leitura.
class AddonDetailScreen extends ConsumerWidget {
  final String addonId;

  const AddonDetailScreen({super.key, required this.addonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final indice = addons.indexWhere((a) => a.id == addonId);

    // A remoção muda a lista antes de o `pop` completar, então este quadro
    // existe de verdade. Sem a guarda, o `addons[indice]` abaixo estoura com
    // índice -1 no caminho feliz do botão Remover.
    if (indice < 0) return const Scaffold(body: SizedBox.shrink());

    final addon = addons[indice];
    final catalogo = ref.watch(mergedCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(addon.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Secao(
            titulo: 'Origem',
            child: Text(addon.url ?? (addon.isBuiltin ? 'Instalado com o app' : 'Instalado de arquivo')),
          ),
          catalogo.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => _Secao(titulo: 'Cobertura', child: Text('Catálogo ilegível: $e')),
            data: (fundido) {
              final cobertura = fundido.coverage()[addonId] ?? (consoles: const <String>[], authConsoles: const <String>[]);
              // Declaração e não `final nome = (String id) => ...`: o
              // `prefer_function_declarations_over_variables` vem ligado no
              // `flutter_lints` e a variável empurraria o analyze para 23.
              String nome(String id) => fundido.consoles[id]?.name ?? id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cobertura.authConsoles.isNotEmpty) const VaultWarning(),
                  for (final consoleId in cobertura.authConsoles)
                    if (fundido.consoles[consoleId] != null)
                      _Secao(
                        titulo: 'Conta: ${nome(consoleId)}',
                        child: ConsoleAuthSetting(console: fundido.consoles[consoleId]!, addonId: addonId),
                      ),
                  _Secao(
                    titulo: 'Cobertura',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cobertura.consoles.isEmpty
                            ? 'Nenhum console'
                            : '${cobertura.consoles.length} console${cobertura.consoles.length == 1 ? '' : 's'}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final id in cobertura.consoles) Chip(label: Text(nome(id)))],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          _Secao(
            titulo: 'Prioridade',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${indice + 1}ª de ${addons.length}'),
                const SizedBox(height: 4),
                Text(
                  'Arraste na lista de addons para mudar a ordem. A primeira fonte que tem o arquivo é a que baixa.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmarRemocao(context, ref, addon),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarRemocao(BuildContext context, WidgetRef ref, Addon addon) async {
    final navigator = Navigator.of(context);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${addon.name}?'),
        // O token fica no cofre de propósito (`AddonNotifier.remove`), e dizer
        // isso aqui é o que impede o usuário de achar que vai ter que
        // redescobrir a credencial para reinstalar.
        content: const Text('O catálogo sai do app. A credencial fica guardada, e reinstalar a mesma fonte volta a encontrá-la.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remover addon')),
        ],
      ),
    );
    if (confirmou != true) return;
    await ref.read(addonProvider.notifier).remove(addon.id);
    navigator.pop();
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _Secao({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
