import 'package:flutter/services.dart';

import 'library.dart';

/// Bridge to the Android side: PDFs that other apps open or share with
/// ToolPDF View, plus the system document picker.
class DocumentsChannel {
  DocumentsChannel._();

  static const _channel = MethodChannel('com.toolodfview.app/documents');

  /// The document ToolPDF View was launched with, if it was launched by
  /// tapping a PDF somewhere else. Consumed once.
  static Future<PdfEntry?> initialDocument() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'takeInitialDocument',
    );
    return _entryFrom(result);
  }

  /// Whether the app may list the PDFs in shared storage.
  static Future<bool> hasStorageAccess() async =>
      await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;

  /// Asks for the storage permission this Android version needs and returns
  /// what the user decided.
  static Future<bool> requestStorageAccess() async =>
      await _channel.invokeMethod<bool>('requestStorageAccess') ?? false;

  /// Opens the system document picker and returns the chosen PDF, or null
  /// when the user backs out. Needs no storage permission.
  static Future<PdfEntry?> pickDocument() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'pickDocument',
    );
    return _entryFrom(result);
  }

  /// Fires when a PDF is opened while the app is already running.
  static void onDocument(void Function(PdfEntry entry) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openDocument') return null;
      final entry = _entryFrom(
        (call.arguments as Map?)?.cast<String, String>(),
      );
      if (entry != null) handler(entry);
      return null;
    });
  }

  static PdfEntry? _entryFrom(Map<String, String>? data) {
    final path = data?['path'];
    if (path == null || path.isEmpty) return null;
    return PdfEntry(path: path, name: data?['name'] ?? path.split('/').last);
  }
}
