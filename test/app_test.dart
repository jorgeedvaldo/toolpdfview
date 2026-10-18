import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toolpdf_view/l10n/app_localizations.dart';
import 'package:toolpdf_view/src/screens/about_screen.dart';
import 'package:toolpdf_view/src/screens/home_screen.dart';
import 'package:toolpdf_view/src/services/library.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await library.load();
  });

  testWidgets('home shows the three navigation destinations', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    // Not pumpAndSettle: the folder tab spins while it probes storage.
    await tester.pump();

    expect(find.text('Favourites'), findsWidgets);
    expect(find.text('Recents'), findsWidgets);
    expect(find.text('Folders'), findsWidgets);
  });

  testWidgets('navigation labels are translated', (tester) async {
    await tester.pumpWidget(
      _wrap(const HomeScreen(), locale: const Locale('pt')),
    );
    await tester.pump();

    expect(find.text('Favoritos'), findsWidgets);
    expect(find.text('Pastas'), findsWidgets);
  });

  testWidgets('about screen credits the developer and the site', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Edivaldo Jorge'), findsOneWidget);
    expect(find.text('github.com/jorgeedvaldo'), findsOneWidget);
    expect(find.text('toolpdf.org'), findsOneWidget);
  });

  test('favourites and recents survive a reload', () async {
    const entry = PdfEntry(path: '/tmp/a.pdf', name: 'a.pdf');
    await library.remember(entry);
    await library.toggleFavorite(entry);

    final reloaded = Library();
    await reloaded.load();
    expect(reloaded.recents.single.path, '/tmp/a.pdf');
    expect(reloaded.isFavorite('/tmp/a.pdf'), isTrue);
  });
}
