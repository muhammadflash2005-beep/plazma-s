import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/main.dart';

void main() {
  testWidgets('home screen shows Plazma S and room actions', (tester) async {
    await tester.pumpWidget(const PlazmaApp());

    expect(find.text('plazma'), findsOneWidget);
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
    expect(find.textContaining('Web preview'), findsOneWidget);
  });

  testWidgets('creating a room shows a six-character code', (tester) async {
    await tester.pumpWidget(const PlazmaApp());

    await tester.ensureVisible(find.text('Create room'));
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();

    expect(find.text('Your room'), findsOneWidget);
    expect(find.text('ROOM CODE'), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);
  });
}
