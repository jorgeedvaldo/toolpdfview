import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/app_localizations.dart';
import '../services/library.dart';
import '../widgets/error_view.dart';

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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.fileMissing)));
      return;
    }
    Navigator.of(context).push(route(entry));
  }

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

enum _CopyScope { page, document }

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  int _page = 1;
  int _pageCount = 0;
  int _passwordAttempts = 0;
  bool _openFailureReported = false;

  void _say(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Opening -------------------------------------------------------------

  void _onReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted) return;
    setState(() => _pageCount = document.pages.length);
    // Only documents that really opened belong in the recents list.
    library.remember(widget.entry);
  }

  /// Asks for the password of a protected PDF; null gives up on the file.
  Future<String?> _askPassword() async {
    if (!mounted) return null;
    final wrong = _passwordAttempts++ > 0;
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(wrongPassword: wrong),
    );
    if (password == null && mounted) {
      // Nothing to show without the password: leave the viewer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    return password;
  }

  // --- Copying -------------------------------------------------------------

  /// Copies the current selection and removes the highlight.
  Future<void> _copySelection(PdfTextSelectionDelegate selection) async {
    final l10n = AppLocalizations.of(context);
    try {
      final copied = await selection.copyTextSelection();
      _say(copied ? l10n.textCopied : l10n.copyNotAllowed);
    } on Object catch (error, stack) {
      reportError(error, stack, 'copying the selected text');
      await selection.clearTextSelection();
    }
  }

  /// Copies the text of the current page or of the whole document straight
  /// to the clipboard, without selecting (and highlighting) anything.
  Future<void> _copyText(_CopyScope scope) async {
    final l10n = AppLocalizations.of(context);
    if (!_controller.isReady) return;
    final document = _controller.document;
    if (document.permissions?.allowsCopying == false) {
      _say(l10n.copyNotAllowed);
      return;
    }

    final pages = scope == _CopyScope.page
        ? [document.pages[(_page - 1).clamp(0, document.pages.length - 1)]]
        : document.pages;
    final progress = ValueNotifier<int>(0);
    var cancelled = false;
    var dialogOpen = false;

    // A whole newspaper takes a few seconds: say so, and allow backing out.
    if (pages.length > 1) {
      dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _CopyProgressDialog(progress: progress, total: pages.length),
        ).then((_) {
          dialogOpen = false;
          cancelled = true;
        }),
      );
    }

    final text = StringBuffer();
    try {
      for (final page in pages) {
        if (cancelled || !mounted) break;
        final pageText = await page.loadStructuredText(ensureLoaded: true);
        final content = pageText.fullText.trim();
        if (content.isNotEmpty) {
          if (text.isNotEmpty) text.write('\n\n');
          text.write(content);
        }
        progress.value++;
      }
    } on Object catch (error, stack) {
      reportError(error, stack, 'reading the text of the document');
    }

    final finished = !cancelled;
    if (dialogOpen && mounted) Navigator.of(context).pop();
    progress.dispose();
    if (!finished || !mounted) return;

    if (text.isEmpty) {
      _say(l10n.noTextInDocument);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text.toString()));
    _say(
      scope == _CopyScope.page ? l10n.pageTextCopied : l10n.documentTextCopied,
    );
  }

  /// The menu shown over a text selection: Copy and Select all.
  ///
  /// Built with the app's own Material widgets, so it follows the app theme
  /// and language and does not depend on what the PDF engine brings along.
  Widget? _buildSelectionMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (!params.isTextSelectionEnabled) return null;
    final selection = params.textSelectionDelegate;
    final items = <ContextMenuButtonItem>[
      if (selection.isCopyAllowed && selection.hasSelectedText)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => _copySelection(selection),
        ),
      if (!selection.isSelectingAllText)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: selection.selectAllText,
        ),
    ];
    if (items.isEmpty) return null;
    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        buttonItems: items,
      ),
    );
  }

  // --- Moving around -------------------------------------------------------

  /// Double tap zooms into the tapped spot, and back out again.
  bool _onTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.doubleTap) return false;
    final base = controller.coverScale;
    final zoomedIn = controller.currentZoom > base * 1.3;
    controller.setZoom(details.documentPosition, zoomedIn ? base : base * 2.5);
    return true;
  }

  Future<void> _goToPage() async {
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(current: _page, total: _pageCount),
    );
    if (page != null && _controller.isReady) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
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
                  color: isFavorite ? scheme.primary : null,
                  tooltip: isFavorite
                      ? l10n.removeFromFavorites
                      : l10n.addToFavorites,
                  onPressed: () => library.toggleFavorite(widget.entry),
                );
              },
            ),
            PopupMenuButton<_CopyScope>(
              icon: const Icon(Icons.content_copy),
              tooltip: l10n.copyText,
              enabled: _pageCount > 0,
              onSelected: _copyText,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _CopyScope.page,
                  child: Text(l10n.copyPageText),
                ),
                PopupMenuItem(
                  value: _CopyScope.document,
                  child: Text(l10n.copyDocumentText),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            // A light tint over the selected words, never a grey wash.
            DefaultSelectionStyle(
              selectionColor: scheme.primary.withValues(alpha: 0.28),
              cursorColor: scheme.primary,
              child: PdfViewer.file(
                widget.entry.path,
                controller: _controller,
                passwordProvider: _askPassword,
                params: PdfViewerParams(
                  margin: 6,
                  backgroundColor: scheme.surfaceContainer,
                  // Two-finger pinch zoom, up to 10x.
                  sizeDelegateProvider:
                      const PdfViewerSizeDelegateProviderLegacy(maxScale: 10),
                  // Long-press a word to select it, drag the handles, Copy.
                  textSelectionParams: const PdfTextSelectionParams(
                    enabled: true,
                  ),
                  buildContextMenu: _buildSelectionMenu,
                  onGeneralTap: _onTap,
                  onPageChanged: (page) {
                    if (page != null && mounted) setState(() => _page = page);
                  },
                  onViewerReady: _onReady,
                  loadingBannerBuilder: (context, downloaded, total) =>
                      const Center(child: CircularProgressIndicator()),
                  errorBannerBuilder: (context, error, stackTrace, ref) {
                    if (!_openFailureReported) {
                      _openFailureReported = true;
                      reportError(error, stackTrace, 'opening a PDF');
                    }
                    return _OpenFailed(message: l10n.couldNotOpen);
                  },
                ),
              ),
            ),
            if (_pageCount > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: _PagePill(
                    label: l10n.pageIndicator(_page, _pageCount),
                    tooltip: l10n.goToPage,
                    onTap: _goToPage,
                  ),
                ),
              ),
            if (_pageCount > 0)
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
      ),
    );
  }
}

/// Shown instead of the pages when a PDF cannot be opened.
class _OpenFailed extends StatelessWidget {
  const _OpenFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.inverseSurface.withValues(alpha: 0.82),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(color: scheme.onInverseSurface),
            ),
          ),
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
      heroTag: null,
      tooltip: tooltip,
      elevation: 1,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

class _CopyProgressDialog extends StatelessWidget {
  const _CopyProgressDialog({required this.progress, required this.total});

  final ValueNotifier<int> progress;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (context, done, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.copyingText),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: total == 0 ? null : done / total),
            const SizedBox(height: 8),
            Text(l10n.pageIndicator(done, total)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.wrongPassword});

  final bool wrongPassword;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: Text(l10n.passwordTitle),
      content: TextField(
        controller: _field,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          labelText: l10n.passwordHint,
          errorText: widget.wrongPassword ? l10n.passwordWrong : null,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: Text(l10n.open),
        ),
      ],
    );
  }
}

class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final _field = TextEditingController(text: '${widget.current}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final page = int.tryParse(_field.text.trim());
    Navigator.of(context).pop(page?.clamp(1, widget.total));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.goToPage),
      content: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(suffixText: '/ ${widget.total}'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.go)),
      ],
    );
  }
}
