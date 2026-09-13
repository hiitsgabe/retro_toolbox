import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/services/prefs_vault.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

/// Which vault the app could open, and whether it encrypts. The two fields
/// travel together because a `SecretVault` alone cannot tell whether the
/// accounts screen must warn about plaintext.
class VaultChoice {
  final SecretVault vault;

  /// `false` means plaintext: in practice, Linux with no `gnome-keyring` or
  /// KWallet on D-Bus.
  final bool encryptedAtRest;

  const VaultChoice(this.vault, {required this.encryptedAtRest});
}

/// Tries the system keyring; falls back to [buildFallback] if it does not
/// respond. [buildFallback] is a function so `shared_preferences` is not
/// opened on every boot of a device that has a keyring.
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
