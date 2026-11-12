import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../services/documents_channel.dart';
import '../services/library.dart';
import '../services/storage.dart';
import '../services/storage_access.dart';
import '../widgets/document_tile.dart';
import 'all_pdfs_screen.dart';
import 'home_screen.dart';
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

  Future<void> _pickWithSystemPicker() async {
    try {
      final entry = await DocumentsChannel.pickDocument();
      if (entry != null && mounted) ViewerScreen.open(context, entry);
    } on MissingPluginException {
      // Nothing to pick with outside Android.
    } on PlatformException {
      // The picker could not be opened; nothing to show.
    }
  }

  void _enter(Directory directory) => setState(() => _directory = directory);

  void _goUp() {
    final current = _directory;
    if (current == null) return;
    final isRoot = Storage.isRoot(current);
    setState(() => _directory = isRoot ? null : current.parent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: storageAccess,
      builder: (context, _) {
        if (!storageAccess.isKnown) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!storageAccess.isGranted) {
          return EmptyView(
            icon: Icons.folder_off_outlined,
            title: l10n.storageAccessTitle,
            body: l10n.storageAccessBody,
            action: Column(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: Text(l10n.grantAccess),
                  onPressed: () => requestStorageAccess(context),
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
                  // A new folder is a new list: start it scrolled to the top.
                  key: ValueKey(directory.path),
                  directory: directory,
                  onOpenFolder: _enter,
                  onUp: _goUp,
                ),
        );
      },
    );
  }
}

/// Every PDF on the device, the usual folders, and the storage roots.
class _RootList extends StatefulWidget {
  const _RootList({required this.onOpen});

  final void Function(Directory directory) onOpen;

  @override
  State<_RootList> createState() => _RootListState();
}

class _RootListState extends State<_RootList> {
  late final Future<(List<Directory>, List<Directory>)> _folders = _load();

  static Future<(List<Directory>, List<Directory>)> _load() async =>
      (await Storage.roots(), await Storage.shortcuts());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<(List<Directory>, List<Directory>)>(
      future: _folders,
      builder: (context, snapshot) {
        final (roots, shortcuts) =
            snapshot.data ?? (const <Directory>[], const <Directory>[]);
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card.filled(
                color: theme.colorScheme.primaryContainer,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(
                    Icons.picture_as_pdf,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  title: Text(l10n.allPdfs),
                  subtitle: Text(l10n.allPdfsBody),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(AllPdfsScreen.route()),
                ),
              ),
            ),
            if (shortcuts.isNotEmpty) _SectionHeader(l10n.shortcuts),
            for (final folder in shortcuts)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(folder.path.split('/').last),
                onTap: () => widget.onOpen(folder),
              ),
            if (roots.isNotEmpty) _SectionHeader(l10n.storageRoots),
            for (final root in roots)
              ListTile(
                leading: Icon(
                  Storage.isPrimary(root)
                      ? Icons.smartphone
                      : Icons.sd_card_outlined,
                ),
                title: Text(
                  Storage.isPrimary(root)
                      ? l10n.internalStorage
                      : root.path.split('/').last,
                ),
                onTap: () => widget.onOpen(root),
              ),
          ],
        );
      },
    );
  }
}

class _FolderList extends StatefulWidget {
  const _FolderList({
    required this.directory,
    required this.onOpenFolder,
    required this.onUp,
    super.key,
  });

  final Directory directory;
  final void Function(Directory directory) onOpenFolder;
  final VoidCallback onUp;

  @override
  State<_FolderList> createState() => _FolderListState();
}

class _FolderListState extends State<_FolderList> {
  late final Future<({List<Directory> folders, List<File> files})> _contents =
      Storage.list(widget.directory);

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
              Storage.isPrimary(widget.directory)
                  ? l10n.internalStorage
                  : widget.directory.path.replaceFirst(
                      '/storage/emulated/0/',
                      '',
                    ),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
            onTap: widget.onUp,
          ),
        ),
        Expanded(
          child: FutureBuilder<({List<Directory> folders, List<File> files})>(
            future: _contents,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyView(
                  icon: Icons.folder_off_outlined,
                  title: l10n.folderEmpty,
                  body: '',
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
                      onTap: () => widget.onOpenFolder(folder),
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
