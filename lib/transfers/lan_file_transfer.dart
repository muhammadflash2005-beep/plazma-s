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

/// Resumable, one-file-per-connection TCP transfer.
///
/// The receiver stores incomplete data in a private partial directory. The
/// transfer identity is stable for the same content and relative destination,
/// so calling sendFile again resumes from the receiver's reported offset.
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
    File? partialFile;
    File? metadataFile;
    try {
      final prefix = await reader.readExact(4);
      final headerLength = ByteData.sublistView(prefix).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final decoded = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 2 ||
          decoded['name'] is! String ||
          decoded['size'] is! int ||
          decoded['sha256'] is! String ||
          decoded['transferId'] is! String ||
          decoded['relativePath'] is! String) {
        throw const FormatException('Invalid or unsupported transfer metadata.');
      }

      final suppliedCode = decoded['authorizationCode'];
      final name = _safeFileName(decoded['name'] as String);
      final relativePath = _safeRelativePath(decoded['relativePath'] as String);
      final expectedSize = decoded['size'] as int;
      final expectedHash = decoded['sha256'] as String;
      final transferId = decoded['transferId'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(transferId) ||
          expectedSize < 0 || expectedSize > (1 << 50) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
        throw const FormatException('Invalid transfer identity, size, or digest.');
      }
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        socket.add(List<int>.filled(8, 255));
        await socket.flush();
        throw const FormatException('Transfer authorization failed.');
      }

      final target = File('${destination.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        throw FileSystemException('A file with this name already exists.', target.path);
      }

      final partialDirectory = Directory('${destination.path}${Platform.pathSeparator}.plazma_s_partial');
      await partialDirectory.create(recursive: true);
      partialFile = File('${partialDirectory.path}${Platform.pathSeparator}$transferId.part');
      metadataFile = File('${partialDirectory.path}${Platform.pathSeparator}$transferId.json');

      final expectedMetadata = jsonEncode({
        'version': 2,
        'name': name,
        'relativePath': relativePath,
        'size': expectedSize,
        'sha256': expectedHash,
      });
      if (await metadataFile.exists()) {
        final saved = jsonDecode(await metadataFile.readAsString());
        if (saved is! Map<String, dynamic> ||
            saved['version'] != 2 ||
            saved['name'] != name ||
            saved['relativePath'] != relativePath ||
            saved['size'] != expectedSize ||
            saved['sha256'] != expectedHash) {
          throw const FormatException('A different transfer already uses this resume identity.');
        }
      } else {
        await metadataFile.writeAsString(expectedMetadata, flush: true);
      }
      if (!await partialFile.exists()) {
        await partialFile.create(recursive: true);
      }
      var offset = await partialFile.length();
      if (offset > expectedSize) {
        throw const FormatException('Saved partial file exceeds the declared size.');
      }

      final offsetBytes = Uint8List(8);
      ByteData.sublistView(offsetBytes).setUint64(0, offset, Endian.big);
      socket.add(offsetBytes);
      await socket.flush();

      output = partialFile.openWrite(mode: FileMode.append);
      await for (final chunk in reader.readPayload(expectedSize - offset)) {
        output.add(chunk);
        offset += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;

      final actualHash = await sha256.bind(partialFile.openRead()).first;
      if (await partialFile.length() != expectedSize || actualHash.toString() != expectedHash) {
        await partialFile.delete();
        if (await metadataFile.exists()) await metadataFile.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }

      await partialFile.rename(target.path);
      partialFile = null;
      if (await metadataFile.exists()) await metadataFile.delete();
      await onReceived(target, name, actualHash.toString());
      socket.add([1]);
      await socket.flush();
    } catch (error) {
      await output?.close();
      // Keep partial data on connection loss so the next sendFile call resumes.
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
    Duration timeout = const Duration(seconds: 30),
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
    final transferId = sha256.convert(utf8.encode(
      'plazma-s-v2:${stat.size}:${digest.toString()}:$safeRelativePath',
    )).toString();
    final metadata = utf8.encode(jsonEncode({
      'version': 2,
      'transferId': transferId,
      'name': _safeFileName(name),
      'relativePath': safeRelativePath,
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);
    final socket = await Socket.connect(host, port, timeout: timeout);
    final reader = _SocketByteReader(socket);

    try {
      socket.add(prefix);
      socket.add(metadata);
      await socket.flush();

      final offsetBytes = await reader.readExact(8).timeout(timeout);
      final offset = ByteData.sublistView(offsetBytes).getUint64(0, Endian.big);
      if (offset > stat.size) {
        throw const FormatException('Receiver supplied an invalid resume offset or rejected authorization.');
      }

      final started = DateTime.now();
      var sent = offset;
      onProgress(TransferProgress(
        bytesTransferred: sent,
        totalBytes: stat.size,
        bytesPerSecond: 0,
      ));
      await for (final chunk in file.openRead(offset)) {
        socket.add(chunk);
        sent += chunk.length;
        final elapsed = DateTime.now().difference(started).inMicroseconds /
            Duration.microsecondsPerSecond;
        onProgress(TransferProgress(
          bytesTransferred: sent,
          totalBytes: stat.size,
          bytesPerSecond: elapsed <= 0 ? 0 : (sent - offset) / elapsed,
        ));
      }
      await socket.flush();
      final acknowledgement = await reader.readExact(1).timeout(timeout);
      if (acknowledgement.first != 1) {
        throw const FormatException('Receiver rejected the file or its integrity check. Retry to resume if the connection was interrupted.');
      }
      await socket.close();
    } catch (_) {
      socket.destroy();
      rethrow;
    } finally {
      await reader.close();
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
  final normalized = input.replaceAll(RegExp(r'\\'), '/');
  if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw const FormatException('Absolute transfer paths are not allowed.');
  }
  final segments = normalized.split('/');
  if (segments.isEmpty || segments.first == '.plazma_s_partial' || segments.any((segment) =>
      segment.isEmpty || segment == '.' || segment == '..')) {
    throw const FormatException('Invalid relative transfer path.');
  }
  return segments.map(_safeFileName).join('/');
}

String _safeFileName(String input) {
  final normalized = input.replaceAll(RegExp(r'\\'), '/');
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
          throw const FormatException('Connection closed during transfer.');
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
