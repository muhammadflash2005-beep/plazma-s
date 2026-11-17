import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/protocol/frame_codec.dart';

void main() {
  group('FrameCodec', () {
    final codec = FrameCodec();

    test('round-trips a JSON message', () {
      final original = <String, Object?>{'type': 'ping', 'id': 'ABC123'};
      expect(codec.tryDecode(codec.encode(original)), original);
    });

    test('waits for incomplete headers and payloads', () {
      final frame = codec.encode({'type': 'hello'});
      expect(codec.tryDecode(Uint8List.fromList(frame.sublist(0, 2))), isNull);
      expect(
        codec.tryDecode(Uint8List.fromList(frame.sublist(0, frame.length - 1))),
        isNull,
      );
    });

    test('rejects frames above the configured limit', () {
      final smallCodec = FrameCodec(maxFrameBytes: 4);
      expect(() => smallCodec.encode({'data': 'too long'}), throwsFormatException);
    });

    test('rejects zero-length frames', () {
      expect(
        () => codec.tryDecode(Uint8List.fromList([0, 0, 0, 0])),
        throwsFormatException,
      );
    });
  });
}
