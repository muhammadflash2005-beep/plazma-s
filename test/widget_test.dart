import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/main.dart';

void main() {
  testWidgets('home screen exposes unified room creation and joining actions', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('plazma'), findsOneWidget);
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
    expect(find.text('Create room'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
  });

  testWidgets('Join action opens the unified transfer room screen', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('Join room'));
    await tester.tap(find.text('Join room'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Share files'), findsOneWidget);
    expect(find.text('Enter connection code'), findsOneWidget);
    expect(find.text('Add files'), findsOneWidget);
    expect(find.text('Start sharing'), findsOneWidget);
  });

  testWidgets('settings exposes all nine Plazma themes', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Settings').last);
    await tester.pump(const Duration(seconds: 1));

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
