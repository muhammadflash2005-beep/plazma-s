// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/features/media/permanent_delete_confirmation.dart';

void main() {
  testWidgets('permanent delete waits five seconds and requires a final tap',
      (tester) async {
    var completed = false;
    late Future<bool> confirmation;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              confirmation = confirmPermanentDelete(
                context,
                itemDescription: 'one file',
              );
              confirmation.then((_) => completed = true);
            },
            child: const Text('Open delete warning'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open delete warning'));
    await tester.pump();
    expect(find.textContaining('Please wait 5 seconds'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(completed, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Delete permanently'), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
    expect(completed, isTrue);
  });

  testWidgets('leaving the warning cancels permanent deletion',
      (tester) async {
    late Future<bool> confirmation;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              confirmation = confirmPermanentDelete(
                context,
                itemDescription: 'one photo',
              );
            },
            child: const Text('Open delete warning'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open delete warning'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await confirmation, isFalse);
  });
}
