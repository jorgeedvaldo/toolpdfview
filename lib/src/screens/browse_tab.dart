import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../services/documents_channel.dart';
import '../services/library.dart';
import '../services/storage.dart';
import '../widgets/document_tile.dart';
import 'viewer_screen.dart';

/// Browses the folders of the device looking for PDFs.
class BrowseTab extends StatefulWidget {
  const BrowseTab({super.key});

  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab> {
  /// Folder currently shown; null means the list of roots and shortcuts.
  Directory? _directory;
  bool _hasAccess = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final granted = await Storage.canRead();
    if (!mounted) return;
    setState(() {
      _hasAccess = granted;
      _checking = false;
    });
  }

  Future<void> _requestAccess() async {
    setState(() => _checking = true);
    final granted = await Storage.requestAccess();
    if (!mounted) return;
    setState(() {
      _hasAccess = granted;
      _checking = false;
    });
  }

  Future<void> _pickWithSystemPicker() async {
    try {
      final entry = await DocumentsChannel.pickDocument();
      if (entry != null && mounted) ViewerScreen.open(context, entry);
    } on MissingPluginException {
      // Nothing to pick with outside Android.
    }
  }

  void _enter(Directory directory) => setState(() => _directory = directory);

  void _goUp() {
    final current = _directory;
    if (current == null) return;
    final parent = current.parent;
    final isRoot =
        current.path == '/storage/emulated/0' ||
        parent.path == '/storage' ||
        parent.path == current.path;
    setState(() => _directory = isRoot ? null : parent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasAccess) {
      return EmptyView(
        icon: Icons.folder_off_outlined,
        title: l10n.storageAccessTitle,
        body: l10n.storageAccessBody,
        action: Column(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.lock_open),
              label: Text(l10n.grantAccess),
              onPressed: _requestAccess,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l10n.chooseFile),
              onPressed: _pickWithSystemPicker,
            ),
          ],
        ),
      );
    }

    final directory = _directory;
    return PopScope(
      canPop: directory == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: directory == null
          ? _RootList(onOpen: _enter)
          : _FolderList(
              directory: directory,
              onOpenFolder: _enter,
              onUp: _goUp,
            ),
    );
  }
}

/// Storage roots plus the handful of folders where PDFs usually land.
class _RootList extends StatelessWidget {
  const _RootList({required this.onOpen});

  final void Function(Directory directory) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<(List<Directory>, List<Directory>)>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (roots, shortcuts) = data;
        return ListView(
          children: [
            if (shortcuts.isNotEmpty) _SectionHeader(l10n.shortcuts),
            for (final folder in shortcuts)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(folder.path.split('/').last),
                onTap: () => onOpen(folder),
              ),
            _SectionHeader(l10n.storageRoots),
            for (final root in roots)
              ListTile(
                leading: Icon(
                  root.path == '/storage/emulated/0'
                      ? Icons.smartphone
                      : Icons.sd_card_outlined,
                ),
                title: Text(
                  root.path == '/storage/emulated/0'
                      ? l10n.internalStorage
                      : root.path.split('/').last,
                ),
                onTap: () => onOpen(root),
              ),
          ],
        );
      },
    );
  }

  Future<(List<Directory>, List<Directory>)> _load() async =>
      (await Storage.roots(), await Storage.shortcuts());
}

class _FolderList extends StatelessWidget {
  const _FolderList({
    required this.directory,
    required this.onOpenFolder,
    required this.onUp,
  });

  final Directory directory;
  final void Function(Directory directory) onOpenFolder;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: ListTile(
            leading: const Icon(Icons.arrow_upward),
            title: Text(
              directory.path.replaceFirst('/storage/emulated/0', ''),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
            onTap: onUp,
          ),
        ),
        Expanded(
          child: FutureBuilder<({List<Directory> folders, List<File> files})>(
            future: Storage.list(directory),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyView(
                  icon: Icons.folder_off_outlined,
                  title: l10n.storageAccessTitle,
                  body: l10n.storageAccessBody,
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (data.folders.isEmpty && data.files.isEmpty) {
                return EmptyView(
                  icon: Icons.folder_open_outlined,
                  title: l10n.folderEmpty,
                  body: '',
                );
              }
              return ListView.builder(
                itemCount: data.folders.length + data.files.length,
                itemBuilder: (context, index) {
                  if (index < data.folders.length) {
                    final folder = data.folders[index];
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(folder.path.split('/').last),
                      onTap: () => onOpenFolder(folder),
                    );
                  }
                  final file = data.files[index - data.folders.length];
                  final entry = PdfEntry.fromPath(file.path);
                  return DocumentTile(
                    entry: entry,
                    onTap: () => ViewerScreen.open(context, entry),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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
