import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/protocol/frame_codec.dart';
import 'package:plazma_s/protocol/frame_stream_decoder.dart';

void main() {
  group('FrameStreamDecoder', () {
    final codec = FrameCodec();

    test('reassembles a frame split across chunks', () {
      final decoder = FrameStreamDecoder(codec: codec);
      final frame = codec.encode({'type': 'hello', 'value': 7});

      expect(decoder.add(Uint8List.fromList(frame.sublist(0, 3))), isEmpty);
      expect(decoder.pendingBytes, 3);
      expect(
        decoder.add(Uint8List.fromList(frame.sublist(3))),
        [
          {'type': 'hello', 'value': 7},
        ],
      );
      expect(decoder.pendingBytes, 0);
    });

    test('decodes multiple coalesced frames in order', () {
      final decoder = FrameStreamDecoder(codec: codec);
      final first = codec.encode({'type': 'one'});
      final second = codec.encode({'type': 'two'});
      final combined = Uint8List.fromList([...first, ...second]);

      expect(
        decoder.add(combined),
        [
          {'type': 'one'},
          {'type': 'two'},
        ],
      );
    });

    test('keeps an incomplete trailing frame after a complete frame', () {
      final decoder = FrameStreamDecoder(codec: codec);
      final first = codec.encode({'type': 'one'});
      final second = codec.encode({'type': 'two'});
      final partial = Uint8List.fromList([...first, ...second.take(5)]);

      expect(decoder.add(partial), [
        {'type': 'one'},
      ]);
      expect(decoder.pendingBytes, 5);
      expect(decoder.add(Uint8List.fromList(second.skip(5).toList())), [
        {'type': 'two'},
      ]);
    });

    test('rejects invalid frame lengths', () {
      final decoder = FrameStreamDecoder(codec: FrameCodec(maxFrameBytes: 8));
      expect(
        () => decoder.add(Uint8List.fromList([0, 0, 0, 9])),
        throwsFormatException,
      );
    });
  });
}
