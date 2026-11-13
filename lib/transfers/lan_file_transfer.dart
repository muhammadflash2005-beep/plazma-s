import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

/// Progress for one LAN file transfer. Bytes are payload bytes, excluding the
/// small metadata header.
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

/// A simple, dedicated binary TCP data channel.
///
/// Control messages stay on TcpPeer's framed JSON channel. File bytes use this
/// separate stream so large files are never JSON/base64 encoded or buffered in
/// memory. Each connection currently carries one file.
class LanFileTransfer {
  LanFileTransfer({this.port = 0});

  final int port;
  ServerSocket? _server;

  int? get listeningPort => _server?.port;
  bool get isListening => _server != null;

  Future<void> startReceiver({
    required Directory destination,
    required String authorizationCode,
    required FutureOr<void> Function(File file, String name, String sha256)
        onReceived,
    FutureOr<void> Function(Object error)? onError,
    InternetAddress? address,
  }) async {
    if (_server != null) throw StateError('Transfer receiver is already running.');
    if (!RegExp(r'^[0-9]{6}$').hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    await destination.create(recursive: true);
    _server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      unawaited(_receiveOne(
        socket,
        destination,
        authorizationCode,
        onReceived,
        onError,
      ));
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
      final lengthBytes = await reader.readExact(4);
      final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final header = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (header is! Map<String, dynamic> ||
          header['name'] is! String ||
          header['size'] is! int ||
          header['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }
      final name = _safeFileName(header['name'] as String);
      final suppliedCode = header['authorizationCode'];
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        throw const FormatException('Transfer authorization failed.');
      }
      final expectedSize = header['size'] as int;
      final expectedHash = header['sha256'] as String;
      if (expectedSize < 0 || expectedSize > 1 << 50) {
        throw const FormatException('Invalid file size.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}$name');
      if (await file.exists()) throw FileSystemException('A file with this name already exists.', file.path);
      targetFile = file;
      output = file.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var received = 0;
      await for (final chunk in reader.remaining()) {
        if (received + chunk.length > expectedSize) {
          throw const FormatException('Received more bytes than declared.');
        }
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      if (received != expectedSize) {
        await file.delete();
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = hasher.events.single.toString();
      if (actualHash != expectedHash) {
        await file.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }
      await onReceived(file, name, actualHash);
      socket.destroy();
    } catch (error) {
      await output?.close();
      // Never leave an incomplete or unauthorized file in the destination.
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      if (onError != null) await onError(error);
      socket.destroy();
    } finally {
      await reader.close();
    }
  }

  /// Sends a file without loading it all into RAM. Hashing is a first streaming
  /// pass; the second pass streams the bytes to the receiving device.
  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    await destination.create(recursive: true);
    _server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      unawaited(_receiveOne(
        socket,
        destination,
        authorizationCode,
        onReceived,
        onError,
      ));
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
      final lengthBytes = await reader.readExact(4);
      final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final header = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (header is! Map<String, dynamic> ||
          header['name'] is! String ||
          header['size'] is! int ||
          header['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }
      final name = _safeFileName(header['name'] as String);
      final suppliedCode = header['authorizationCode'];
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        throw const FormatException('Transfer authorization failed.');
      }
      final expectedSize = header['size'] as int;
      final expectedHash = header['sha256'] as String;
      if (expectedSize < 0 || expectedSize > 1 << 50) {
        throw const FormatException('Invalid file size.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}$name');
      targetFile = file;
      output = file.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var received = 0;
      await for (final chunk in reader.remaining()) {
        if (received + chunk.length > expectedSize) {
          throw const FormatException('Received more bytes than declared.');
        }
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      if (received != expectedSize) {
        await file.delete();
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = hasher.events.single.toString();
      if (actualHash != expectedHash) {
        await file.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }
      await onReceived(file, name, actualHash);
      socket.destroy();
    } catch (error) {
      await output?.close();
      // Never leave an incomplete or unauthorized file in the destination.
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      if (onError != null) await onError(error);
      socket.destroy();
    } finally {
      await reader.close();
    }
  }

  /// Sends a file without loading it all into RAM. Hashing is a first streaming
  /// pass; the second pass streams the bytes to the receiving device.
  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    await destination.create(recursive: true);
    _server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      unawaited(_receiveOne(
        socket,
        destination,
        authorizationCode,
        onReceived,
        onError,
      ));
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
      final lengthBytes = await reader.readExact(4);
      final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final header = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (header is! Map<String, dynamic> ||
          header['name'] is! String ||
          header['size'] is! int ||
          header['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }
      final name = _safeFileName(header['name'] as String);
      final suppliedCode = header['authorizationCode'];
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        throw const FormatException('Transfer authorization failed.');
      }
      final expectedSize = header['size'] as int;
      final expectedHash = header['sha256'] as String;
      if (expectedSize < 0 || expectedSize > 1 << 50) {
        throw const FormatException('Invalid file size.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}$name');
      if (await file.exists()) throw FileSystemException('A file with this name already exists.', file.path);
      targetFile = file;
      output = file.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var received = 0;
      await for (final chunk in reader.remaining()) {
        if (received + chunk.length > expectedSize) {
          throw const FormatException('Received more bytes than declared.');
        }
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      if (received != expectedSize) {
        await file.delete();
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = hasher.events.single.toString();
      if (actualHash != expectedHash) {
        await file.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }
      await onReceived(file, name, actualHash);
      socket.destroy();
    } catch (error) {
      await output?.close();
      // Never leave an incomplete or unauthorized file in the destination.
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      if (onError != null) await onError(error);
      socket.destroy();
    } finally {
      await reader.close();
    }
  }

  /// Sends a file without loading it all into RAM. Hashing is a first streaming
  /// pass; the second pass streams the bytes to the receiving device.
  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!RegExp(r'^\\d{6}
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    await destination.create(recursive: true);
    _server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      unawaited(_receiveOne(
        socket,
        destination,
        authorizationCode,
        onReceived,
        onError,
      ));
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
      final lengthBytes = await reader.readExact(4);
      final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final header = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (header is! Map<String, dynamic> ||
          header['name'] is! String ||
          header['size'] is! int ||
          header['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }
      final name = _safeFileName(header['name'] as String);
      final suppliedCode = header['authorizationCode'];
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        throw const FormatException('Transfer authorization failed.');
      }
      final expectedSize = header['size'] as int;
      final expectedHash = header['sha256'] as String;
      if (expectedSize < 0 || expectedSize > 1 << 50) {
        throw const FormatException('Invalid file size.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}$name');
      targetFile = file;
      output = file.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var received = 0;
      await for (final chunk in reader.remaining()) {
        if (received + chunk.length > expectedSize) {
          throw const FormatException('Received more bytes than declared.');
        }
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      if (received != expectedSize) {
        await file.delete();
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = hasher.events.single.toString();
      if (actualHash != expectedHash) {
        await file.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }
      await onReceived(file, name, actualHash);
      socket.destroy();
    } catch (error) {
      await output?.close();
      // Never leave an incomplete or unauthorized file in the destination.
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      if (onError != null) await onError(error);
      socket.destroy();
    } finally {
      await reader.close();
    }
  }

  /// Sends a file without loading it all into RAM. Hashing is a first streaming
  /// pass; the second pass streams the bytes to the receiving device.
  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
).hasMatch(authorizationCode)) {
      throw ArgumentError.value(authorizationCode, 'authorizationCode', 'Must be six digits.');
    }
    await destination.create(recursive: true);
    _server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      unawaited(_receiveOne(
        socket,
        destination,
        authorizationCode,
        onReceived,
        onError,
      ));
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
      final lengthBytes = await reader.readExact(4);
      final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid transfer header length.');
      }
      final header = jsonDecode(utf8.decode(await reader.readExact(headerLength)));
      if (header is! Map<String, dynamic> ||
          header['name'] is! String ||
          header['size'] is! int ||
          header['sha256'] is! String) {
        throw const FormatException('Invalid transfer metadata.');
      }
      final name = _safeFileName(header['name'] as String);
      final suppliedCode = header['authorizationCode'];
      if (suppliedCode is! String || !_constantTimeEquals(suppliedCode, authorizationCode)) {
        throw const FormatException('Transfer authorization failed.');
      }
      final expectedSize = header['size'] as int;
      final expectedHash = header['sha256'] as String;
      if (expectedSize < 0 || expectedSize > 1 << 50) {
        throw const FormatException('Invalid file size.');
      }

      final file = File('${destination.path}${Platform.pathSeparator}$name');
      targetFile = file;
      output = file.openWrite();
      final hasher = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(hasher);
      var received = 0;
      await for (final chunk in reader.remaining()) {
        if (received + chunk.length > expectedSize) {
          throw const FormatException('Received more bytes than declared.');
        }
        output.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
      }
      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      if (received != expectedSize) {
        await file.delete();
        throw const FormatException('Transfer ended before the full file arrived.');
      }
      final actualHash = hasher.events.single.toString();
      if (actualHash != expectedHash) {
        await file.delete();
        throw const FormatException('File integrity check failed (SHA-256 mismatch).');
      }
      await onReceived(file, name, actualHash);
      socket.destroy();
    } catch (error) {
      await output?.close();
      // Never leave an incomplete or unauthorized file in the destination.
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      if (onError != null) await onError(error);
      socket.destroy();
    } finally {
      await reader.close();
    }
  }

  /// Sends a file without loading it all into RAM. Hashing is a first streaming
  /// pass; the second pass streams the bytes to the receiving device.
  Future<void> sendFile({
    required String host,
    required int port,
    required File file,
    required String authorizationCode,
    required void Function(TransferProgress progress) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Only regular files can be transferred.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    final socket = await Socket.connect(host, port, timeout: timeout);
    final name = file.uri.pathSegments.isEmpty
        ? 'file'
        : Uri.decodeComponent(file.uri.pathSegments.last);
    final metadata = utf8.encode(jsonEncode({
      'name': _safeFileName(name),
      'authorizationCode': authorizationCode,
      'size': stat.size,
      'sha256': digest.toString(),
    }));
    final prefix = Uint8List(4);
    ByteData.sublistView(prefix).setUint32(0, metadata.length, Endian.big);

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _safeFileName(String input) {
  final normalized = input.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name == '.' || name == '..') {
    throw const FormatException('Invalid file name.');
  }
  return name.replaceAll(RegExp(r'[\\x00-\\x1f]'), '_');
}

/// Reads exact bytes from a TCP stream while preserving any bytes that arrived
/// in the same packet as the preceding field.
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

  Stream<Uint8List> remaining() async* {
    if (_offset < _pending.length) {
      yield Uint8List.sublistView(_pending, _offset);
      _offset = _pending.length;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> close() => _iterator.cancel();
}
