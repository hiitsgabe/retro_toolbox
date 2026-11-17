import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:retro_toolbox/services/permission_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

class PermissionsSetting extends StatefulWidget {
  const PermissionsSetting({super.key});

  /// Test seam: the statuses, instead of asking Android.
  @visibleForTesting
  static Map<Permission, PermissionStatus>? debugStatuses;

  /// Whether Settings lists permissions: Android, not the Linux handheld.
  static bool get shown => debugStatuses != null || (Platform.isAndroid && !Handheld.current);

  @override
  State<PermissionsSetting> createState() => _PermissionsSettingState();
}

class _PermissionsSettingState extends State<PermissionsSetting> {
  Map<Permission, PermissionStatus> _permissionStatuses = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionStatuses();
  }

  Future<void> _loadPermissionStatuses() async {
    final fixed = PermissionsSetting.debugStatuses;
    if (fixed != null) {
      _permissionStatuses = {...fixed};
      return;
    }
    if (!Platform.isAndroid) return;

    setState(() => _loading = true);

    final statuses = <Permission, PermissionStatus>{};
    for (final permission in PermissionService.requiredPermissions) {
      statuses[permission] = await permission.status;
    }

    setState(() {
      _permissionStatuses = statuses;
      _loading = false;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    setState(() => _loading = true);

    final status = await permission.request();

    setState(() {
      _permissionStatuses[permission] = status;
      _loading = false;
    });

    if (status.isPermanentlyDenied) {
      if (mounted) {
        _showSettingsDialog(permission);
      }
    }
  }

  Future<void> _showSettingsDialog(Permission permission) async {
    final description = PermissionService.permissionDescriptions[permission] ?? permission.toString();

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text('$description permission is required. Open app settings to grant it manually?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpen == true) {
      await openAppSettings();
      _loadPermissionStatuses();
    }
  }

  static final _titles = {
    Permission.manageExternalStorage: ('Storage access', 'Needed to write to the download folder'),
    Permission.notification: ('Notifications', 'Shows downloads running in the background'),
  };

  Widget _buildPermissionTile(Permission permission, PermissionStatus status) {
    final (title, subtitle) = _titles[permission] ??
        (PermissionService.permissionDescriptions[permission] ?? permission.toString(), PermissionService.permissionRationales[permission] ?? '');
    return SettingsValueRow(
      title: title,
      subtitle: subtitle,
      value: status.isGranted ? 'Granted' : 'Not granted',
      onTap: status.isGranted || _loading ? null : () => _requestPermission(permission),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionsSetting.shown) return const SizedBox.shrink();
    if (_loading && _permissionStatuses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    // Storage first: it is the one the library cannot work without.
    final order = [Permission.manageExternalStorage, Permission.notification];
    final entries = _permissionStatuses.entries.toList()..sort((a, b) => order.indexOf(a.key).compareTo(order.indexOf(b.key)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final e in entries) _buildPermissionTile(e.key, e.value)],
    );
  }
}
