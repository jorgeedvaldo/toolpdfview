import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;

import '../l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/viewer_screen.dart';
import 'services/documents_channel.dart';
import 'services/library.dart';
import 'theme.dart';

/// App version, kept in step with the `version:` field of pubspec.yaml.
const String kAppVersion = '1.0.1';

class ToolPdfViewApp extends StatefulWidget {
  const ToolPdfViewApp({this.initialDocument, super.key});

  /// The PDF the app was started with, when another app asked to open one.
  final PdfEntry? initialDocument;

  /// Delegates every screen of the app needs, in every supported language.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    ...AppLocalizations.localizationsDelegates,
    PdfEngineLocalizations.delegate,
  ];

  @override
  State<ToolPdfViewApp> createState() => _ToolPdfViewAppState();
}

class _ToolPdfViewAppState extends State<ToolPdfViewApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    DocumentsChannel.onDocument(_open);
    final initial = widget.initialDocument;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(initial));
    }
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
      localizationsDelegates: ToolPdfViewApp.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Someone who tapped a PDF wants to read it, not answer a question;
      // the request for storage access waits for a normal launch.
      home: HomeScreen(askForStorageAccess: widget.initialDocument == null),
    );
  }
}

/// Gives the PDF engine's own widgets the localizations they look up.
///
/// pdfrx builds its menus and messages with the standalone `material_ui`
/// package, whose `MaterialLocalizations` is a different class from Flutter's
/// and whose built-in fallback only answers for English. On a phone set to
/// any other language that lookup came back empty and the widget failed to
/// build - which in a release build is a grey box over the whole document.
/// This delegate answers for every language, so the lookup can never fail.
class PdfEngineLocalizations
    extends LocalizationsDelegate<mui.MaterialLocalizations> {
  const PdfEngineLocalizations();

  static const PdfEngineLocalizations delegate = PdfEngineLocalizations();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<mui.MaterialLocalizations> load(Locale locale) =>
      mui.DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(PdfEngineLocalizations old) => false;
}
