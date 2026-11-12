import 'dart:io';

import 'package:flutter/foundation.dart';

/// A PDF found on the device.
@immutable
class FoundPdf {
  const FoundPdf({
    required this.path,
    required this.size,
    required this.modified,
  });

  final String path;
  final int size;
  final DateTime modified;

  String get name => path.split('/').last;
}

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
    '$_primary/Telegram/Telegram Documents',
    '$_primary/Bluetooth',
    '$_primary/Books',
  ];

  /// Replaces the storage roots; lets tests browse a temporary folder.
  @visibleForTesting
  static List<Directory>? debugRoots;

  /// Storage roots: internal storage first, then any removable card.
  static Future<List<Directory>> roots() async {
    final override = debugRoots;
    if (override != null) return override;

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

  /// True when [directory] is the phone's internal storage.
  static bool isPrimary(Directory directory) => directory.path == _primary;

  /// True when [directory] is a storage root, with nothing to go up to.
  static bool isRoot(Directory directory) {
    final override = debugRoots;
    if (override != null) {
      return override.any((root) => root.path == directory.path);
    }
    final parent = directory.parent.path;
    return isPrimary(directory) ||
        parent == '/storage' ||
        parent == directory.path;
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
      } else if (entity is File && _isPdf(name)) {
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

  /// Every PDF in shared storage, newest first.
  ///
  /// The walk runs on a background isolate so a phone with tens of thousands
  /// of files never stutters while it is being searched.
  static Future<List<FoundPdf>> findAll() async {
    final rootPaths = [for (final root in await roots()) root.path];
    final rows = await compute(_scan, rootPaths);
    return [
      for (final row in rows)
        FoundPdf(
          path: row.$1,
          size: row.$2,
          modified: DateTime.fromMillisecondsSinceEpoch(row.$3),
        ),
    ];
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

  /// Size of the file at [path], or null when it cannot be read.
  static int? sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }
}

bool _isPdf(String name) => name.toLowerCase().endsWith('.pdf');

/// Walks [rootPaths] and returns `(path, size, modifiedMillis)` for each PDF.
List<(String, int, int)> _scan(List<String> rootPaths) {
  final found = <(String, int, int)>[];
  final pending = [for (final path in rootPaths) Directory(path)];

  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      continue; // unreadable folder, e.g. another app's private data
    }
    for (final entity in children) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        // Android/data and Android/obb belong to other apps and are sealed;
        // Android/media is where WhatsApp and Telegram keep documents.
        if (directory.path.endsWith('/Android') &&
            (name == 'data' || name == 'obb')) {
          continue;
        }
        pending.add(entity);
      } else if (entity is File && _isPdf(name)) {
        try {
          final stat = entity.statSync();
          found.add((
            entity.path,
            stat.size,
            stat.modified.millisecondsSinceEpoch,
          ));
        } on FileSystemException {
          // Vanished while we were looking.
        }
      }
    }
  }

  found.sort((a, b) => b.$3.compareTo(a.$3));
  return found;
}
