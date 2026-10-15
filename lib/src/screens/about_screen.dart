import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../app.dart';
import '../widgets/pdf_mark.dart';

/// Who made the app, where it comes from, and what it does not do.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _github = 'https://github.com/jorgeedvaldo';
  static const _website = 'https://toolpdf.org';

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const AboutScreen());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                const PdfMark(size: 88),
                const SizedBox(height: 16),
                Text(l10n.appTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  l10n.versionLabel(kAppVersion),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    l10n.aboutBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _Section(l10n.developer),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.developerName),
            subtitle: Text(l10n.developerRole),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.github),
            subtitle: const Text('github.com/jorgeedvaldo'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(_github),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(l10n.website),
            subtitle: Text(l10n.websiteBody),
            isThreeLine: true,
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(_website),
          ),
          const Divider(height: 1),
          _Section(l10n.tipsTitle),
          ListTile(
            leading: const Icon(Icons.zoom_in),
            title: Text(l10n.tipZoom),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(l10n.tipCopy),
          ),
          const Divider(height: 1),
          _Section(l10n.noAdsTitle),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(l10n.noAdsBody),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: kAppVersion,
                applicationIcon: const Padding(
                  padding: EdgeInsets.all(8),
                  child: PdfMark(size: 48),
                ),
              ),
              child: Text(
                MaterialLocalizations.of(context).viewLicensesButtonLabel,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
