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
import 'transfer_queue.dart';

class SharedLocalFile {
  const SharedLocalFile({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.size,
    required this.sha256,
    this.status = 'waiting',
    this.bytesTransferred = 0,
    this.type = 'file',
  });

  final int id;
  final String name;
  final String relativePath;
  final int size;
  final String sha256;
  final String status;
  final int bytesTransferred;
  final String type;

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
      status: json['status'] as String? ?? 'waiting',
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
      type: json['type'] as String? ?? 'file',
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

  double get fraction => totalSize == 0 ? 1 : (totalBytes / totalSize).clamp(0.0, 1.0);
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
  Future<void> _roomMutationTail = Future<void>.value();
  List<File> _files = const [];
  List<Map<String, Object>> _manifest = const [];
  List<SharedLocalFile> _joinedManifest = const [];
  final ValueNotifier<List<SharedLocalFile>> roomFiles = ValueNotifier(const []);
  final ReceiverQueueStatusRegistry _receiverQueueStatuses = ReceiverQueueStatusRegistry();
  int _manifestRevision = 0;
  Completer<void>? _manifestChanged;
  PlazmaConnectionInvite? _invite;
  Future<void> Function()? _onTransferCompleted;
  RoomRegistry? _room;
  String? _joinedDeviceId;
  PlazmaConnectionInvite? _joinedInvite;

  List<RoomDevice> get roomMembers => _room?.members ?? const [];
  int get joinedDeviceCount => _room?.receiverCount ?? 0;
  int get completedDeviceCount => _room?.completedCount ?? 0;

  PlazmaConnectionInvite? get invite => _invite;
  PlazmaConnectionInvite? get joinedInvite => _joinedInvite;
  bool get isSharing => _server != null;

  void _bumpManifestRevision() {
    _manifestRevision++;
    _publishRoomFiles();
    final changed = _manifestChanged;
    if (changed != null && !changed.isCompleted) changed.complete();
    _manifestChanged = Completer<void>();
  }

  void _publishRoomFiles() {
    if (_server != null) {
      roomFiles.value = List.unmodifiable(_manifest.map((entry) =>
        SharedLocalFile.fromJson(Map<String, dynamic>.from(entry))).toList());
    } else {
      roomFiles.value = List.unmodifiable(_joinedManifest);
    }
  }

  Future<T> _serializeRoomMutation<T>(Future<T> Function() action) {
    final operation = _roomMutationTail.then((_) => action());
    _roomMutationTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<PlazmaConnectionInvite> startSharing({
    required List<File> files,
    required List<String> relativePaths,
    Future<void> Function()? onTransferCompleted,
  }) {
    return _serializeRoomMutation(() async {
      // Two category tabs can be tapped almost simultaneously. The second
      // request must append to the room created by the first, never replace it.
      if (_server != null && _invite != null) {
        await _addFilesInternal(files: files, relativePaths: relativePaths);
        return _invite!;
      }
      return _startSharingInternal(
        files: files,
        relativePaths: relativePaths,
        onTransferCompleted: onTransferCompleted,
      );
    });
  }

  Future<PlazmaConnectionInvite> _startSharingInternal({
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
    final seenPaths = <String>{};
    for (var i = 0; i < files.length; i++) {
      final stat = await files[i].stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final path = _safeRelativePath(relativePaths[i]);
      if (!seenPaths.add(path)) continue;
      checkedFiles.add(files[i]);
      checkedPaths.add(path);
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
        'status': 'waiting',
        'bytesTransferred': 0,
        'type': _itemTypeForPath(checkedPaths[index]),
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
      _manifestRevision = 1;
      _manifestChanged = Completer<void>();
      _invite = invite;
      _room = RoomRegistry(roomId: roomId);
      _onTransferCompleted = onTransferCompleted;
      _server = server;
      _publishRoomFiles();
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
  }) {
    return _serializeRoomMutation(
      () => _addFilesInternal(files: files, relativePaths: relativePaths),
    );
  }

  Future<void> _addFilesInternal({
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
    final seenPaths = _manifest
        .map((entry) => entry['relativePath'] as String)
        .toSet();
    for (var i = 0; i < files.length; i++) {
      final stat = await files[i].stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final path = _safeRelativePath(relativePaths[i]);
      if (!seenPaths.add(path)) continue;
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
        'status': 'waiting',
        'bytesTransferred': 0,
        'type': _itemTypeForPath(nextPaths[i]),
      });
    }
    if (additions.isNotEmpty) {
      _files = [..._files, ...nextFiles];
      _manifest = [..._manifest, ...additions];
      _bumpManifestRevision();
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
      if (request.method == 'POST' && request.uri.path == '/queue-status') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        final id = decoded is Map ? decoded['id'] : null;
        final status = decoded is Map ? decoded['status'] : null;
        final bytes = decoded is Map ? decoded['bytesTransferred'] : null;
        if (id is! int || status is! String || bytes is! int || id < 0 || id >= _manifest.length ||
            !{'waiting', 'sending', 'done', 'failed', 'cancelled'}.contains(status)) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final currentStatus = _manifest[id]['status'] as String? ?? 'waiting';
        final deviceId = decoded is Map ? decoded['deviceId'] : null;
        final receiverCanUpdate = deviceId is! String ||
            _receiverQueueStatuses.update(deviceId, id, status);
        if (currentStatus == 'cancelled' || !receiverCanUpdate) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'status': 'cancelled'}));
          await request.response.close();
          return;
        }
        // A receiver's cancellation is local to that receiver. Host-side
        // cancellation remains in the shared manifest and stops every receiver.
        if (status != 'cancelled') {
          _setQueueStatus(id, status, bytes, decoded is Map ? decoded['error'] as String? : null);
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': status}));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/complete') {
        // Do not acknowledge a receiver while new room items are still waiting.
        // The receiver will refresh the manifest and drain those additions.
        final waitingCount = _manifest.where(
          (item) => item['status'] == 'waiting',
        ).length;
        if (waitingCount > 0) {
          request.response.statusCode = HttpStatus.conflict;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'pendingCount': waitingCount,
            'revision': _manifestRevision,
          }));
          await request.response.close();
          return;
        }
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
        if (deviceId is String) { _room?.leave(deviceId); _receiverQueueStatuses.removeDevice(deviceId); }
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
        // Receivers can long-poll the room revision. A sender adding items
        // wakes every waiting receiver without requiring a room rejoin.
        final since = int.tryParse(request.uri.queryParameters['since'] ?? '');
        if (since != null && since == _manifestRevision) {
          final changed = _manifestChanged;
          if (changed != null && !changed.isCompleted) {
            try {
              await changed.future.timeout(const Duration(seconds: 20));
            } on TimeoutException {
              // A timeout is a heartbeat; the client simply rechecks.
            }
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.write(jsonEncode({
          'version': 1,
          'revision': _manifestRevision,
          'files': _manifest,
        }));
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
        if ((_manifest[id]['status'] as String? ?? 'waiting') == 'cancelled') {
          request.response.statusCode = HttpStatus.gone;
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

  void _setQueueStatus(int id, String status, int bytesTransferred, [String? error]) {
    if (id < 0 || id >= _manifest.length) return;
    final current = _manifest[id];
    if (current['status'] == 'cancelled' && status != 'cancelled') return;
    final updated = Map<String, Object>.from(current);
    updated['status'] = status;
    updated['bytesTransferred'] = bytesTransferred.clamp(0, updated['size'] as int).toInt();
    if (status == 'waiting') updated.remove('error');
    if (error != null) updated['error'] = error;
    _manifest = [..._manifest]..[id] = updated;
    _bumpManifestRevision();
  }

  void _updateJoinedQueueStatus(int id, String status, int bytesTransferred) {
    _joinedManifest = _joinedManifest.map((item) {
      if (item.id != id) return item;
      return SharedLocalFile(
        id: item.id,
        name: item.name,
        relativePath: item.relativePath,
        size: item.size,
        sha256: item.sha256,
        status: status,
        bytesTransferred: bytesTransferred.clamp(0, item.size),
        type: item.type,
      );
    }).toList();
    _publishRoomFiles();
  }

  Future<void> cancelQueuedItem(int id) async {
    if (_server != null) {
      if (id >= 0 && id < _manifest.length) {
        final status = _manifest[id]['status'] as String? ?? 'waiting';
        if (status == 'waiting' || status == 'sending') _setQueueStatus(id, 'cancelled', _manifest[id]['bytesTransferred'] as int? ?? 0);
      }
    } else if (_joinedInvite != null && id >= 0 && id < _joinedManifest.length) {
      final bytes = _joinedManifest[id].bytesTransferred;
      final status = await _postQueueStatus(_joinedInvite!, id, 'cancelled', bytes);
      if (status == 'cancelled') _updateJoinedQueueStatus(id, 'cancelled', bytes);
    }
  }

  Future<void> cancelAllQueuedItems() async {
    if (_server != null) {
      var changed = false;
      final next = <Map<String, Object>>[];
      for (final item in _manifest) {
        final status = item['status'] as String? ?? 'waiting';
        if (status == 'waiting' || status == 'sending') { next.add({...item, 'status': 'cancelled'}); changed = true; }
        else { next.add(item); }
      }
      if (changed) { _manifest = next; _bumpManifestRevision(); }
    } else if (_joinedInvite != null) {
      for (final item in _joinedManifest) {
        if (item.status == 'waiting' || item.status == 'sending') {
          final status = await _postQueueStatus(_joinedInvite!, item.id, 'cancelled', item.bytesTransferred);
          if (status == 'cancelled') {
            _updateJoinedQueueStatus(item.id, 'cancelled', item.bytesTransferred);
          }
        }
      }
    }
  }

  Future<void> retryFailedQueueItems() async {
    if (_server != null) {
      var changed = false;
      final next = <Map<String, Object>>[];
      for (final item in _manifest) {
        if (item['status'] == 'failed') { next.add({...item, 'status': 'waiting', 'bytesTransferred': 0}..remove('error')); changed = true; }
        else { next.add(item); }
      }
      if (changed) { _manifest = next; _bumpManifestRevision(); }
    } else if (_joinedInvite != null) {
      for (final item in _joinedManifest) {
        if (item.status == 'failed') {
          final status = await _postQueueStatus(_joinedInvite!, item.id, 'waiting', 0);
          if (status == 'waiting') _updateJoinedQueueStatus(item.id, 'waiting', 0);
        }
      }
    }
  }

  Future<String?> _postQueueStatus(PlazmaConnectionInvite invite, int id, String status, int bytes, {String? error, HttpClient? client}) async {
    final ownsClient = client == null;
    final httpClient = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 5));
    try {
      final request = await httpClient.postUrl(_endpoint(invite, '/queue-status'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'id': id, 'status': status, 'bytesTransferred': bytes, if (_joinedDeviceId != null) 'deviceId': _joinedDeviceId, if (error != null) 'error': error}));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      return decoded is Map ? decoded['status'] as String? : null;
    } catch (_) { return null; }
    finally { if (ownsClient) httpClient.close(force: true); }
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
      _joinedManifest = (decoded['files'] as List)
          .whereType<Map>()
          .map((item) => SharedLocalFile.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      _publishRoomFiles();
      return _joinedManifest;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<SharedLocalFile>> refreshManifest(PlazmaConnectionInvite invite) async {
    final snapshot = await _fetchManifest(invite);
    _joinedManifest = snapshot.files;
    _publishRoomFiles();
    return snapshot.files;
  }

  /// Emits the current room manifest and then waits for live additions.
  /// The server holds each request until its manifest revision changes, so
  /// receivers stay current without repeatedly downloading the whole list.
  Stream<List<SharedLocalFile>> watchManifest(PlazmaConnectionInvite invite) async* {
    var revision = -1;
    while (_joinedInvite == invite && _joinedDeviceId != null) {
      final snapshot = await _fetchManifest(invite, since: revision);
      if (snapshot.revision != revision) {
        revision = snapshot.revision;
        _joinedManifest = snapshot.files;
        _publishRoomFiles();
        yield snapshot.files;
      }
    }
  }

  Future<({int revision, List<SharedLocalFile> files})> _fetchManifest(
    PlazmaConnectionInvite invite, {int? since}
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(_endpoint(invite, '/manifest', {
        if (since != null && since >= 0) 'since': since.toString(),
      }));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Could not refresh the shared item list (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1 || decoded['files'] is! List) {
        throw const FormatException('The sender returned an unsupported file list.');
      }
      final revision = decoded['revision'] as int? ?? 0;
      final files = (decoded['files'] as List)
          .whereType<Map>()
          .map((item) => SharedLocalFile.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      return (revision: revision, files: files);
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
    var totalSize = files.fold<int>(0, (sum, file) => sum + file.size);
    var totalBytes = 0;
    var hadFailure = false;
    var wasCancelled = false;
    var queueRefreshAttempts = 0;
    var pendingFiles = List<SharedLocalFile>.from(files);
    final processedIds = <int>{};
    final knownIds = files.map((item) => item.id).toSet();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      while (true) {
      for (final item in pendingFiles) {
        if (!processedIds.add(item.id)) continue;
        if (item.status == 'cancelled') {
          wasCancelled = true;
          continue;
        }
        var fileBytes = item.bytesTransferred;
        try {
          final initialStatus = await _postQueueStatus(
            invite, item.id, 'sending', fileBytes, client: client,
          );
          if (initialStatus == 'cancelled') {
            wasCancelled = true;
            continue;
          }
          final relative = _safeRelativePath(item.relativePath);
          final target = File(
            '${destination.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
          );
          await target.parent.create(recursive: true);
          if (await target.exists()) {
            final existingSize = await target.length();
            final existingDigest = await sha256.bind(target.openRead()).first;
            if (existingSize == item.size && existingDigest.toString() == item.sha256) {
              totalBytes += item.size;
              final finalStatus = await _postQueueStatus(
                invite, item.id, 'done', item.size, client: client,
              );
              if (finalStatus == 'cancelled') {
                wasCancelled = true;
                continue;
              }
              onProgress(LocalTransferProgress(
                fileName: item.name, fileBytes: item.size, fileSize: item.size,
                totalBytes: totalBytes, totalSize: totalSize,
              ));
              continue;
            }
            throw FileSystemException(
              'A different file with this name already exists.', target.path,
            );
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
              final finalStatus = await _postQueueStatus(
                invite, item.id, 'done', item.size, client: client,
              );
              if (finalStatus == 'cancelled') {
                wasCancelled = true;
                continue;
              }
              onProgress(LocalTransferProgress(
                fileName: item.name, fileBytes: item.size, fileSize: item.size,
                totalBytes: totalBytes, totalSize: totalSize,
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
            await response.drain<void>();
            throw HttpException(
              offset > 0
                ? 'Download could not resume for ${item.name} (HTTP ${response.statusCode}).'
                : 'Download failed for ${item.name} (HTTP ${response.statusCode}).',
            );
          }
          final sink = partial.openWrite(
            mode: offset > 0 ? FileMode.append : FileMode.write,
          );
          fileBytes = offset;
          var lastQueueUpdate = offset;
          totalBytes += offset;
          onProgress(LocalTransferProgress(
            fileName: item.name, fileBytes: fileBytes, fileSize: item.size,
            totalBytes: totalBytes, totalSize: totalSize,
          ));
          try {
            await for (final chunk in response) {
              sink.add(chunk);
              fileBytes += chunk.length;
              totalBytes += chunk.length;
              onProgress(LocalTransferProgress(
                fileName: item.name, fileBytes: fileBytes, fileSize: item.size,
                totalBytes: totalBytes, totalSize: totalSize,
              ));
              if (fileBytes - lastQueueUpdate >= 16 * 1024 * 1024) {
                final status = await _postQueueStatus(
                  invite, item.id, 'sending', fileBytes, client: client,
                );
                if (status == 'cancelled') {
                  throw StateError('Transfer cancelled by sender.');
                }
                lastQueueUpdate = fileBytes;
              }
            }
            await sink.flush();
            await sink.close();
          } catch (_) {
            await sink.close();
            rethrow;
          }
          final receivedDigest = await sha256.bind(partial.openRead()).first;
          if (fileBytes != item.size || receivedDigest.toString() != item.sha256) {
            await partial.delete();
            throw FileSystemException(
              'The received file failed its size or SHA-256 integrity check.',
              partial.path,
            );
          }
          await partial.rename(target.path);
          final finalStatus = await _postQueueStatus(
            invite, item.id, 'done', item.size, client: client,
          );
          if (finalStatus == 'cancelled') {
            wasCancelled = true;
            continue;
          }
        } catch (error) {
          final cancelled = error.toString().toLowerCase().contains('cancelled');
          await _postQueueStatus(
            invite,
            item.id,
            cancelled ? 'cancelled' : 'failed',
            fileBytes,
            error: error.toString(),
            client: client,
          );
          if (cancelled) {
            wasCancelled = true;
          } else {
            hadFailure = true;
          }
          // A failed item must not block the remaining room queue.
          continue;
        }
      }
      if (hadFailure || wasCancelled) {
        throw StateError(
          hadFailure
            ? 'Some items failed. Retry failed items from the room queue.'
            : 'One or more items were cancelled.',
        );
      }
      final completeRequest = await client.postUrl(_endpoint(invite, '/complete', {
        if (_joinedDeviceId != null) 'deviceId': _joinedDeviceId!,
      }));
      final completeResponse = await completeRequest.close().timeout(const Duration(seconds: 10));
      if (completeResponse.statusCode == HttpStatus.conflict) {
        await completeResponse.drain<void>();
        final snapshot = await _fetchManifest(invite);
        _joinedManifest = snapshot.files;
        _publishRoomFiles();
        pendingFiles = snapshot.files.where((item) => item.status == 'waiting').toList();
        if (pendingFiles.isEmpty || ++queueRefreshAttempts > 20) {
          throw StateError('The room queue changed but could not be acknowledged. Refresh and retry.');
        }
        for (final item in pendingFiles) {
          processedIds.remove(item.id);
          if (knownIds.add(item.id)) totalSize += item.size;
        }
        continue;
      }
      if (completeResponse.statusCode != HttpStatus.ok) {
        await completeResponse.drain<void>();
        throw HttpException('The sender did not acknowledge transfer completion.');
      }
      await completeResponse.drain<void>();
      break;
      }
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

  String _itemTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (['.apk', '.aab', '.exe', '.msi', '.msix', '.appimage', '.deb', '.rpm', '.dmg', '.pkg'].any(lower.endsWith)) return 'app';
    if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'].any(lower.endsWith)) return 'image';
    if (['.mp4', '.m4v', '.mov', '.mkv', '.webm', '.avi', '.3gp'].any(lower.endsWith)) return 'video';
    if (['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.wma'].any(lower.endsWith)) return 'music';
    return 'file';
  }
  String _displayName(String path) => path.split('/').last;

  Future<void> stopSharing() => _serializeRoomMutation(_stopSharingInternal);

  Future<void> _stopSharingInternal() async {
    final server = _server;
    _server = null;
    _invite = null;
    _onTransferCompleted = null;
    _files = const [];
    _manifest = const [];
    _joinedManifest = const [];
    _receiverQueueStatuses.clear();
    _manifestRevision = 0;
    _publishRoomFiles();
    final changed = _manifestChanged;
    if (changed != null && !changed.isCompleted) changed.complete();
    _manifestChanged = null;
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
    _joinedManifest = const [];
    _publishRoomFiles();
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
