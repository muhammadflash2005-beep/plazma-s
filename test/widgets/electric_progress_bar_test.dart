// Flutter stable 3.50 deprecates the Material umbrella library during migration.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/widgets/electric_progress_bar.dart';

void main() {
  testWidgets(
    'transfer card keeps the app icon and file details inside the plasma fill',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElectricTransferProgressCard(
                    icon: const Icon(Icons.android_rounded),
                    title: 'Amazon Kindle.apk',
                    subtitle: '69.70 MB · apps/com.amazon.kindle',
                    progress: 0.42,
                    status: 'Sending',
                    speed: const Text('18.2 MB/s'),
                    trailing: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Amazon Kindle.apk'), findsOneWidget);
      expect(find.text('69.70 MB · apps/com.amazon.kindle'), findsOneWidget);
      expect(find.text('Sending'), findsOneWidget);
      expect(find.text('18.2 MB/s'), findsOneWidget);
      expect(find.byIcon(Icons.android_rounded), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plasma progress bar accepts completed and zero progress',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ElectricProgressBar(value: 0, height: 10),
                ElectricProgressBar(value: 1, height: 10),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    },
  );
}
