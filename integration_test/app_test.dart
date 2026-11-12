// End-to-end tests against the real rendering engine and the real PDFium.
//
// They run the app on a desktop build (see the workflow), with the platform
// switched to Android so that every touch-only code path - long-press
// selection, selection handles, the mobile selection menu - is exercised
// exactly as on a phone.
//
//   xvfb-run -a flutter test integration_test -d linux
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toolpdf_view/l10n/app_localizations.dart';
import 'package:toolpdf_view/src/app.dart';
import 'package:toolpdf_view/src/screens/all_pdfs_screen.dart';
import 'package:toolpdf_view/src/screens/home_screen.dart';
import 'package:toolpdf_view/src/screens/viewer_screen.dart';
import 'package:toolpdf_view/src/services/library.dart';
import 'package:toolpdf_view/src/services/storage.dart';
import 'package:toolpdf_view/src/services/storage_access.dart';
import 'package:toolpdf_view/src/theme.dart';
import 'package:toolpdf_view/src/widgets/error_view.dart';

const _assetsFromEnvironment = String.fromEnvironment('TEST_ASSETS');
const _shotDir = String.fromEnvironment('SHOT_DIR');

final _assets = _assetsFromEnvironment.isNotEmpty
    ? _assetsFromEnvironment
    : '${Directory.current.path}/integration_test/assets';

const _documents = MethodChannel('com.toolodfview.app/documents');
final _root = GlobalKey();

/// What the app last put on the clipboard.
String? _clipboard;

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _root,
      child: MaterialApp(
        // A fresh app for every test: nothing carries over between them.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: ToolPdfViewApp.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

/// Lets real time pass, so PDFium can render on its background isolate.
Future<void> _wait(WidgetTester tester, [double seconds = 2]) async {
  final frames = (seconds * 5).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Waits until [finder] matches, failing with [reason] after [seconds].
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  double seconds = 15,
  String? reason,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(reason ?? 'Timed out waiting for $finder');
}

/// Saves what is on screen as a PNG when a SHOT_DIR is given.
Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotDir.isEmpty) return;
  final boundary =
      _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File('$_shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// No part of the screen may have been replaced by an error placeholder.
void _expectNothingBroke(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(find.byType(FriendlyErrorBox), findsNothing);
}

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

PdfEntry _pdf(String name) => PdfEntry.fromPath('$_assets/$name');

Future<void> _openViewer(
  WidgetTester tester,
  String file, {
  Locale locale = const Locale('en'),
}) async {
  await _pumpApp(tester, ViewerScreen(entry: _pdf(file)), locale: locale);
}

Future<void> _waitForPages(WidgetTester tester) async {
  await _waitFor(
    tester,
    find.textContaining(' / 12'),
    reason: 'The document never finished loading',
  );
  await _wait(tester, 1.5);
}

/// A point on the third line of text of the first page.
Offset _onText(WidgetTester tester) {
  final viewer = tester.getRect(find.byType(PdfViewer));
  return Offset(
    viewer.left + viewer.width * 0.39,
    viewer.top + viewer.height * 0.663,
  );
}

/// A test that behaves like a phone: touch selection, selection handles and
/// the mobile selection menu, exactly the code paths Android users run.
void _phoneTest(String description, WidgetTesterCallback body) {
  testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              _clipboard = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': _clipboard};
            default:
              return null;
          }
        });
  });

  setUp(() async {
    _clipboard = null;
    SharedPreferences.setMockInitialValues({});
    await library.load();
    storageAccess.debugSet(granted: true);
    Storage.debugRoots = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_documents, null);
  });

  group('reading', () {
    _phoneTest('a PDF opens and shows its pages', (tester) async {
      await _openViewer(tester, 'sample.pdf');
      await _waitForPages(tester);

      expect(find.text('1 / 12'), findsOneWidget);
      expect(library.recents.single.name, 'sample.pdf');
      _expectNothingBroke(tester);
      await _shot(tester, 'viewer_opened');
    });

    _phoneTest('zoom buttons and double tap change the zoom', (tester) async {
      await _openViewer(tester, 'sample.pdf');
      await _waitForPages(tester);
      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      final initial = controller.currentZoom;

      await tester.tap(find.byIcon(Icons.add));
      await _wait(tester, 1);
      final zoomedIn = controller.currentZoom;
      expect(zoomedIn, greaterThan(initial));

      await tester.tap(find.byIcon(Icons.remove));
      await _wait(tester, 1);
      expect(controller.currentZoom, lessThan(zoomedIn));

      final spot = _onText(tester);
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(spot);
      await _wait(tester, 1);
      expect(controller.currentZoom, greaterThan(controller.coverScale * 1.3));
      _expectNothingBroke(tester);
      await _shot(tester, 'viewer_zoomed');
    });

    _phoneTest('the page indicator jumps to a page', (tester) async {
      await _openViewer(tester, 'sample.pdf');
      await _waitForPages(tester);

      await tester.tap(find.text('1 / 12'));
      await _wait(tester, 0.6);
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text(_l10n(tester).go));
      await _wait(tester, 1.5);

      expect(find.text('7 / 12'), findsOneWidget);
      _expectNothingBroke(tester);
    });

    _phoneTest('a file that is not a PDF gets an explanation', (tester) async {
      await _openViewer(tester, 'broken.pdf');
      await _waitFor(tester, find.byIcon(Icons.broken_image_outlined));

      expect(find.text(_l10n(tester).couldNotOpen), findsOneWidget);
      expect(library.recents, isEmpty);
      _expectNothingBroke(tester);
      await _shot(tester, 'viewer_broken_file');
    });

    _phoneTest('a protected PDF asks for its password', (tester) async {
      await _openViewer(tester, 'protected.pdf');
      await _waitFor(tester, find.byIcon(Icons.lock_outline));
      final l10n = _l10n(tester);
      await _shot(tester, 'viewer_password');

      await tester.enterText(find.byType(TextField), 'not the password');
      await tester.tap(find.text(l10n.open));
      await _waitFor(tester, find.text(l10n.passwordWrong));
      // Let the first dialog finish closing; the second one is now alone.
      await _wait(tester, 1);

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text(l10n.open));
      await _waitFor(tester, find.text('1 / 2'));
      _expectNothingBroke(tester);
    });
  });

  group('copying text', () {
    // The bug this guards against: on a phone set to anything but English,
    // long-pressing a word replaced the whole document with a grey box.
    for (final language in ['en', 'pt', 'es', 'fr', 'ru']) {
      _phoneTest('long-press, then Copy, in "$language"', (tester) async {
        await _openViewer(tester, 'sample.pdf', locale: Locale(language));
        await _waitForPages(tester);

        await tester.longPressAt(_onText(tester));
        await _wait(tester, 1.5);
        _expectNothingBroke(tester);

        final context = tester.element(find.byType(PdfViewer));
        final copyLabel = MaterialLocalizations.of(context).copyButtonLabel;
        await _waitFor(
          tester,
          find.text(copyLabel),
          seconds: 5,
          reason: 'The selection menu with "$copyLabel" never appeared',
        );
        await _shot(tester, 'copy_menu_$language');

        await tester.tap(find.text(copyLabel));
        await _wait(tester, 1);

        expect(_clipboard, isNotNull);
        expect(_clipboard!.trim(), isNotEmpty);
        expect(
          'Line 3 of page 1: the quick brown fox jumps over the lazy dog.',
          contains(_clipboard!.trim()),
        );
        expect(find.text(_l10n(tester).textCopied), findsOneWidget);
        _expectNothingBroke(tester);
        await _shot(tester, 'copy_done_$language');
      });
    }

    _phoneTest('Select all, then Copy, takes the whole document', (
      tester,
    ) async {
      await _openViewer(tester, 'sample.pdf', locale: const Locale('pt'));
      await _waitForPages(tester);
      final context = tester.element(find.byType(PdfViewer));
      final labels = MaterialLocalizations.of(context);

      await tester.longPressAt(_onText(tester));
      await _waitFor(tester, find.text(labels.selectAllButtonLabel));
      await tester.tap(find.text(labels.selectAllButtonLabel));
      await _wait(tester, 3);
      _expectNothingBroke(tester);
      await _shot(tester, 'select_all');

      await _waitFor(tester, find.text(labels.copyButtonLabel));
      await tester.tap(find.text(labels.copyButtonLabel));
      await _wait(tester, 2);

      expect(_clipboard, contains('ToolPDF View page 1'));
      expect(_clipboard, contains('ToolPDF View page 12'));
      _expectNothingBroke(tester);
    });

    _phoneTest('the toolbar copies the text of the current page', (
      tester,
    ) async {
      await _openViewer(tester, 'sample.pdf', locale: const Locale('pt'));
      await _waitForPages(tester);
      final l10n = _l10n(tester);

      await tester.tap(find.byIcon(Icons.content_copy));
      await _wait(tester, 0.6);
      await _shot(tester, 'copy_toolbar_menu');
      await tester.tap(find.text(l10n.copyPageText));
      await _wait(tester, 1.5);

      expect(_clipboard, contains('Line 1 of page 1'));
      expect(_clipboard, isNot(contains('page 2')));
      expect(find.text(l10n.pageTextCopied), findsOneWidget);
      // Nothing was selected, so nothing is left highlighted.
      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      expect(controller.textSelectionDelegate.hasSelectedText, isFalse);
      _expectNothingBroke(tester);
    });

    _phoneTest('the toolbar copies the text of the whole document', (
      tester,
    ) async {
      await _openViewer(tester, 'sample.pdf', locale: const Locale('pt'));
      await _waitForPages(tester);
      final l10n = _l10n(tester);

      await tester.tap(find.byIcon(Icons.content_copy));
      await _wait(tester, 0.6);
      await tester.tap(find.text(l10n.copyDocumentText));
      await _waitFor(tester, find.text(l10n.documentTextCopied));

      for (var page = 1; page <= 12; page++) {
        expect(_clipboard, contains('Line 25 of page $page:'));
      }
      _expectNothingBroke(tester);
    });
  });

  group('finding PDFs', () {
    late Directory storage;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('toolpdf_storage');
      Directory('${storage.path}/Download').createSync();
      Directory(
        '${storage.path}/Android/data/secret',
      ).createSync(recursive: true);
      File(
        '$_assets/sample.pdf',
      ).copySync('${storage.path}/Download/Jornal de hoje.pdf');
      File('$_assets/sample.pdf').copySync('${storage.path}/Contrato.pdf');
      File(
        '$_assets/sample.pdf',
      ).copySync('${storage.path}/Android/data/secret/Hidden.pdf');
      File('${storage.path}/Download/notes.txt').writeAsStringSync('no');
      Storage.debugRoots = [storage];
    });

    tearDown(() => storage.deleteSync(recursive: true));

    _phoneTest('folders lead to a PDF, which opens', (tester) async {
      await _pumpApp(
        tester,
        const HomeScreen(askForStorageAccess: false),
        locale: const Locale('pt'),
      );
      await _wait(tester, 1);
      final l10n = _l10n(tester);

      // Nothing opened yet, so the app starts on the folders.
      expect(find.text(l10n.allPdfs), findsOneWidget);
      await _shot(tester, 'folders_root');

      await tester.tap(find.text(storage.path.split('/').last));
      await _wait(tester, 1);
      expect(find.text('Contrato.pdf'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await _wait(tester, 1);
      expect(find.text('Jornal de hoje.pdf'), findsOneWidget);
      expect(find.text('notes.txt'), findsNothing);
      await _shot(tester, 'folders_download');

      await tester.tap(find.text('Jornal de hoje.pdf'));
      await _waitForPages(tester);
      expect(find.byType(PdfViewer), findsOneWidget);
      _expectNothingBroke(tester);
    });

    _phoneTest('"All PDFs" lists every PDF and filters by name', (
      tester,
    ) async {
      await _pumpApp(tester, const AllPdfsScreen(), locale: const Locale('pt'));
      await _waitFor(tester, find.text('Contrato.pdf'));

      expect(find.text('Jornal de hoje.pdf'), findsOneWidget);
      // Other apps' private folders are never searched.
      expect(find.text('Hidden.pdf'), findsNothing);
      await _shot(tester, 'all_pdfs');

      await tester.enterText(find.byType(TextField), 'jornal');
      await _wait(tester, 0.6);
      expect(find.text('Jornal de hoje.pdf'), findsOneWidget);
      expect(find.text('Contrato.pdf'), findsNothing);
      _expectNothingBroke(tester);
    });
  });

  group('storage access', () {
    _phoneTest('is requested on the first launch, and remembered', (
      tester,
    ) async {
      var granted = false;
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_documents, (call) async {
            switch (call.method) {
              case 'hasStorageAccess':
                return granted;
              case 'storageNeedsSettingsPage':
                return true;
              case 'requestStorageAccess':
                requests++;
                return granted = true;
              default:
                return null;
            }
          });
      await storageAccess.init();
      expect(storageAccess.isGranted, isFalse);

      await _pumpApp(tester, const HomeScreen(), locale: const Locale('pt'));
      await _wait(tester, 1);
      final l10n = _l10n(tester);

      // The request is on screen before the user has to look for anything.
      expect(find.text(l10n.firstRunTitle), findsOneWidget);
      expect(find.text(l10n.firstRunSettingsHint), findsOneWidget);
      await _shot(tester, 'first_run_request');

      await tester.tap(_inDialog(find.text(l10n.grantAccess)));
      await _wait(tester, 1.5);

      expect(requests, 1);
      expect(storageAccess.isGranted, isTrue);
      expect(library.storagePromptSeen, isTrue);
      expect(find.text(l10n.accessGranted), findsOneWidget);
      expect(find.text(l10n.allPdfs), findsOneWidget);
      _expectNothingBroke(tester);
      await _shot(tester, 'first_run_granted');

      // A second launch does not ask again.
      await _pumpApp(tester, const HomeScreen(), locale: const Locale('pt'));
      await _wait(tester, 1);
      expect(find.text(l10n.firstRunTitle), findsNothing);
    });

    _phoneTest('declined: the folders tab still offers both ways in', (
      tester,
    ) async {
      var granted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_documents, (call) async {
            switch (call.method) {
              case 'hasStorageAccess':
                return granted;
              case 'storageNeedsSettingsPage':
                return false;
              case 'requestStorageAccess':
                return false;
              default:
                return null;
            }
          });
      await storageAccess.init();

      await _pumpApp(tester, const HomeScreen(), locale: const Locale('pt'));
      await _wait(tester, 1);
      final l10n = _l10n(tester);
      await tester.tap(_inDialog(find.text(l10n.notNow)));
      await _wait(tester, 1);

      expect(find.text(l10n.storageAccessTitle), findsOneWidget);
      expect(find.text(l10n.grantAccess), findsOneWidget);
      expect(find.text(l10n.chooseFile), findsOneWidget);
      await _shot(tester, 'access_declined');

      // Granting it later, from Android's settings, is noticed on return.
      granted = true;
      storageAccess.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _wait(tester, 1);
      expect(find.text(l10n.allPdfs), findsOneWidget);
      _expectNothingBroke(tester);
    });
  });
}
