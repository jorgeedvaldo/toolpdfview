import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../services/documents_channel.dart';
import '../services/library.dart';
import '../services/storage_access.dart';
import '../widgets/document_tile.dart';
import 'about_screen.dart';
import 'browse_tab.dart';
import 'viewer_screen.dart';

/// The three tabs of the app: favourites, recents and the folder browser.
class HomeScreen extends StatefulWidget {
  const HomeScreen({this.askForStorageAccess = true, super.key});

  /// Whether to ask for storage access on the very first launch.
  final bool askForStorageAccess;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recentsTab = 1;
  static const _foldersTab = 2;

  // With nothing opened yet, the folders are where the user's PDFs are.
  late int _tab = library.recents.isEmpty ? _foldersTab : _recentsTab;

  @override
  void initState() {
    super.initState();
    if (widget.askForStorageAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunPrompt());
    }
  }

  /// Asks for storage access once, the first time the app is opened.
  ///
  /// The answer itself is remembered by Android; the app only remembers that
  /// it asked, so it never nags.
  Future<void> _firstRunPrompt() async {
    if (!mounted || storageAccess.isGranted || library.storagePromptSeen) {
      return;
    }
    final allow = await showStorageAccessDialog(context);
    await library.markStoragePromptSeen();
    if (allow != true || !mounted) return;
    await requestStorageAccess(context);
    if (mounted && storageAccess.isGranted) {
      setState(() => _tab = _foldersTab);
    }
  }

  Future<void> _pickFile() async {
    try {
      final entry = await DocumentsChannel.pickDocument();
      if (entry != null && mounted) ViewerScreen.open(context, entry);
    } on MissingPluginException {
      // Nothing to pick with outside Android.
    } on PlatformException {
      // The picker could not be opened; nothing to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.navFavorites, l10n.navRecents, l10n.navBrowse];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == _recentsTab)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.clearRecents,
              onPressed: _confirmClearRecents,
            ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: l10n.openFile,
            onPressed: _pickFile,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.about,
            onPressed: () => Navigator.of(context).push(AboutScreen.route()),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [_FavoritesTab(), _RecentsTab(), BrowseTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.star_border),
            selectedIcon: const Icon(Icons.star),
            label: l10n.navFavorites,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.navRecents,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: l10n.navBrowse,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearRecents() async {
    final l10n = AppLocalizations.of(context);
    if (library.recents.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearRecents),
        content: Text(l10n.clearRecentsQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await library.clearRecents();
  }
}

/// Explains why the app wants storage access; true means "go ahead".
Future<bool?> showStorageAccessDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.folder_open, size: 40),
      title: Text(l10n.firstRunTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.firstRunBody),
          if (storageAccess.needsSettingsPage) ...[
            const SizedBox(height: 12),
            Text(
              l10n.firstRunSettingsHint,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.notNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.grantAccess),
        ),
      ],
    ),
  );
}

/// Sends the user to Android's permission prompt and reports how it went.
Future<void> requestStorageAccess(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final granted = await storageAccess.request();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(granted ? l10n.accessGranted : l10n.accessDenied)),
    );
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        if (library.favorites.isEmpty) {
          return EmptyView(
            icon: Icons.star_border,
            title: l10n.favoritesEmptyTitle,
            body: l10n.favoritesEmptyBody,
          );
        }
        return _DocumentList(
          entries: library.favorites,
          removeLabel: l10n.removeFromFavorites,
          onRemove: (entry) => library.removeFavorite(entry.path),
        );
      },
    );
  }
}

class _RecentsTab extends StatelessWidget {
  const _RecentsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        if (library.recents.isEmpty) {
          return EmptyView(
            icon: Icons.history,
            title: l10n.recentsEmptyTitle,
            body: l10n.recentsEmptyBody,
          );
        }
        return _DocumentList(
          entries: library.recents,
          removeLabel: l10n.remove,
          onRemove: (entry) => library.removeRecent(entry.path),
        );
      },
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({
    required this.entries,
    required this.onRemove,
    required this.removeLabel,
  });

  final List<PdfEntry> entries;
  final void Function(PdfEntry entry) onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return DocumentTile(
          entry: entry,
          removeLabel: removeLabel,
          onRemove: () => onRemove(entry),
          onTap: () => ViewerScreen.open(context, entry),
        );
      },
    );
  }
}
