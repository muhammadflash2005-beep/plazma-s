import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/features/apps/apk_bundle.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('plazma-apk-bundle-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeApk(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}${name}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> craftBundle({
    required String packageName,
    required String entryName,
    required List<int> payload,
    required String digest,
  }) async {
    final payloadFile = await writeApk('crafted-payload.apk', payload);
    final manifestFile = File('${temp.path}${Platform.pathSeparator}crafted-manifest.json');
    await manifestFile.writeAsString(jsonEncode({
      'format': ApkBundle.formatName,
      'version': 1,
      'packageName': packageName,
      'files': [
        {'name': entryName, 'size': payload.length, 'sha256': digest},
      ],
    }));
    final bundle = File('${temp.path}${Platform.pathSeparator}crafted.apks');
    final encoder = ZipFileEncoder()..create(bundle.path, level: ZipFileEncoder.store);
    await encoder.addFile(payloadFile, entryName, ZipFileEncoder.store);
    await encoder.addFile(manifestFile, ApkBundle.manifestName, ZipFileEncoder.store);
    await encoder.close();
    return bundle;
  }

  test('exports base and split APKs as one streamed, verifiable bundle', () async {
    final base = await writeApk('base.apk', [1, 2, 3, 4]);
    final split = await writeApk('split_1.apk', [5, 6, 7, 8]);
    final bundle = await ApkBundle.create(
      packageName: 'com.example.transfer',
      apkFiles: [split, base],
      outputDirectory: Directory('${temp.path}${Platform.pathSeparator}out'),
    );

    expect(bundle.path.endsWith('com.example.transfer.apks'), isTrue);
    final extracted = await ApkBundle.extract(
      bundle: bundle,
      expectedPackageName: 'com.example.transfer',
      destinationDirectory: Directory('${temp.path}${Platform.pathSeparator}received'),
    );
    expect(extracted.map((file) => file.uri.pathSegments.last).toList(),
        ['base.apk', 'split_1.apk']);
    expect(await extracted[0].readAsBytes(), [1, 2, 3, 4]);
    expect(await extracted[1].readAsBytes(), [5, 6, 7, 8]);
  });

  test('rejects a bundle for a different Android package', () async {
    final base = await writeApk('base.apk', [1, 2, 3]);
    final bundle = await ApkBundle.create(
      packageName: 'com.example.sender',
      apkFiles: [base],
      outputDirectory: Directory('${temp.path}${Platform.pathSeparator}out'),
    );
    await expectLater(
      ApkBundle.extract(
        bundle: bundle,
        expectedPackageName: 'com.example.receiver',
        destinationDirectory: Directory('${temp.path}${Platform.pathSeparator}received'),
      ),
      throwsFormatException,
    );
  });

  test('rejects APK bytes whose manifest checksum does not match', () async {
    final bundle = await craftBundle(
      packageName: 'com.example.transfer',
      entryName: 'base.apk',
      payload: [9, 8, 7, 6],
      digest: List.filled(64, '0').join(),
    );
    await expectLater(
      ApkBundle.extract(
        bundle: bundle,
        expectedPackageName: 'com.example.transfer',
        destinationDirectory: Directory('${temp.path}${Platform.pathSeparator}received'),
      ),
      throwsFormatException,
    );
  });

  test('rejects path traversal entries before writing outside the app folder', () async {
    final bundle = await craftBundle(
      packageName: 'com.example.transfer',
      entryName: '../outside.apk',
      payload: [1, 2, 3],
      digest: List.filled(64, 'a').join(),
    );
    final destination = Directory('${temp.path}${Platform.pathSeparator}received');
    await expectLater(
      ApkBundle.extract(
        bundle: bundle,
        expectedPackageName: 'com.example.transfer',
        destinationDirectory: destination,
      ),
      throwsFormatException,
    );
    expect(await File('${temp.path}${Platform.pathSeparator}outside.apk').exists(), isFalse);
  });

  test('requires the base APK when creating a bundle', () async {
    final split = await writeApk('split_1.apk', [1, 2, 3]);
    await expectLater(
      ApkBundle.create(
        packageName: 'com.example.transfer',
        apkFiles: [split],
        outputDirectory: Directory('${temp.path}${Platform.pathSeparator}out'),
      ),
      throwsStateError,
    );
  });
}
