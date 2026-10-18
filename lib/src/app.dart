import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/viewer_screen.dart';
import 'services/documents_channel.dart';
import 'services/library.dart';
import 'theme.dart';

/// App version, kept in step with the `version:` field of pubspec.yaml.
const String kAppVersion = '1.0.0';

class ToolPdfViewApp extends StatefulWidget {
  const ToolPdfViewApp({super.key});

  @override
  State<ToolPdfViewApp> createState() => _ToolPdfViewAppState();
}

class _ToolPdfViewAppState extends State<ToolPdfViewApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    DocumentsChannel.onDocument(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final entry = await DocumentsChannel.initialDocument();
        if (entry != null) _open(entry);
      } on MissingPluginException {
        // Running on a platform without the Android bridge.
      }
    });
  }

  /// Shows a PDF handed over by another app.
  void _open(PdfEntry entry) {
    _navigatorKey.currentState?.push(ViewerScreen.route(entry));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
