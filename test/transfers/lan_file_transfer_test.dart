import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/transfers/lan_file_transfer.dart';

void main() {
  group('LanFileTransfer', () {
    late Directory temporaryDirectory;
    late Directory receivedDirectory;
    late LanFileTransfer receiver;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('plazma-send-');
      receivedDirectory = Directory('${temporaryDirectory.path}/received');
      receiver = LanFileTransfer();
    });

    tearDown(() async {
      await receiver.close();
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('streams a file and verifies its SHA-256 before accepting it', () async {
      final source = File('${temporaryDirectory.path}/sample.bin');
      final bytes = List<int>.generate(256 * 1024, (index) => index % 251);
      await source.writeAsBytes(bytes);
      final received = Completer<File>();

      await receiver.startReceiver(
        destination: receivedDirectory,
        authorizationCode: '482915',
        onReceived: (file, name, hash) {
          received.complete(file);
        },
        onError: (error) {
          if (!received.isCompleted) received.completeError(error);
        },
      );

      final progressValues = <int>[];
      await LanFileTransfer().sendFile(
        host: InternetAddress.loopbackIPv4.address,
        port: receiver.listeningPort!,
        file: source,
        authorizationCode: '482915',
        relativePath: 'Camera/2026/sample.bin',
        onProgress: (progress) => progressValues.add(progress.bytesTransferred),
      );

      final result = await received.future.timeout(const Duration(seconds: 5));
      expect(result.path, endsWith('Camera/2026/sample.bin'));
      expect(await result.readAsBytes(), bytes);
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, bytes.length);
    });

    test('resumes from the receiver partial file offset', () async {
      final source = File('${temporaryDirectory.path}/resume.bin');
      final bytes = List<int>.generate(512 * 1024, (index) => index % 239);
      await source.writeAsBytes(bytes);
      const relativePath = 'Camera/resume.bin';
      final hash = sha256.convert(bytes).toString();
      final transferId = sha256.convert(utf8.encode(
        'plazma-s-v2:${bytes.length}:$hash:$relativePath',
      )).toString();

      final destinationKey = sha256.convert(
        utf8.encode(receivedDirectory.absolute.path),
      ).toString();
      final partialDirectory = Directory(
        '${Directory.systemTemp.path}/plazma_s_partial/$destinationKey',
      );
      await partialDirectory.create(recursive: true);
      final partial = File('${partialDirectory.path}/$transferId.part');
      final resumeOffset = bytes.length ~/ 3;
      await partial.writeAsBytes(bytes.sublist(0, resumeOffset));
      final metadata = File('${partialDirectory.path}/$transferId.json');
      await metadata.writeAsString(jsonEncode({
        'version': 2,
        'name': 'resume.bin',
        'relativePath': relativePath,
        'size': bytes.length,
        'sha256': hash,
      }));

      final received = Completer<File>();
      await receiver.startReceiver(
        destination: receivedDirectory,
        authorizationCode: '482915',
        onReceived: (file, name, digest) => received.complete(file),
        onError: (error) {
          if (!received.isCompleted) received.completeError(error);
        },
      );

      final progressValues = <int>[];
      await LanFileTransfer().sendFile(
        host: InternetAddress.loopbackIPv4.address,
        port: receiver.listeningPort!,
        file: source,
        authorizationCode: '482915',
        relativePath: relativePath,
        onProgress: (progress) => progressValues.add(progress.bytesTransferred),
      );

      final result = await received.future.timeout(const Duration(seconds: 5));
      expect(progressValues.first, resumeOffset);
      expect(progressValues.last, bytes.length);
      expect(await result.readAsBytes(), bytes);
      expect(await partial.exists(), isFalse);
      expect(await metadata.exists(), isFalse);
    });

    test('does not allow a transfer to target its private resume directory', () async {
      final source = File('${temporaryDirectory.path}/reserved.bin');
      await source.writeAsBytes([1]);
      await expectLater(
        LanFileTransfer().sendFile(
          host: InternetAddress.loopbackIPv4.address,
          port: 0,
          file: source,
          authorizationCode: '482915',
          relativePath: '.plazma_s_partial/attack.bin',
          onProgress: (_) {},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects parent traversal in a relative transfer path', () async {
      final source = File('${temporaryDirectory.path}/outside.bin');
      await source.writeAsBytes([7, 8, 9]);

      await expectLater(
        LanFileTransfer().sendFile(
          host: InternetAddress.loopbackIPv4.address,
          port: 0,
          file: source,
          authorizationCode: '482915',
          relativePath: '../outside.bin',
          onProgress: (_) {},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a sender with an incorrect pairing code', () async {
      final source = File('${temporaryDirectory.path}/private.bin');
      await source.writeAsBytes([1, 2, 3, 4]);
      final rejected = Completer<Object>();
      await receiver.startReceiver(
        destination: receivedDirectory,
        authorizationCode: '482915',
        onReceived: (file, name, hash) {},
        onError: (error) {
          if (!rejected.isCompleted) rejected.complete(error);
        },
      );

      await expectLater(
        LanFileTransfer().sendFile(
          host: InternetAddress.loopbackIPv4.address,
          port: receiver.listeningPort!,
          file: source,
          authorizationCode: '111111',
          onProgress: (_) {},
        ),
        throwsA(isA<FormatException>()),
      );

      final error = await rejected.future.timeout(const Duration(seconds: 5));
      expect(error, isA<FormatException>());
      expect(await receivedDirectory.list().isEmpty, isTrue);
    });
  });
}
