import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:retro_toolbox/services/permission_service.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

class PermissionsSetting extends StatefulWidget {
  const PermissionsSetting({super.key});

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

  Widget _buildPermissionTile(Permission permission, PermissionStatus status) {
    final description = PermissionService.permissionDescriptions[permission] ?? permission.toString();
    final rationale = PermissionService.permissionRationales[permission];
    if (status.isGranted) {
      return SettingsValueRow(title: description, subtitle: rationale, value: 'Granted', onTap: null);
    }
    return SettingsActionRow(
      title: description,
      subtitle: rationale,
      action: status.isPermanentlyDenied ? 'Settings' : 'Request',
      onPressed: _loading ? null : () => _requestPermission(permission),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    if (_loading && _permissionStatuses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final e in _permissionStatuses.entries) _buildPermissionTile(e.key, e.value)],
    );
  }
}
