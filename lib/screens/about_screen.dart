import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:roms_downloader/widgets/about/info_card.dart';
import 'package:roms_downloader/widgets/about/expandable_info_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _packageInfo = info);
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('About', style: TextStyle(fontSize: 16)),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 40,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(height: 20),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Image.asset('assets/icon.png', fit: BoxFit.contain),
            ),
            SizedBox(height: 32),
            Text(
              _packageInfo?.appName ?? '-',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 4),
            Text(
              _packageInfo?.packageName ?? '-',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Version ${_packageInfo?.version ?? '-'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Icon(Icons.verified_user_rounded, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'Play fair',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Retro Toolbox is a utility, not a source of games. Neither the app nor its developers endorse piracy. It stands for easy access to a library you already own. Stick to trusted sources and download only titles you own.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            InfoCard(
              icon: Icons.code_rounded,
              title: 'Open Source',
              subtitle: 'This app is open source. Contributions welcome at hiitsgabe/retro_toolbox',
              url: 'https://github.com/hiitsgabe/retro_toolbox',
              onTap: () => _copyToClipboard(context, 'https://github.com/hiitsgabe/retro_toolbox'),
            ),
            SizedBox(height: 16),
            ExpandableInfoCard(
              icon: Icons.person_rounded,
              title: 'Authors',
              items: [
                InfoItem('rafaismyname', 'rafaismy.name', 'https://rafaismy.name'),
                InfoItem('hiitsgabe', 'gabeismy.name', 'https://gabeismy.name'),
              ],
              onItemTap: (url) => _copyToClipboard(context, url),
            ),
            SizedBox(height: 16),
            ExpandableInfoCard(
              icon: Icons.favorite_rounded,
              title: 'Credits',
              items: [
                InfoItem('nsz', 'NSZ decompression by nicoboss - github.com/nicoboss/nsz', 'https://github.com/nicoboss/nsz'),
                InfoItem('0x0', 'Ephemeral storage - 0x0.st', 'https://0x0.st'),
                InfoItem('EmulationStation Carbon', 'Console logos by Rookervik', 'https://github.com/RetroPie/es-theme-carbon'),
                InfoItem('Art Book Next', 'Console logos by Anthony Caccese (CC-BY-NC-SA)', 'https://github.com/anthonycaccese/es-theme-art-book-next'),
                InfoItem('Chakra Petch', 'Font by Cadson Demak (OFL)', 'https://fonts.google.com/specimen/Chakra+Petch'),
                InfoItem('flutter', 'flutter.dev', 'https://flutter.dev'),
                InfoItem('serious_python', 'pub.dev/packages/serious_python', 'https://pub.dev/packages/serious_python'),
                InfoItem('file_picker', 'pub.dev/packages/file_picker', 'https://pub.dev/packages/file_picker'),
                InfoItem('background_downloader', 'pub.dev/packages/background_downloader', 'https://pub.dev/packages/background_downloader'),
                InfoItem('flutter_riverpod', 'pub.dev/packages/flutter_riverpod', 'https://pub.dev/packages/flutter_riverpod'),
                InfoItem('shared_preferences', 'pub.dev/packages/shared_preferences', 'https://pub.dev/packages/shared_preferences'),
                InfoItem('url_launcher', 'pub.dev/packages/url_launcher', 'https://pub.dev/packages/url_launcher'),
                InfoItem('path_provider', 'pub.dev/packages/path_provider', 'https://pub.dev/packages/path_provider'),
                InfoItem('permission_handler', 'pub.dev/packages/permission_handler', 'https://pub.dev/packages/permission_handler'),
                InfoItem('archive', 'pub.dev/packages/archive', 'https://pub.dev/packages/archive'),
                InfoItem('flutter_archive', 'pub.dev/packages/flutter_archive', 'https://pub.dev/packages/flutter_archive'),
                InfoItem('flutter_foreground_task', 'pub.dev/packages/flutter_foreground_task', 'https://pub.dev/packages/flutter_foreground_task'),
                InfoItem('package_info_plus', 'pub.dev/packages/package_info_plus', 'https://pub.dev/packages/package_info_plus'),
                InfoItem('cached_network_image', 'pub.dev/packages/cached_network_image', 'https://pub.dev/packages/cached_network_image'),
                InfoItem('rapidfuzz', 'pub.dev/packages/rapidfuzz', 'https://pub.dev/packages/rapidfuzz'),
                InfoItem('photo_view', 'pub.dev/packages/photo_view', 'https://pub.dev/packages/photo_view'),
                InfoItem('disk_space_2', 'pub.dev/packages/disk_space_2', 'https://pub.dev/packages/disk_space_2'),
              ],
              onItemTap: (url) => _copyToClipboard(context, url),
            ),
            SizedBox(height: 32),
            Text(
              'Support the developers',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'This app is free and made in our spare time. If it helps you, a coffee keeps it going. ☕',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            InfoCard(
              icon: Icons.coffee_rounded,
              title: 'Buy me a coffee',
              subtitle: 'buymeacoffee.com/hiitsgabe',
              url: 'https://buymeacoffee.com/hiitsgabe',
              onTap: () => _copyToClipboard(context, 'https://buymeacoffee.com/hiitsgabe'),
            ),
            SizedBox(height: 40),
            Text(
              'Made with ❤️ in NYC 🗽 & Toronto 🇨🇦',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
