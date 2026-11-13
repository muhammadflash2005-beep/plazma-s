import 'dart:typed_data';

import 'frame_codec.dart';

/// Reassembles TCP byte chunks into complete protocol messages.
///
/// A single socket event may contain a partial frame, one frame, or several
/// frames. This decoder handles all three cases without assuming packet
/// boundaries.
class FrameStreamDecoder {
  FrameStreamDecoder({FrameCodec? codec}) : codec = codec ?? FrameCodec();

  final FrameCodec codec;
  Uint8List _pending = Uint8List(0);

  int get pendingBytes => _pending.length;

  List<Map<String, Object?>> add(Uint8List chunk) {
    if (chunk.isEmpty) return const [];

    final combined = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);

    final messages = <Map<String, Object?>>[];
    var offset = 0;

    while (combined.length - offset >= 4) {
      final view = ByteData.sublistView(combined, offset);
      final payloadLength = view.getUint32(0, Endian.big);
      if (payloadLength == 0 || payloadLength > codec.maxFrameBytes) {
        _pending = Uint8List(0);
        throw FormatException('Invalid frame length: $payloadLength');
      }

      final frameLength = 4 + payloadLength;
      if (combined.length - offset < frameLength) break;

      final frame = Uint8List.sublistView(combined, offset, offset + frameLength);
      final message = codec.tryDecode(frame);
      if (message == null) {
        throw StateError('Complete frame was not decoded.');
      }
      messages.add(message);
      offset += frameLength;
    }

    _pending = Uint8List.fromList(combined.sublist(offset));
    if (_pending.length > codec.maxFrameBytes + 4) {
      _pending = Uint8List(0);
      throw FormatException('Incomplete frame exceeds maximum allowed size.');
    }
    return messages;
  }

  void reset() => _pending = Uint8List(0);
}
