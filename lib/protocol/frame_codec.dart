import 'dart:convert';
import 'dart:typed_data';

/// Wire format: 4-byte unsigned big-endian payload length followed by UTF-8 JSON.
/// TCP is a byte stream: this prefix allows callers to handle partial/coalesced data.
class FrameCodec {
  FrameCodec({this.maxFrameBytes = 1024 * 1024});

  final int maxFrameBytes;

  Uint8List encode(Map<String, Object?> message) {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(message)));
    if (payload.isEmpty || payload.length > maxFrameBytes) {
      throw FormatException('Frame size must be between 1 and $maxFrameBytes bytes.');
    }
    final frame = Uint8List(4 + payload.length);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  /// Decodes the first complete frame; null means the buffer is incomplete.
  Map<String, Object?>? tryDecode(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final length = ByteData.sublistView(bytes).getUint32(0, Endian.big);
    if (length == 0 || length > maxFrameBytes) {
      throw FormatException('Invalid frame length: $length');
    }
    if (bytes.length < 4 + length) return null;
    final decoded = jsonDecode(utf8.decode(bytes.sublist(4, 4 + length)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Frame payload must be a JSON object.');
    }
    return decoded;
  }
}
