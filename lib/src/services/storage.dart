import 'dart:io';

import 'package:flutter/services.dart';

import 'documents_channel.dart';

/// Read-only access to the PDFs stored on the device.
class Storage {
  Storage._();

  static const _primary = '/storage/emulated/0';

  /// Folders worth a shortcut, in the order they are shown. Only the ones
  /// that actually exist on this device end up in the browser.
  static const _shortcutCandidates = <String>[
    '$_primary/Download',
    '$_primary/Documents',
    '$_primary/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents',
    '$_primary/WhatsApp/Media/WhatsApp Documents',
    '$_primary/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Documents',
    '$_primary/Android/media/org.telegram.messenger/Telegram/Telegram Documents',
    '$_primary/Bluetooth',
    '$_primary/Books',
  ];

  /// True when the app can actually list the shared storage.
  static Future<bool> canRead() async {
    try {
      if (await DocumentsChannel.hasStorageAccess()) return true;
    } on MissingPluginException {
      // Not on Android; fall through to simply trying to read.
    }
    return _probe();
  }

  /// Asks for the permission that the running Android version needs.
  ///
  /// Android 10 and older are happy with the legacy read permission; from
  /// Android 11 on, documents are only reachable through "All files access".
  static Future<bool> requestAccess() async {
    if (await canRead()) return true;
    try {
      return await DocumentsChannel.requestStorageAccess() || await _probe();
    } on MissingPluginException {
      return _probe();
    }
  }

  /// Last resort: see whether the primary storage can simply be listed.
  static Future<bool> _probe() async {
    try {
      await Directory(_primary).list().first;
      return true;
    } on StateError {
      return true; // readable, simply empty
    } on FileSystemException {
      return false;
    }
  }

  /// Storage roots: internal storage first, then any removable card.
  static Future<List<Directory>> roots() async {
    final roots = <Directory>[];
    final primary = Directory(_primary);
    if (primary.existsSync()) roots.add(primary);
    try {
      for (final entity in Directory('/storage').listSync()) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        if (name == 'emulated' || name == 'self') continue;
        roots.add(entity);
      }
    } on FileSystemException {
      // No access to /storage; the primary root is enough.
    }
    return roots;
  }

  static Future<List<Directory>> shortcuts() async => [
    for (final path in _shortcutCandidates)
      if (Directory(path).existsSync()) Directory(path),
  ];

  /// Sub-folders and PDFs of [directory], folders first, both A→Z.
  static Future<({List<Directory> folders, List<File> files})> list(
    Directory directory,
  ) async {
    final folders = <Directory>[];
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        folders.add(entity);
      } else if (entity is File && name.toLowerCase().endsWith('.pdf')) {
        files.add(entity);
      }
    }
    int byName(FileSystemEntity a, FileSystemEntity b) => a.path
        .split('/')
        .last
        .toLowerCase()
        .compareTo(b.path.split('/').last.toLowerCase());
    folders.sort(byName);
    files.sort(byName);
    return (folders: folders, files: files);
  }

  /// Human readable file size, e.g. `1.4 MB`.
  static String formatSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final rounded = size >= 10 || unit == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$rounded ${units[unit]}';
  }
}
