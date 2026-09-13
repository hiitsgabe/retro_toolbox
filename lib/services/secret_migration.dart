import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Moves the four secrets out of the `app_settings` JSON and into the vault.
///
/// Works on the raw map, before `AppSettings.fromJson`, because the model
/// drops unknown fields silently. Returns the cleaned map instead of saving;
/// the caller saves.
///
/// No "already ran" flag: after the first pass the fields are gone, so a second
/// pass is a no-op on its own.
class SecretMigration {
  final SecretVault vault;

  /// The addon that owns today's catalog consoles.
  final String builtinAddonId;

  const SecretMigration({required this.vault, required this.builtinAddonId});

  Future<Map<String, dynamic>> drain(Map<String, dynamic> raw) async {
    final cleaned = Map<String, dynamic>.from(raw);

    await _move(cleaned, 'iaAccessKey', SecretRef.iaAccessKey);
    await _move(cleaned, 'iaSecretKey', SecretRef.iaSecretKey);
    await _move(cleaned, 'iaCookies', SecretRef.iaCookies);

    final consoles = cleaned['consoleSettings'];
    if (consoles is Map) {
      final result = <String, dynamic>{};
      for (final entry in consoles.entries) {
        final id = entry.key.toString();
        final value = entry.value;
        if (value is! Map) {
          result[id] = value;
          continue;
        }
        // Own copy, not the caller's nested map: `Map.from` above is shallow.
        final console = Map<String, dynamic>.from(value);
        await _move(console, 'authToken', SecretRef.addonToken(builtinAddonId, id));
        result[id] = console;
      }
      cleaned['consoleSettings'] = result;
    }

    return cleaned;
  }

  /// Removes [field] from [from] always, and writes to the vault only when there
  /// is something to write and the vault has no value yet.
  Future<void> _move(Map<String, dynamic> from, String field, String ref) async {
    final value = from.remove(field);
    if (value is! String || value.isEmpty) return;
    if (await vault.read(ref) != null) return;
    await vault.write(ref, value);
  }
}
