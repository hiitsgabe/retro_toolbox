import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the file browsers (File Explorer, SMB, FTP) show entries.
enum BrowserLayout { grid, list }

const _key = 'file_browser_layout';

/// The user's choice, shared by every file browser and remembered; null until
/// they pick one, which means automatic (list on short screens, grid otherwise).
final browserLayoutProvider = StateNotifierProvider<BrowserLayoutNotifier, BrowserLayout?>((ref) => BrowserLayoutNotifier());

class BrowserLayoutNotifier extends StateNotifier<BrowserLayout?> {
  BrowserLayoutNotifier() : super(null) {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (mounted && saved != null) state = BrowserLayout.values.asNameMap()[saved];
    });
  }

  Future<void> set(BrowserLayout layout) async {
    state = layout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, layout.name);
  }
}
