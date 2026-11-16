import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/features/apps/app_bundle.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plazma-app-bundle-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('round-trips base and split APKs as one bundle', () async {
    final base = File('${root.path}/base.apk')..writeAsBytesSync([1, 2, 3, 4]);
    final split = File('${root.path}/split_config.arm64_v8a.apk')
      ..writeAsBytesSync([5, 6, 7, 8, 9]);
    final bundle = File('${root.path}/com.example.demo.plazmaapp');

    await AppBundle.create(
      output: bundle,
      packageName: 'com.example.demo',
      appName: 'Demo',
      versionName: '2.4.1',
      versionCode: 20401,
      apks: [split, base],
    );

    final destination = Directory('${root.path}/received');
    final result = await AppBundle.extract(bundle: bundle, outputDirectory: destination);

    expect(result.packageName, 'com.example.demo');
    expect(result.appName, 'Demo');
    expect(result.versionName, '2.4.1');
    expect(result.versionCode, 20401);
    expect(result.apkPaths.map((path) => path.split(Platform.pathSeparator).last),
        ['base.apk', 'split_config.arm64_v8a.apk']);
    expect(await File(result.apkPaths.first).readAsBytes(), [1, 2, 3, 4]);
    expect(await File(result.apkPaths.last).readAsBytes(), [5, 6, 7, 8, 9]);
  });

  test('rejects a bundle whose APK payload checksum is wrong', () async {
    final base = File('${root.path}/base.apk')..writeAsBytesSync([10, 20, 30, 40]);
    final bundle = File('${root.path}/broken.plazmaapp');
    await AppBundle.create(
      output: bundle,
      packageName: 'com.example.demo',
      appName: 'Demo',
      versionName: '1',
      versionCode: 1,
      apks: [base],
    );
    final bytes = await bundle.readAsBytes();
    bytes[bytes.length - 1] = 99;
    await bundle.writeAsBytes(bytes, flush: true);

    await expectLater(
      AppBundle.extract(bundle: bundle, outputDirectory: Directory('${root.path}/out')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid package names before creating a bundle', () async {
    final base = File('${root.path}/base.apk')..writeAsBytesSync([1]);
    await expectLater(
      AppBundle.create(
        output: File('${root.path}/bad.plazmaapp'),
        packageName: '../escape',
        appName: 'Bad',
        versionName: '1',
        versionCode: 1,
        apks: [base],
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an unsupported or malformed header', () async {
    final bundle = File('${root.path}/malformed.plazmaapp')
      ..writeAsBytesSync(utf8.encode('not an app bundle'));
    await expectLater(
      AppBundle.extract(bundle: bundle, outputDirectory: Directory('${root.path}/out')),
      throwsA(isA<FormatException>()),
    );
  });
}
