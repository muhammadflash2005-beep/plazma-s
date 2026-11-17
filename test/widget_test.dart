// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/main.dart';

void main() {
  testWidgets('app opens on the Apps tab with the Xender-style categories', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('plazma'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Quick access'), findsNothing);
  });

  testWidgets('Transfer tab opens the unified send and receive screen', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Transfer').last);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Share files'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Enter connection code'), findsOneWidget);
    expect(find.text('Create room'), findsNothing);
    expect(find.text('Join room'), findsNothing);
  });

  testWidgets('Settings Appearance labels all twelve theme swatches and their brightness', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance').last);
    await tester.pumpAndSettle();

    expect(find.text('Choose a theme'), findsOneWidget);

    const themeNames = [
      'Plazma Light',
      'Plazma Dark',
      'Ocean',
      'Sunset',
      'Forest',
      'Purple',
      'Crimson',
      'Midnight',
      'Obsidian',
      'Black & White',
      'Black & Gold',
      'Abyssal Amethyst',
    ];
    // Each swatch visibly identifies its palette and whether it is light or dark.
    for (final name in themeNames) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Light'), findsNWidgets(6));
    expect(find.text('Dark'), findsNWidgets(6));
  });
}
