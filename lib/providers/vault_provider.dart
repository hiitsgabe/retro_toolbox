import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/services/prefs_vault.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

/// Qual cofre o app conseguiu abrir, e se ele cifra.
///
/// Os dois campos andam juntos de propósito. A tela de contas precisa avisar
/// quando o segredo está em texto puro (decisão travada), e um `SecretVault`
/// sozinho não conta essa história: `PrefsVault` e `SecureStorageVault`
/// cumprem exatamente o mesmo contrato.
class VaultChoice {
  final SecretVault vault;

  /// `false` quer dizer texto puro. Na prática, Linux sem `gnome-keyring` nem
  /// KWallet no D-Bus.
  final bool encryptedAtRest;

  const VaultChoice(this.vault, {required this.encryptedAtRest});
}

/// Tenta o chaveiro do sistema; se ele não responder, cai para [buildFallback].
///
/// [buildFallback] é função e não valor para não abrir o `shared_preferences`
/// em todo boot de aparelho que tem chaveiro, que é a maioria.
Future<VaultChoice> chooseVault({
  required SecureStorageBackend backend,
  required Future<SecretVault> Function() buildFallback,
}) async {
  if (await probeSecureStorage(backend)) {
    return VaultChoice(SecureStorageVault(backend), encryptedAtRest: true);
  }
  return VaultChoice(await buildFallback(), encryptedAtRest: false);
}

final vaultProvider = FutureProvider<VaultChoice>((ref) {
  return chooseVault(
    backend: const PluginSecureStorage(),
    buildFallback: PrefsVault.open,
  );
});
