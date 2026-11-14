import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/transfers/transfer_mode.dart';

void main() {
  group('TransferMode', () {
    test('PC to PC accepts desktop platforms only', () {
      expect(TransferMode.pcToPc.matches('Windows', 'Linux'), isTrue);
      expect(TransferMode.pcToPc.matches('macOS', 'Windows'), isTrue);
      expect(TransferMode.pcToPc.matches('Android', 'Windows'), isFalse);
      expect(TransferMode.pcToPc.matches('Windows', 'Android'), isFalse);
    });

    test('Android to Android accepts Android devices only', () {
      expect(TransferMode.androidToAndroid.matches('Android', 'Android'), isTrue);
      expect(TransferMode.androidToAndroid.matches('Android', 'Linux'), isFalse);
      expect(TransferMode.androidToAndroid.matches('Windows', 'Android'), isFalse);
    });

    test('PC to Android works in either direction', () {
      expect(TransferMode.pcToAndroid.matches('Windows', 'Android'), isTrue);
      expect(TransferMode.pcToAndroid.matches('Android', 'Linux'), isTrue);
      expect(TransferMode.pcToAndroid.matches('macOS', 'Android'), isTrue);
      expect(TransferMode.pcToAndroid.matches('Android', 'Android'), isFalse);
      expect(TransferMode.pcToAndroid.matches('Windows', 'Linux'), isFalse);
    });

    test('unsupported local platform is rejected', () {
      expect(TransferMode.pcToPc.supportsLocal('iOS'), isFalse);
      expect(TransferMode.androidToAndroid.supportsLocal('Windows'), isFalse);
      expect(TransferMode.pcToAndroid.supportsLocal('iOS'), isFalse);
    });
  });
}
