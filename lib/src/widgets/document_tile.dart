import 'package:flutter/material.dart';

import '../services/library.dart';
import '../services/storage.dart';
import 'pdf_mark.dart';

/// One PDF in a list: mark, file name, and where it lives.
class DocumentTile extends StatelessWidget {
  const DocumentTile({
    required this.entry,
    required this.onTap,
    this.onRemove,
    this.removeLabel,
    this.size,
    super.key,
  });

  final PdfEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final String? removeLabel;

  /// File size when the caller already knows it; read from disk otherwise.
  final int? size;

  @override
  Widget build(BuildContext context) {
    // A file the app can no longer read is treated exactly like a missing
    // one: shown dimmed, never allowed to break the list.
    final size = this.size ?? Storage.sizeOf(entry.path);
    final exists = size != null;
    final theme = Theme.of(context);
    final details = <String>[
      if (size != null) Storage.formatSize(size),
      _folderOf(entry.path),
    ];

    return ListTile(
      leading: Opacity(
        opacity: exists ? 1 : 0.4,
        child: const PdfMark(size: 40),
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: exists ? null : theme.disabledColor),
      ),
      subtitle: Text(
        details.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onRemove == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: removeLabel,
              onPressed: onRemove,
            ),
      onTap: onTap,
    );
  }

  static String _folderOf(String path) {
    final folder = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : path;
    return folder.replaceFirst('/storage/emulated/0', '');
  }
}

/// Friendly placeholder for an empty list.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
