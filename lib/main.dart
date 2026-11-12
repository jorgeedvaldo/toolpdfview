import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/services/documents_channel.dart';
import 'src/services/library.dart';
import 'src/services/storage_access.dart';
import 'src/widgets/error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling();
  if (const bool.fromEnvironment('TOOLPDF_E2E')) {
    // The emulator test drives the app through Android's accessibility tree,
    // which Flutter only fills in while something is listening.
    SemanticsBinding.instance.ensureSemantics();
  }
  try {
    await library.load();
  } on Object catch (error, stack) {
    // Starting with empty lists beats not starting at all.
    reportError(error, stack, 'loading favourites and recents');
  }
  await storageAccess.init();
  runApp(ToolPdfViewApp(initialDocument: await _initialDocument()));
}

/// The PDF another app asked ToolPDF View to open, if that is how it started.
Future<PdfEntry?> _initialDocument() async {
  try {
    return await DocumentsChannel.initialDocument();
  } on MissingPluginException {
    return null; // not on Android
  } on PlatformException catch (error, stack) {
    reportError(error, stack, 'receiving the document to open');
    return null;
  }
}
