import 'dart:async';
import 'dart:io';

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
        onProgress: (progress) => progressValues.add(progress.bytesTransferred),
      );

      final result = await received.future.timeout(const Duration(seconds: 5));
      expect(await result.readAsBytes(), bytes);
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, bytes.length);
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
