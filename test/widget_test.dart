import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/main.dart';

void main() {
  testWidgets('home screen shows Plazma S room actions', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pumpAndSettle();

    expect(find.text('plazma'), findsOneWidget);
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
  });

  testWidgets('creating a room starts the live room flow', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create room'));
    await tester.tap(find.text('Create room'));
    // The live room startup is asynchronous and the progress indicator is
    // intentionally animated, so pumpAndSettle would wait forever here.
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('settings exposes all five Plazma themes', (tester) async {
    await tester.pumpWidget(const PlazmaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Plazma Light'), findsOneWidget);
    expect(find.text('Plazma Dark'), findsOneWidget);
    expect(find.text('Ocean'), findsOneWidget);
    expect(find.text('Sunset'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
  });
}
