import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/android_wifi_session_service.dart';
import '../rooms/room_id.dart';
import '../rooms/room_registry.dart';
import 'transfer_overlay_controller.dart';

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

/// Direct device-to-device sharing over the existing Wi-Fi/LAN network.
/// The sender hosts file metadata and download endpoints; recipients join
/// using a QR invite and download directly over the local network.
class XenderLocalTransferService {
  XenderLocalTransferService._();
  static final XenderLocalTransferService _shared = XenderLocalTransferService._();
  factory XenderLocalTransferService() => _shared;

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
  List<Map<String, Object>> _manifest = const [];
  PlazmaConnectionInvite? _invite;
  Future<void> Function()? _onTransferCompleted;
  RoomRegistry? _room;
  String? _joinedDeviceId;
  PlazmaConnectionInvite? _joinedInvite;

  List<RoomDevice> get roomMembers => _room?.members ?? const [];
  int get joinedDeviceCount => _room?.receiverCount ?? 0;
  int get completedDeviceCount => _room?.completedCount ?? 0;

  PlazmaConnectionInvite? get invite => _invite;
  bool get isSharing => _server != null;

  Future<PlazmaConnectionInvite> startSharing({
    required List<File> files,
    required List<String> relativePaths,
    Future<void> Function()? onTransferCompleted,
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

    // Prepare APK checksums before displaying the QR code. Hashing large APKs
    // during the receiver's first HTTP request can exceed its connection timeout.
    final manifest = <Map<String, Object>>[];
    for (var index = 0; index < checkedFiles.length; index++) {
      final file = checkedFiles[index];
      final digest = await sha256.bind(file.openRead()).first;
      manifest.add({
        'id': index,
        'name': _displayName(checkedPaths[index]),
        'relativePath': checkedPaths[index],
        'size': await file.length(),
        'sha256': digest.toString(),
      });
    }

    // Use the Wi-Fi network already connected on every platform.
    // Plazma S must never create or join a hotspot.
    final token = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final roomId = RoomId.generate();
    final invite = PlazmaConnectionInvite(
      ssid: '',
      password: '',
      host: await _localIpv4Address(),
      port: 45454,
      token: token,
      roomId: roomId,
    );
    HttpServer? server;
    try {
      // Bind all IPv4 interfaces so phones and computers on the same LAN
      // can reach this host regardless of which Wi-Fi adapter is active.
      server = await HttpServer.bind(InternetAddress.anyIPv4, invite.port);
      _files = checkedFiles;
      _manifest = manifest;
      _invite = invite;
      _room = RoomRegistry(roomId: roomId);
      _onTransferCompleted = onTransferCompleted;
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
      rethrow;
    }
  }

  /// Adds more files to the currently hosted room without changing its QR code.
  Future<void> addFiles({
    required List<File> files,
    required List<String> relativePaths,
  }) async {
    if (_server == null || _invite == null) {
      throw StateError('There is no active sharing room.');
    }
    if (files.isEmpty || files.length != relativePaths.length) {
      throw ArgumentError('Select at least one valid file to add.');
    }
    final nextFiles = <File>[];
    final nextPaths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final stat = await files[i].stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final path = _safeRelativePath(relativePaths[i]);
      if (_manifest.any((entry) => entry['relativePath'] == path)) continue;
      nextFiles.add(files[i]);
      nextPaths.add(path);
    }
    final additions = <Map<String, Object>>[];
    for (var i = 0; i < nextFiles.length; i++) {
      final file = nextFiles[i];
      final digest = await sha256.bind(file.openRead()).first;
      additions.add({
        'id': _files.length + i,
        'name': _displayName(nextPaths[i]),
        'relativePath': nextPaths[i],
        'size': await file.length(),
        'sha256': digest.toString(),
      });
    }
    _files = [..._files, ...nextFiles];
    _manifest = [..._manifest, ...additions];
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
        final deviceId = request.uri.queryParameters['deviceId'];
        final wasFirst = (_room?.completedCount ?? 0) == 0;
        final marked = deviceId != null && (_room?.markCompleted(deviceId) ?? false);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        final onCompleted = marked && wasFirst ? _onTransferCompleted : null;
        if (onCompleted != null) {
          try {
            await onCompleted();
          } catch (error) {
            debugPrint('Could not record completed outgoing transfer: $error');
          }
        }
        // Keep the room open until its host explicitly stops sharing.
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/join') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final deviceId = decoded['deviceId'];
        final deviceName = decoded['deviceName'];
        final platform = decoded['platform'];
        if (deviceId is! String || deviceName is! String || platform is! String ||
            !(_room?.join(deviceId: deviceId, deviceName: deviceName, platform: platform) ?? false)) {
          request.response.statusCode = HttpStatus.conflict;
          request.response.write('Room is full or the device details are invalid.');
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'roomId': _room?.roomId,
          'joinedCount': joinedDeviceCount,
          'maxMembers': 8,
        }));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/leave') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        final deviceId = decoded is Map ? decoded['deviceId'] : null;
        if (deviceId is String) _room?.leave(deviceId);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/room') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'roomId': _room?.roomId,
          'joinedCount': joinedDeviceCount,
          'maxMembers': 8,
          'completedCount': completedDeviceCount,
          'members': roomMembers.map((member) => member.toJson()).toList(),
        }));
        await request.response.close();
        return;
      }
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/manifest') {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.write(jsonEncode({'version': 1, 'files': _manifest}));
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
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
            await request.response.close();
            return;
          }
          offset = int.parse(match.group(1)!);
          if (offset >= length) {
            request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $offset-${length - 1}/$length',
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
    // Receivers must already be connected to the same Wi-Fi/LAN.
    await _startForegroundService();
    final deviceId = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _joinedDeviceId = deviceId;
    _joinedInvite = invite;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final joinRequest = await client.postUrl(_endpoint(invite, '/join'));
      joinRequest.headers.contentType = ContentType.json;
      joinRequest.write(jsonEncode({
        'deviceId': deviceId,
        'deviceName': Platform.localHostname,
        'platform': Platform.operatingSystem,
      }));
      final joinResponse = await joinRequest.close().timeout(const Duration(seconds: 15));
      if (joinResponse.statusCode != HttpStatus.ok) {
        final reason = await utf8.decoder.bind(joinResponse).join();
        throw HttpException(reason.isEmpty ? 'Could not join room.' : reason);
      }
      await joinResponse.drain<void>();
      final request = await client.getUrl(_endpoint(invite, '/manifest'));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 60));
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

  Future<List<SharedLocalFile>> refreshManifest(PlazmaConnectionInvite invite) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(_endpoint(invite, '/manifest'));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Could not refresh the shared item list (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1 || decoded['files'] is! List) {
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
      final completeRequest = await client.postUrl(_endpoint(invite, '/complete', {
        if (_joinedDeviceId != null) 'deviceId': _joinedDeviceId!,
      }));
      final completeResponse = await completeRequest.close().timeout(const Duration(seconds: 10));
      if (completeResponse.statusCode != HttpStatus.ok) {
        throw HttpException('The sender did not acknowledge transfer completion.');
      }
      await completeResponse.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _localIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final candidates = <({int priority, String address})>[];
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      // Avoid VPN, virtual-machine, container, Wi-Fi Direct and cellular
      // interfaces when advertising a room address to devices on the LAN.
      if (RegExp(r'tun|vpn|wireguard|wg|utun|tailscale|docker|veth|bridge|vmnet|rmnet|p2p').hasMatch(name)) {
        continue;
      }
      final priority = name.contains('wlan') || name.contains('wifi') ||
              name.contains('wi-fi') || name == 'en0' || name.startsWith('wl')
          ? 0
          : name.contains('ethernet') || name.startsWith('eth') ||
                  name.startsWith('enp') || name.startsWith('eno')
              ? 1
              : 2;
      for (final address in interface.addresses) {
        final parts = address.address.split('.').map(int.tryParse).toList();
        if (parts.length != 4 || parts.any((part) => part == null)) continue;
        final a = parts[0]!;
        final b = parts[1]!;
        final isPrivate = a == 10 ||
            (a == 192 && b == 168) ||
            (a == 172 && b >= 16 && b <= 31);
        if (isPrivate) candidates.add((priority: priority, address: address.address));
      }
    }
    candidates.sort((a, b) => a.priority.compareTo(b.priority));
    if (candidates.isNotEmpty) return candidates.first.address;
    throw const SocketException(
      'No private IPv4 address found. Connect this device to the same Wi-Fi network as the other devices.',
    );
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
    _onTransferCompleted = null;
    _files = const [];
    _manifest = const [];
    _room = null;
    await server?.close(force: true);
    TransferOverlayController.clear();
    await stopForegroundService();
  }

  Future<void> disconnect() async {
    final invite = _joinedInvite;
    final deviceId = _joinedDeviceId;
    _joinedInvite = null;
    _joinedDeviceId = null;
    if (invite != null && deviceId != null) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(_endpoint(invite, '/leave'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'deviceId': deviceId}));
        final response = await request.close().timeout(const Duration(seconds: 5));
        await response.drain<void>();
      } catch (_) {
        // The room may already have been closed by its host.
      } finally {
        client.close(force: true);
      }
    }
    // Plazma S never changes the device's Wi-Fi connection.
    await stopForegroundService();
  }
}
