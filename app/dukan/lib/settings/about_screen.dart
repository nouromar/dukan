// Settings → About. Shows the installed app version + build so a shopkeeper
// can read it back to support ("Dukan 1.0.0 (17)"). Reads the REAL installed
// package info at runtime via package_info_plus, so it always matches what's
// on the phone regardless of how the build was made.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.aboutTitle),
      body: SafeArea(
        child: FutureBuilder<PackageInfo>(
          future: _info,
          builder: (context, snapshot) {
            final info = snapshot.data;
            final appName = (info?.appName.isNotEmpty ?? false)
                ? info!.appName
                : 'Dukan';
            final version = info == null
                ? '—'
                : '${info.version} (${info.buildNumber})';
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    appName,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l.aboutVersionLabel),
                  trailing: Text(
                    version,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
