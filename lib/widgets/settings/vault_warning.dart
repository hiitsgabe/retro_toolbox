import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/vault_provider.dart';

/// Avisa, onde o segredo é digitado, que este aparelho não tem chaveiro.
///
/// É a segunda metade da seção 6.3 do spec de arquitetura, e a metade que
/// **não** é incondicional. Tirar o token do JSON compartilhável fecha em toda
/// plataforma (`CatalogService.harvestAuthTokens`); cifrar em repouso depende
/// de haver `gnome-keyring` ou KWallet no D-Bus, e num Linux de servidor não
/// há. Nessa máquina o segredo continua em texto puro, e quem digita tem que
/// saber disso na hora de digitar.
///
/// Carregando não avisa: enquanto a sondagem não voltou, o app não sabe se
/// cifra, e um aviso que pisca em todo boot de máquina que tem chaveiro é um
/// aviso que o usuário aprende a ignorar. Erro avisa, e avisa pior que o caso
/// normal, porque aí não há cofre nenhum.
///
/// **O ramo de erro não é o chaveiro falhando.** Chaveiro que não abre é o
/// caminho previsto: a sonda engole a exceção, devolve `false` e a escolha cai
/// para a reserva, o que chega aqui como `data` com `encryptedAtRest: false`. O
/// único jeito de o `error` acontecer é a **reserva** levantar, ou seja
/// `PrefsVault.open()` (`vault_provider.dart:33`, fora de qualquer `try`). Por
/// isso a mensagem fala em cofre e não em chaveiro: culpar o chaveiro aqui
/// mandaria o usuário procurar o problema no lugar errado.
class VaultWarning extends ConsumerWidget {
  const VaultWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texto = ref.watch(vaultProvider).when(
          loading: () => null,
          error: (e, _) => 'Não deu para abrir cofre nenhum, nem o do sistema nem a reserva: $e',
          data: (escolha) => escolha.encryptedAtRest ? null : 'As credenciais ficam em texto puro neste aparelho.',
        );
    if (texto == null) return const SizedBox.shrink();

    final cores = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cores.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_open, size: 20, color: cores.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: TextStyle(color: cores.onErrorContainer)),
                const SizedBox(height: 4),
                Text(
                  'Sem gnome-keyring nem KWallet, o app guarda o segredo como antes. O catálogo que você compartilha continua sem token.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cores.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
