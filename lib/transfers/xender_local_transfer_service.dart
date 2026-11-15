import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/android_wifi_session_service.dart';

class SharedLocalFile {
  const SharedLocalFile({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.size,
    required this.sha256,
  });

  final int id;
  final String name;
  final String relativePath;
  final int size;
  final String sha256;

  factory SharedLocalFile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final relativePath = json['relativePath'];
    final size = json['size'];
    final digest = json['sha256'];
    if (id is! int ||
        name is! String ||
        relativePath is! String ||
        size is! int ||
        size < 0 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('The sender returned invalid file information.');
    }
    return SharedLocalFile(
      id: id,
      name: name,
      relativePath: relativePath,
      size: size,
      sha256: digest,
    );
  }
}

class LocalTransferProgress {
  const LocalTransferProgress({
    required this.fileName,
    required this.fileBytes,
    required this.fileSize,
    required this.totalBytes,
    required this.totalSize,
  });

  final String fileName;
  final int fileBytes;
  final int fileSize;
  final int totalBytes;
  final int totalSize;

  double get fraction => totalSize == 0 ? 1 : totalBytes / totalSize;
}

/// Direct phone-to-phone sharing over a private Android local-only hotspot.
/// The sender hosts file metadata and download endpoints; the receiver joins
/// the hotspot from the QR invite and downloads directly over that Wi-Fi link.
class XenderLocalTransferService {
  XenderLocalTransferService({AndroidWifiSessionService? wifi})
      : _wifi = wifi ?? AndroidWifiSessionService();

  final AndroidWifiSessionService _wifi;
  static const MethodChannel _foregroundChannel = MethodChannel('com.plazma.s/transfer_service');

  Future<void> _startForegroundService() async {
    try {
      await _foregroundChannel.invokeMethod<void>('start');
    } catch (error) {
      debugPrint('Could not start Plazma transfer notification service: $error');
    }
  }

  Future<void> stopForegroundService() async {
    try {
      await _foregroundChannel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Could not stop Plazma transfer notification service: $error');
    }
  }
  HttpServer? _server;
  List<File> _files = const [];
  List<String> _relativePaths = const [];
  PlazmaConnectionInvite? _invite;

  PlazmaConnectionInvite? get invite => _invite;
  bool get isSharing => _server != null;

  Future<PlazmaConnectionInvite> startSharing({
    required List<File> files,
    required List<String> relativePaths,
  }) async {
    if (_server != null) throw StateError('A sharing session is already running.');
    if (files.isEmpty || files.length != relativePaths.length) {
      throw ArgumentError('Select at least one valid file to share.');
    }

    final checkedFiles = <File>[];
    final checkedPaths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final stat = await files[i].stat();
      if (stat.type != FileSystemEntityType.file) continue;
      checkedFiles.add(files[i]);
      checkedPaths.add(_safeRelativePath(relativePaths[i]));
    }
    if (checkedFiles.isEmpty) throw ArgumentError('No readable files were selected.');

    final invite = await _wifi.createInvite(port: 45454);
    HttpServer? server;
    try {
      // Bind to the address advertised in the QR invite. Binding to 0.0.0.0
      // can silently accept on the sender's normal LAN while the receiver is
      // attached to the isolated local-only hotspot.
      server = await HttpServer.bind(InternetAddress(invite.host), invite.port);
      _files = checkedFiles;
      _relativePaths = checkedPaths;
      _invite = invite;
      _server = server;
      server.listen(
        _handleRequest,
        onError: (Object error, StackTrace stack) {
          debugPrint('Plazma local transfer server error: $error');
        },
      );
      await _startForegroundService();
      return invite;
    } catch (_) {
      await server?.close(force: true);
      await _wifi.stop();
      rethrow;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final invite = _invite;
    if (invite == null || !_authorized(request, invite.token)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    try {
      if (request.method == 'POST' && request.uri.path == '/complete') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        unawaited(stopSharing());
        return;
      }
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/manifest') {
        final manifest = <Map<String, Object>>[];
        for (var index = 0; index < _files.length; index++) {
          final file = _files[index];
          final digest = await sha256.bind(file.openRead()).first;
          manifest.add({
            'id': index,
            'name': _displayName(_relativePaths[index]),
            'relativePath': _relativePaths[index],
            'size': await file.length(),
            'sha256': digest.toString(),
          });
        }
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.write(jsonEncode({'version': 1, 'files': manifest}));
        await request.response.close();
        return;
      }
      if (request.uri.path == '/download') {
        final id = int.tryParse(request.uri.queryParameters['id'] ?? '');
        if (id == null || id < 0 || id >= _files.length) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final file = _files[id];
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final length = await file.length();
        final range = request.headers.value(HttpHeaders.rangeHeader);
        var offset = 0;
        if (range != null) {
          final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range.trim());
          if (match == null) {
            request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */' + length.toString());
            await request.response.close();
            return;
          }
          offset = int.parse(match.group(1)!);
          if (offset >= length) {
            request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */' + length.toString());
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes ' + offset.toString() + '-' + (length - 1).toString() + '/' + length.toString(),
          );
        } else {
          request.response.statusCode = HttpStatus.ok;
        }
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.contentType = ContentType.binary;
        request.response.headers.contentLength = length - offset;
        request.response.headers.set('Cache-Control', 'no-store');
        await request.response.addStream(file.openRead(offset));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (error) {
      debugPrint('Plazma request failed: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<List<SharedLocalFile>> joinAndList(PlazmaConnectionInvite invite) async {
    await _wifi.join(invite);
    await _startForegroundService();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(_endpoint(invite, '/manifest'));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Could not read the sender file list (HTTP ${response.statusCode}).');
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['files'] is! List) {
        throw const FormatException('The sender returned an unsupported file list.');
      }
      return (decoded['files'] as List)
          .whereType<Map>()
          .map((item) => SharedLocalFile.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAll({
    required PlazmaConnectionInvite invite,
    required List<SharedLocalFile> files,
    required Directory destination,
    required void Function(LocalTransferProgress progress) onProgress,
  }) async {
    await destination.create(recursive: true);
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);
    var totalBytes = 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      for (final item in files) {
        final relative = _safeRelativePath(item.relativePath);
        final target = File('${destination.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
        await target.parent.create(recursive: true);
        if (await target.exists()) {
          final existingSize = await target.length();
          final existingDigest = await sha256.bind(target.openRead()).first;
          if (existingSize == item.size && existingDigest.toString() == item.sha256) {
            totalBytes += item.size;
            onProgress(LocalTransferProgress(
              fileName: item.name,
              fileBytes: item.size,
              fileSize: item.size,
              totalBytes: totalBytes,
              totalSize: totalSize,
            ));
            continue;
          }
          throw FileSystemException('A different file with this name already exists.', target.path);
        }
        final partial = File('${target.path}.plazma-partial');
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset > item.size) {
          await partial.delete();
          offset = 0;
        }
        if (offset == item.size && offset > 0) {
          final digest = await sha256.bind(partial.openRead()).first;
          if (digest.toString() == item.sha256) {
            await partial.rename(target.path);
            totalBytes += item.size;
            onProgress(LocalTransferProgress(
              fileName: item.name,
              fileBytes: item.size,
              fileSize: item.size,
              totalBytes: totalBytes,
              totalSize: totalSize,
            ));
            continue;
          }
          await partial.delete();
          offset = 0;
        }
        final request = await client.getUrl(
          _endpoint(invite, '/download', {'id': item.id.toString()}),
        );
        if (offset > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        final response = await request.close().timeout(const Duration(seconds: 30));
        final expectedStatus = offset > 0 ? HttpStatus.partialContent : HttpStatus.ok;
        if (response.statusCode != expectedStatus) {
          throw HttpException(
            'Download could not resume for ${item.name} (HTTP ${response.statusCode}).',
          );
        }
        final sink = partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
        var fileBytes = offset;
        totalBytes += offset;
        onProgress(LocalTransferProgress(
          fileName: item.name,
          fileBytes: fileBytes,
          fileSize: item.size,
          totalBytes: totalBytes,
          totalSize: totalSize,
        ));
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            fileBytes += chunk.length;
            totalBytes += chunk.length;
            onProgress(LocalTransferProgress(
              fileName: item.name,
              fileBytes: fileBytes,
              fileSize: item.size,
              totalBytes: totalBytes,
              totalSize: totalSize,
            ));
          }
          await sink.flush();
          await sink.close();
          final receivedDigest = await sha256.bind(partial.openRead()).first;
          if (fileBytes != item.size || receivedDigest.toString() != item.sha256) {
            await partial.delete();
            throw FileSystemException(
              'The received file failed its size or SHA-256 integrity check.',
              partial.path,
            );
          }
          await partial.rename(target.path);
        } catch (_) {
          await sink.close();
          rethrow;
        }
      }
      final completeRequest = await client.postUrl(_endpoint(invite, '/complete'));
      final completeResponse = await completeRequest.close().timeout(const Duration(seconds: 10));
      if (completeResponse.statusCode != HttpStatus.ok) {
        throw HttpException('The sender did not acknowledge transfer completion.');
      }
      await completeResponse.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Uri _endpoint(PlazmaConnectionInvite invite, String path, [Map<String, String>? extra]) {
    return Uri(
      scheme: 'http',
      host: invite.host,
      port: invite.port,
      path: path,
      queryParameters: {'token': invite.token, ...?extra},
    );
  }

  bool _authorized(HttpRequest request, String token) {
    final supplied = request.uri.queryParameters['token'];
    if (supplied == null || supplied.length != token.length) return false;
    var difference = 0;
    for (var i = 0; i < token.length; i++) {
      difference |= supplied.codeUnitAt(i) ^ token.codeUnitAt(i);
    }
    return difference == 0;
  }

  String _safeRelativePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw const FormatException('Unsafe file path received.');
    }
    return normalized;
  }

  String _displayName(String path) => path.split('/').last;

  Future<void> stopSharing() async {
    final server = _server;
    _server = null;
    _invite = null;
    _files = const [];
    _relativePaths = const [];
    await server?.close(force: true);
    await _wifi.stop();
    await stopForegroundService();
  }

  Future<void> disconnect() async {
    await _wifi.disconnect();
    await stopForegroundService();
  }
}
