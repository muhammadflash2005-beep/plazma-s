import 'package:flutter/material.dart';
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

  testWidgets('Join room opens the unified transfer screen', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Transfer').last);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Create room'), findsWidgets);
    expect(find.text('Join room'), findsWidgets);

    // The chooser is taller than the test viewport; bring its action button
    // into view before tapping it, just as a user would scroll on a phone.
    final joinRoomButton = find.widgetWithText(OutlinedButton, 'Join room');
    await tester.ensureVisible(joinRoomButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(joinRoomButton);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Share files'), findsOneWidget);
    expect(find.text('Enter connection code'), findsOneWidget);
    expect(find.text('Add files'), findsOneWidget);
    expect(find.text('Start sharing'), findsOneWidget);
  });

  testWidgets('Me tab exposes all nine Plazma themes', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Me').last);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Plazma Light'), findsOneWidget);
    expect(find.text('Plazma Dark'), findsOneWidget);
    expect(find.text('Ocean'), findsOneWidget);
    expect(find.text('Sunset'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('Purple'), findsOneWidget);
    expect(find.text('Crimson'), findsOneWidget);
    expect(find.text('Midnight'), findsOneWidget);
    expect(find.text('Obsidian'), findsOneWidget);
  });
}
