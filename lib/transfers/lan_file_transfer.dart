import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

class TransferProgress {
  const TransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.bytesPerSecond,
  });
  final int bytesTransferred;
  final int totalBytes;
  final double bytesPerSecond;
  double get fraction => totalBytes == 0 ? 1 : bytesTransferred / totalBytes;
}

/// One file per direct TCP connection. The receiver acknowledges only after
/// the declared payload length and SHA-256 digest have been verified.
class LanFileTransfer {
  LanFileTransfer({this.port = 0});
  final int port;
  ServerSocket? _server;

  int? get listeningPort => _server?.port;
  bool get isListening => _server != null;

  Future<void> startReceiver({
    required Directory destination,
    required String authorizationCode,
    required FutureOr<void> Function(File file, String name, String sha256) onReceived,
    FutureOr<void> Function(Object error)? onError,
    InternetAddress? address,
  }) async {
    if (_server != null) throw StateError('Transfer receiver is already running.');
    _validateCode(authorizationCode);
    await destination.create(recursive: true);
    final server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((socket) {
      unawaited(_receiveOne(socket, destination, authorizationCode, onReceived, onError));
    });
  }

  Future<void> _receiveOne(
    Socket socket,
    Directory destination,
    String authorizationCode,
    FutureOr<void> Function(File, String, String) onReceived,
    FutureOr<void> Function(Object)? onError,
  ) async {
    final reader = _SocketByteReader(socket);
    IOSink? output;
    File? targetFile;
    try {
      final prefix = await reader.readExact(4);
      final headerLength = ByteData.sublistView(prefix).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final decoded = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (decoded is! Map<String, dynamic> ||
          decoded['name'] is! String ||
          decoded['size'] is! int ||
          decoded['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }

      final suppliedCode = decoded['authorizationCode'];
      final name = _safeFileName(decoded['name'] as String);
      final relativePath = _safeRelativePath(decoded['relativePath'] is String
          ? decoded['relativePath'] as String
          : name);
      final expectedSize = decoded['size'] as int;
      final expectedHash = decoded['sha256'] as String;
      if (expectedSize < 0 || expectedSize > (1 << 50)) {
        throw const FormatException('Invalid file size.');
      }
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        await for (final _ in reader.readPayload(expectedSize).timeout(const Duration(seconds: 60))) {}
        throw const FormatException('Transfer authorization failed.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        throw FileSystemException('A file with this name already exists.', file.path);
      }
      targetFile = file;
      output = file.openWrite();

      final digestSink = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in reader.readPayload(expectedSize)) {
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }

      await output.flush();
      await output.close();
      output = null;
      hashInput.close();

      if (received != expectedSize) {
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = digestSink.events.single.toString();
      if (actualHash != expectedHash) {
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }

      await onReceived(file, name, actualHash);
      socket.add([1]);
      await socket.flush();
    } catch (error) {
      await output?.close();
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      socket.add([0]);
      try {
        await socket.flush();
      } catch (_) {}
      if (onError != null) await onError(error);
    } finally {
      socket.destroy();
      await reader.close();
    }
  }

  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    String? relativePath,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _validateCode(authorizationCode);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final safeRelativePath = _safeRelativePath(relativePath ?? name);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'relativePath': safeRelativePath,
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);
    final socket = await Socket.connect(host, port, timeout: timeout);

    try {
      socket.add(prefix);
      socket.add(metadata);
      await socket.flush();

      final started = DateTime.now();
      var sent = 0;
      await for (final chunk in file.openRead()) {
        socket.add(chunk);
        sent += chunk.length;
        final elapsed = DateTime.now().difference(started).inMicroseconds /
            Duration.microsecondsPerSecond;
        onProgress(TransferProgress(
          bytesTransferred: sent,
          totalBytes: stat.size,
          bytesPerSecond: elapsed <= 0 ? 0 : sent / elapsed,
        ));
      }
      await socket.flush();
      final acknowledgement = await socket.first.timeout(timeout);
      if (acknowledgement.isEmpty || acknowledgement.first != 1) {
        throw const FormatException('Receiver rejected the file or its integrity check.');
      }
      await socket.close();
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close();
  }
}

void _validateCode(String code) {
  if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
    throw ArgumentError.value(code, 'authorizationCode', 'Must be six digits.');
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeRelativePath(String input) {
  final normalized = input.replaceAll(r'\', '/');
  if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw const FormatException('Absolute transfer paths are not allowed.');
  }
  final segments = normalized.split('/');
  if (segments.isEmpty || segments.any((segment) =>
      segment.isEmpty || segment == '.' || segment == '..')) {
    throw const FormatException('Invalid relative transfer path.');
  }
  return segments.map(_safeFileName).join('/');
}

String _safeFileName(String input) {
  final normalized = input.replaceAll(r'\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\x00-\x1f]'), '_');
}

class _SocketByteReader {
  _SocketByteReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);
  final StreamIterator<Uint8List> _iterator;
  Uint8List _pending = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readExact(int count) async {
    final result = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_offset >= _pending.length) {
        if (!await _iterator.moveNext()) {
          throw const FormatException('Connection closed during transfer header.');
        }
        _pending = _iterator.current;
        _offset = 0;
      }
      final available = _pending.length - _offset;
      final take = available < count - written ? available : count - written;
      result.setRange(written, written + take, _pending, _offset);
      written += take;
      _offset += take;
    }
    return result;
  }

  Stream<Uint8List> readPayload(int count) async* {
    var remaining = count;
    while (remaining > 0) {
      if (_offset >= _pending.length) {
        if (!await _iterator.moveNext()) {
          throw const FormatException('Connection closed before the complete file arrived.');
        }
        _pending = _iterator.current;
        _offset = 0;
      }
      final available = _pending.length - _offset;
      if (available > remaining) {
        throw const FormatException('Received more bytes than declared.');
      }
      final take = available < remaining ? available : remaining;
      yield Uint8List.sublistView(_pending, _offset, _offset + take);
      _offset += take;
      remaining -= take;
    }
  }

  Future<void> close() => _iterator.cancel();
}
