import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toolpdf_view/l10n/app_localizations.dart';
import 'package:toolpdf_view/src/app.dart';
import 'package:toolpdf_view/src/screens/about_screen.dart';
import 'package:toolpdf_view/src/screens/home_screen.dart';
import 'package:toolpdf_view/src/services/library.dart';
import 'package:toolpdf_view/src/services/storage.dart';
import 'package:toolpdf_view/src/services/storage_access.dart';
import 'package:toolpdf_view/src/widgets/error_view.dart';

const _documents = MethodChannel('com.toolodfview.app/documents');

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: ToolPdfViewApp.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void _mockAndroid({
  required bool Function() granted,
  bool settingsPage = true,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_documents, (call) async {
        return switch (call.method) {
          'hasStorageAccess' => granted(),
          'storageNeedsSettingsPage' => settingsPage,
          'requestStorageAccess' => granted(),
          _ => null,
        };
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await library.load();
    storageAccess.debugSet(granted: true);
    Storage.debugRoots = const [];
  });

  tearDown(() {
    Storage.debugRoots = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_documents, null);
  });

  group('home', () {
    testWidgets('shows the three navigation destinations', (tester) async {
      await tester.pumpWidget(
        _wrap(const HomeScreen(askForStorageAccess: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favourites'), findsWidgets);
      expect(find.text('Recents'), findsWidgets);
      expect(find.text('Folders'), findsWidgets);
    });

    testWidgets('navigation labels are translated', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HomeScreen(askForStorageAccess: false),
          locale: const Locale('pt'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favoritos'), findsWidgets);
      expect(find.text('Pastas'), findsWidgets);
    });

    testWidgets('starts on the folders until something was opened', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const HomeScreen(askForStorageAccess: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('All PDFs on this device'), findsOneWidget);

      await library.remember(const PdfEntry(path: '/tmp/a.pdf', name: 'a.pdf'));
      await tester.pumpWidget(
        _wrap(HomeScreen(key: UniqueKey(), askForStorageAccess: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('a.pdf'), findsOneWidget);
    });
  });

  group('storage access', () {
    testWidgets('asks on the first launch only', (tester) async {
      var granted = false;
      _mockAndroid(granted: () => granted);
      await storageAccess.init();

      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Allow access to your PDFs'), findsOneWidget);

      granted = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Allow access').last);
      await tester.pumpAndSettle();
      expect(storageAccess.isGranted, isTrue);
      expect(library.storagePromptSeen, isTrue);

      await tester.pumpWidget(_wrap(HomeScreen(key: UniqueKey())));
      await tester.pumpAndSettle();
      expect(find.text('Allow access to your PDFs'), findsNothing);
    });

    testWidgets('never asks when the app was opened with a PDF', (
      tester,
    ) async {
      _mockAndroid(granted: () => false);
      await storageAccess.init();

      await tester.pumpWidget(
        _wrap(const HomeScreen(askForStorageAccess: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allow access to your PDFs'), findsNothing);
      expect(library.storagePromptSeen, isFalse);
    });

    test('believes Android, not what happens to be listable', () async {
      // The original bug: on Android 11+ the storage root can be listed
      // without any permission, which the app mistook for having access.
      _mockAndroid(granted: () => false);
      await storageAccess.init();
      expect(storageAccess.isGranted, isFalse);
      expect(storageAccess.needsSettingsPage, isTrue);
    });

    test(
      'notices access granted while the app was in the background',
      () async {
        var granted = false;
        _mockAndroid(granted: () => granted);
        await storageAccess.init();
        expect(storageAccess.isGranted, isFalse);

        granted = true;
        storageAccess.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(storageAccess.isGranted, isTrue);
      },
    );
  });

  group('the PDF engine widgets', () {
    // pdfrx draws its menus with the `material_ui` package, which looks up
    // its own MaterialLocalizations. When that lookup found nothing - on any
    // phone not set to English - the menu failed to build and release builds
    // showed a grey box over the whole document.
    for (final language in ['en', 'pt', 'es', 'fr', 'ru']) {
      testWidgets('find their localizations in "$language"', (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
            locale: Locale(language),
          ),
        );

        expect(
          Localizations.of<mui.MaterialLocalizations>(
            context,
            mui.MaterialLocalizations,
          ),
          isNotNull,
        );
      });

      testWidgets('build a selection menu in "$language"', (tester) async {
        await tester.pumpWidget(
          _wrap(
            Scaffold(
              body: mui.AdaptiveTextSelectionToolbar.buttonItems(
                anchors: const mui.TextSelectionToolbarAnchors(
                  primaryAnchor: Offset(200, 200),
                ),
                buttonItems: [
                  ContextMenuButtonItem(onPressed: () {}, label: 'Copy'),
                ],
              ),
            ),
            locale: Locale(language),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Copy'), findsOneWidget);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }
  });

  group('failures', () {
    testWidgets('a widget that cannot build becomes a message, not a wall', (
      tester,
    ) async {
      // The framework checks that a test leaves this exactly as it found it.
      final previousBuilder = ErrorWidget.builder;
      ErrorWidget.builder = (details) => const FriendlyErrorBox();

      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Column(
              children: [
                const Text('still here'),
                Expanded(child: Builder(builder: (_) => throw StateError('x'))),
              ],
            ),
          ),
        ),
      );
      ErrorWidget.builder = previousBuilder;
      expect(tester.takeException(), isStateError);

      expect(find.byType(FriendlyErrorBox), findsOneWidget);
      expect(find.text('Something went wrong here'), findsOneWidget);
      expect(find.text('still here'), findsOneWidget);
    });
  });

  group('about', () {
    testWidgets('credits the developer and the site', (tester) async {
      await tester.pumpWidget(_wrap(const AboutScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Edivaldo Jorge'), findsOneWidget);
      expect(find.text('github.com/jorgeedvaldo'), findsOneWidget);
      expect(find.text('toolpdf.org'), findsOneWidget);
    });
  });

  group('library', () {
    test('favourites and recents survive a reload', () async {
      const entry = PdfEntry(path: '/tmp/a.pdf', name: 'a.pdf');
      await library.remember(entry);
      await library.toggleFavorite(entry);

      final reloaded = Library();
      await reloaded.load();
      expect(reloaded.recents.single.path, '/tmp/a.pdf');
      expect(reloaded.isFavorite('/tmp/a.pdf'), isTrue);
    });

    test('a damaged list does not stop the app from starting', () async {
      SharedPreferences.setMockInitialValues({
        'recents': '[{"path": 42}]',
        'favorites': 'not json at all',
      });
      final damaged = Library();
      await damaged.load();
      expect(damaged.recents, isEmpty);
      expect(damaged.favorites, isEmpty);
    });
  });

  group('storage', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('toolpdf_test');
      Directory('${root.path}/Download/sub').createSync(recursive: true);
      Directory('${root.path}/Android/data/app').createSync(recursive: true);
      Directory('${root.path}/Android/media/chat').createSync(recursive: true);
      Directory('${root.path}/.hidden').createSync();
      File('${root.path}/Download/a.pdf').writeAsStringSync('12345');
      File('${root.path}/Download/sub/B.PDF').writeAsStringSync('1');
      File('${root.path}/Download/notes.txt').writeAsStringSync('1');
      File('${root.path}/Android/data/app/private.pdf').writeAsStringSync('1');
      File('${root.path}/Android/media/chat/shared.pdf').writeAsStringSync('1');
      File('${root.path}/.hidden/secret.pdf').writeAsStringSync('1');
      Storage.debugRoots = [root];
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('finds every PDF it is allowed to see, and only PDFs', () async {
      final found = await Storage.findAll();
      expect(found.map((pdf) => pdf.name).toSet(), {
        'a.pdf',
        'B.PDF',
        'shared.pdf',
      });
      expect(found.firstWhere((pdf) => pdf.name == 'a.pdf').size, 5);
    });

    test('lists folders first and skips other files', () async {
      final listing = await Storage.list(Directory('${root.path}/Download'));
      expect(listing.folders.single.path, endsWith('/sub'));
      expect(listing.files.single.path, endsWith('/a.pdf'));
    });

    test('an unreadable file has no size instead of throwing', () {
      expect(Storage.sizeOf('${root.path}/nope.pdf'), isNull);
      expect(Storage.sizeOf('${root.path}/Download/a.pdf'), 5);
    });

    test('formats sizes for people', () {
      expect(Storage.formatSize(512), '512 B');
      expect(Storage.formatSize(1536), '1.5 KB');
      expect(Storage.formatSize(40566317), '39 MB');
    });
  });
}
