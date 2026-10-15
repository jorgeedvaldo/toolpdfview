import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/app_localizations.dart';
import '../services/library.dart';

/// Shows one PDF: pinch to zoom, long-press to select and copy text.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({required this.entry, super.key});

  final PdfEntry entry;

  static Route<void> route(PdfEntry entry) =>
      MaterialPageRoute<void>(builder: (_) => ViewerScreen(entry: entry));

  /// Opens [entry], or explains that the file is gone.
  static void open(BuildContext context, PdfEntry entry) {
    if (!File(entry.path).existsSync()) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.fileMissing)));
      return;
    }
    Navigator.of(context).push(route(entry));
  }

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    library.remember(widget.entry);
  }

  Future<void> _copyAllText() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _controller.textSelectionDelegate.selectAllText();
    final text = await _controller.textSelectionDelegate.getSelectedText();
    if (text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noTextToCopy)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.textCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ListenableBuilder(
            listenable: library,
            builder: (context, _) {
              final isFavorite = library.isFavorite(widget.entry.path);
              return IconButton(
                icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                color: isFavorite ? theme.colorScheme.primary : null,
                tooltip: isFavorite
                    ? l10n.removeFromFavorites
                    : l10n.addToFavorites,
                onPressed: () => library.toggleFavorite(widget.entry),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: l10n.selectAllText,
            onPressed: _copyAllText,
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            widget.entry.path,
            controller: _controller,
            params: PdfViewerParams(
              margin: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              // Two-finger pinch zoom, up to 10x.
              sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
                maxScale: 10,
              ),
              // Long-press to select text, then Copy from the context menu.
              textSelectionParams: const PdfTextSelectionParams(enabled: true),
              onPageChanged: (page) {
                if (page != null && mounted) setState(() => _page = page);
              },
              onViewerReady: (document, controller) {
                if (mounted) {
                  setState(() => _pageCount = document.pages.length);
                }
              },
              loadingBannerBuilder: (context, downloaded, total) =>
                  const Center(child: CircularProgressIndicator()),
              errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.couldNotOpen,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
            ),
          ),
          if (_pageCount > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: _Pill(
                  child: Text(l10n.pageIndicator(_page, _pageCount)),
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ZoomButton(
                  icon: Icons.add,
                  tooltip: l10n.zoomIn,
                  onPressed: () => _controller.zoomUp(),
                ),
                const SizedBox(height: 8),
                _ZoomButton(
                  icon: Icons.remove,
                  tooltip: l10n.zoomOut,
                  onPressed: () => _controller.zoomDown(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.colorScheme.onInverseSurface),
          child: child,
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      tooltip: tooltip,
      elevation: 1,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
