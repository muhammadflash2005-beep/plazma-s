import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/android_wifi_session_service.dart';
import '../rooms/room_id.dart';
import '../rooms/room_registry.dart';
import 'transfer_history.dart';
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
  Directory? _lastDownloadDestination;
  void Function(LocalTransferProgress progress)? _lastDownloadProgress;
  bool _retryingFailedQueue = false;
  final Set<String> _recordedSentHistory = <String>{};
  final Set<String> _recordedReceivedHistory = <String>{};
  final Map<int, String> _finalSavedPaths = <int, String>{};

  List<RoomDevice> get roomMembers => _room?.members ?? const [];
  int get joinedDeviceCount => _room?.receiverCount ?? 0;
  int get completedDeviceCount => _room?.completedCount ?? 0;

  PlazmaConnectionInvite? get invite => _invite;
  PlazmaConnectionInvite? get joinedInvite => _joinedInvite;
  bool get isSharing => _server != null;
  bool get isReceiving => _joinedInvite != null && _server == null;

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
      _recordedSentHistory.clear();
      _recordedReceivedHistory.clear();
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
      if (request.method == 'POST' && request.uri.path == '/heartbeat') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        final deviceId = decoded is Map ? decoded['deviceId'] : null;
        final touched = deviceId is String && (_room?.heartbeat(deviceId) ?? false);
        request.response.statusCode = touched ? HttpStatus.ok : HttpStatus.forbidden;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'alive': touched}));
        await request.response.close();
        return;
      }
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
        final isJoinedReceiver = deviceId is String &&
            (_room?.members.any((member) => member.deviceId == deviceId) ?? false);
        if (currentStatus == 'cancelled' || !isJoinedReceiver ||
            !_receiverQueueStatuses.update(deviceId, id, status, bytes)) {
          request.response.statusCode = currentStatus == 'cancelled' ? HttpStatus.ok : HttpStatus.forbidden;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'status': 'cancelled'}));
          await request.response.close();
          return;
        }
        // Keep receiver progress isolated, then publish an aggregate across
        // every connected receiver. A single fast receiver cannot mark the
        // shared item done while another device is still downloading it.
        _refreshAggregateQueueStatus(id);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': status}));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/complete') {
        // Completion is acknowledged independently for each receiver. A
        // slower second phone must not hold the first phone at 100%.
        final deviceId = request.uri.queryParameters['deviceId'];
        if (deviceId == null ||
            !(_room?.members.any((member) => member.deviceId == deviceId) ?? false)) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        final pendingCount = List<int>.generate(_manifest.length, (index) => index)
            .where((id) {
              final status = _receiverQueueStatuses.statusFor(deviceId, id)?.status ?? 'waiting';
              return status != 'done' && status != 'cancelled';
            }).length;
        if (pendingCount > 0) {
          request.response.statusCode = HttpStatus.conflict;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'pendingCount': pendingCount,
            'revision': _manifestRevision,
          }));
          await request.response.close();
          return;
        }
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
        // A newly joined receiver starts at zero progress for every queue item.
        for (var itemId = 0; itemId < _manifest.length; itemId++) {
          _refreshAggregateQueueStatus(itemId);
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
        if (deviceId is String) {
          _room?.leave(deviceId);
          _receiverQueueStatuses.removeDevice(deviceId);
          for (var itemId = 0; itemId < _manifest.length; itemId++) {
            _refreshAggregateQueueStatus(itemId);
          }
        }
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
        final response = request.response;
        response.bufferOutput = false;
        response.persistentConnection = true;
        response.headers.contentType = ContentType.json;
        response.headers.set('Cache-Control', 'no-store');
        response.headers.set('Connection', 'keep-alive');
        await response.flush();
        if (since != null && since == _manifestRevision) {
          final changed = _manifestChanged;
          if (changed != null && !changed.isCompleted) {
            try {
              await changed.future.timeout(const Duration(seconds: 20));
            } on TimeoutException {
              // A quiet room is a normal heartbeat.
            }
          }
        }
        try {
          response.write(jsonEncode({
            'version': 1,
            'revision': _manifestRevision,
            'files': _manifest,
          }));
          await response.close();
        } on HttpException catch (error) {
          debugPrint('Plazma manifest client disconnected: $error');
        }
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

  void _refreshAggregateQueueStatus(int id) {
    if (id < 0 || id >= _manifest.length) return;
    final receivers = _room?.members ?? const <RoomDevice>[];
    final statuses = receivers
        .map((device) => _receiverQueueStatuses.statusFor(device.deviceId, id))
        .toList(growable: false);
    if (statuses.isEmpty) {
      _setQueueStatus(id, 'waiting', 0);
      return;
    }
    final totalBytes = _manifest[id]['size'] as int;
    final aggregateBytes = (statuses.fold<int>(
      0, (sum, item) => sum + (item?.bytesTransferred ?? 0)) / statuses.length).round();
    final values = statuses.map((item) => item?.status ?? 'waiting').toList();
    final String aggregateStatus;
    if (values.every((value) => value == 'done')) {
      aggregateStatus = 'done';
    } else if (values.every((value) => value == 'cancelled')) {
      aggregateStatus = 'cancelled';
    } else if (values.any((value) => value == 'sending')) {
      aggregateStatus = 'sending';
    } else if (values.any((value) => value == 'failed') &&
        values.every((value) => value == 'failed' || value == 'done' || value == 'cancelled')) {
      aggregateStatus = 'failed';
    } else if (values.every((value) => value == 'done' || value == 'cancelled')) {
      aggregateStatus = 'done';
    } else {
      aggregateStatus = 'waiting';
    }
    _setQueueStatus(id, aggregateStatus, aggregateBytes.clamp(0, totalBytes));
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
      return;
    }
    final invite = _joinedInvite;
    final destination = _lastDownloadDestination;
    final onProgress = _lastDownloadProgress;
    if (invite == null || _retryingFailedQueue) return;
    final failedIds = _joinedManifest.where((item) => item.status == 'failed')
        .map((item) => item.id).toSet();
    if (failedIds.isEmpty) return;

    for (final item in _joinedManifest.where((item) => failedIds.contains(item.id))) {
      if (item.status == 'failed') {
        final status = await _postQueueStatus(invite, item.id, 'waiting', 0);
        if (status == 'waiting') _updateJoinedQueueStatus(item.id, 'waiting', 0);
      }
    }

    // A retry must resume the receiver, not merely change the sender's queue
    // state. Reuse the last destination and progress callback from the active
    // category screen; if no download has been started on this device yet,
    // leave the items waiting for the normal Receive action.
    if (destination == null || onProgress == null) return;
    _retryingFailedQueue = true;
    try {
      final snapshot = await _fetchManifest(invite);
      _joinedManifest = _mergeReceiverManifest(snapshot.files);
      _publishRoomFiles();
      final retryItems = _joinedManifest.where((item) => failedIds.contains(item.id)).toList();
      if (retryItems.isNotEmpty) {
        await downloadAll(
          invite: invite,
          files: retryItems,
          destination: destination,
          onProgress: onProgress,
        );
      }
    } catch (error) {
      debugPrint('Plazma queue retry did not complete: $error');
    } finally {
      _retryingFailedQueue = false;
    }
  }

  Future<String?> _postQueueStatusReliable(
    PlazmaConnectionInvite invite, int id, String status, int bytes, {HttpClient? client}
  ) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final result = await _postQueueStatus(invite, id, status, bytes, client: client);
      if (result == status) {
        if (status == 'done') {
          final matches = _joinedManifest.where((item) => item.id == id);
          if (matches.isNotEmpty && _lastDownloadDestination != null) {
            final item = matches.first;
            final relative = _safeRelativePath(item.relativePath);
            final categoryFolder = switch (item.type) {
              'image' => 'Pictures/Plazma S',
              'video' => 'Movies/Plazma S',
              'music' => 'Music/Plazma S',
              'app' => 'Download/Plazma S',
              _ => 'Documents/Plazma S',
            };
            final target = File(_lastDownloadDestination!.path + Platform.pathSeparator +
                categoryFolder.replaceAll('/', Platform.pathSeparator) + Platform.pathSeparator +
                relative.replaceAll('/', Platform.pathSeparator));
            _updateJoinedQueueStatus(id, 'saved', item.size);
            if (item.type == 'app') {
              final package = relative.split('/').first;
              final packageItems = _joinedManifest.where((value) =>
                  value.type == 'app' && value.relativePath.startsWith('$package/')).toList();
              if (packageItems.isNotEmpty && packageItems.every((value) => value.status == 'saved') &&
                  _recordedReceivedHistory.add('app:$package')) {
                await TransferHistoryStore.add(
                  name: package, type: 'app', direction: 'received',
                  path: target.parent.path, bytes: packageItems.fold<int>(0, (sum, value) => sum + value.size),
                  peer: 'Nearby Plazma S device',
                );
              }
            } else if (_recordedReceivedHistory.add('item:$id')) {
              await TransferHistoryStore.add(
                name: item.name, type: item.type, direction: 'received',
                path: finalPath, bytes: item.size, peer: 'Nearby Plazma S device',
              );
            }
            debugPrint('Plazma receiver completion confirmed for item ' + id.toString());
          }
        }
        return result;
      }
      debugPrint('Plazma completion acknowledgement retry: ' + (attempt + 1).toString());
      await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt)));
    }
    throw TimeoutException('The sender did not acknowledge the saved file.', const Duration(seconds: 9));
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
    // A new room must never inherit a retry destination from an older room.
    _lastDownloadDestination = null;
    _lastDownloadProgress = null;
    _recordedReceivedHistory.clear();
    _finalSavedPaths.clear();
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
        'deviceName': await _deviceDisplayName(),
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
          .map((item) {
            final local = Map<String, dynamic>.from(item);
            local['status'] = 'waiting';
            return SharedLocalFile.fromJson(local);
          })
          .toList();
      _publishRoomFiles();
      return _joinedManifest;
    } finally {
      client.close(force: true);
    }
  }

  List<SharedLocalFile> _mergeReceiverManifest(List<SharedLocalFile> remote) {
    final previous = {for (final item in _joinedManifest) item.id: item};
    return remote.map((item) {
      final local = previous[item.id];
      var status = local?.status ?? 'waiting';
      var bytes = local?.bytesTransferred ?? 0;
      if (local?.status == 'failed' && item.status == 'waiting') {
        status = 'waiting';
        bytes = 0;
      }
      if (local == null) bytes = 0;
      return SharedLocalFile(
        id: item.id, name: item.name, relativePath: item.relativePath,
        size: item.size, sha256: item.sha256, status: status,
        bytesTransferred: bytes, type: item.type,
      );
    }).toList();
  }

  Future<List<SharedLocalFile>> refreshManifest(PlazmaConnectionInvite invite) async {
    final snapshot = await _fetchManifest(invite);
    _joinedManifest = _mergeReceiverManifest(snapshot.files);
    _publishRoomFiles();
    return _joinedManifest;
  }

  /// Emits the current room manifest and then waits for live additions.
  /// The server holds each request until its manifest revision changes, so
  /// receivers stay current without repeatedly downloading the whole list.
  Stream<List<SharedLocalFile>> watchManifest(PlazmaConnectionInvite invite) async* {
    var revision = -1;
    var failures = 0;
    while (_joinedInvite == invite && _joinedDeviceId != null) {
      try {
        await _sendHeartbeat(invite);
        final snapshot = await _fetchManifest(invite, since: revision);
        failures = 0;
        if (snapshot.revision != revision) {
          final previous = {for (final item in _joinedManifest) item.id: item};
          revision = snapshot.revision;
          _joinedManifest = _mergeReceiverManifest(snapshot.files);
          _publishRoomFiles();
          final restarted = snapshot.files.where((remote) =>
              previous[remote.id]?.status == 'failed' && remote.status == 'waiting').toList();
          if (restarted.isNotEmpty && _lastDownloadDestination != null &&
              _lastDownloadProgress != null && !_retryingFailedQueue) {
            _retryingFailedQueue = true;
            unawaited(downloadAll(
              invite: invite,
              files: restarted,
              destination: _lastDownloadDestination!,
              onProgress: _lastDownloadProgress!,
            ).whenComplete(() => _retryingFailedQueue = false));
          }
          yield _joinedManifest;
        }
      } catch (error) {
        failures++;
        debugPrint('Plazma manifest poll failed; retrying: $error');
        await Future<void>.delayed(Duration(seconds: min(15, 1 << min(failures - 1, 4))));
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
          .map((item) {
            final local = Map<String, dynamic>.from(item);
            local['status'] = 'waiting';
            return SharedLocalFile.fromJson(local);
          })
          .toList();
      return (revision: revision, files: files);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendHeartbeat(PlazmaConnectionInvite invite) async {
    final deviceId = _joinedDeviceId;
    if (deviceId == null) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(_endpoint(invite, '/heartbeat'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'deviceId': deviceId}));
      final response = await request.close().timeout(const Duration(seconds: 6));
      await response.drain<void>();
    } catch (error) {
      debugPrint('Plazma heartbeat missed; grace period remains active: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _persistReceivedFile(File file, SharedLocalFile item) async {
    if (!Platform.isAndroid) return file.path;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('plazma_auto_save_received') ?? true)) return file.path;
    try {
      final saved = await const MethodChannel('com.plazma.s/storage')
          .invokeMapMethod<String, dynamic>('saveReceivedFile', {
        'sourcePath': file.path,
        'name': item.name,
        'type': item.type,
      }).timeout(const Duration(seconds: 30));
      final path = saved?['path'];
      if (path is! String || path.isEmpty) {
        throw StateError('Android did not return the saved file location.');
      }
      debugPrint('Plazma MediaStore save complete: $path');
      return path;
    } catch (error) {
      debugPrint('Plazma MediaStore save failed: $error');
      rethrow;
    }
  }

  Future<void> downloadAll({
    required PlazmaConnectionInvite invite,
    required List<SharedLocalFile> files,
    required Directory destination,
    required void Function(LocalTransferProgress progress) onProgress,
  }) async {
    _lastDownloadDestination = destination;
    _lastDownloadProgress = onProgress;
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
        _updateJoinedQueueStatus(item.id, 'receiving', fileBytes);
        try {
          final initialStatus = await _postQueueStatus(
            invite, item.id, 'sending', fileBytes, client: client,
          );
          if (initialStatus == 'cancelled') {
            wasCancelled = true;
            continue;
          }
          final relative = _safeRelativePath(item.relativePath);
          final categoryFolder = switch (item.type) {
            'image' => 'Pictures/Plazma S',
            'video' => 'Movies/Plazma S',
            'music' => 'Music/Plazma S',
            'app' => 'Download/Plazma S',
            _ => 'Documents/Plazma S',
          };
          final target = File(
            '${destination.path}${Platform.pathSeparator}${categoryFolder.replaceAll('/', Platform.pathSeparator)}'
            '${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
          );
          await target.parent.create(recursive: true);
          if (await target.exists()) {
            final existingSize = await target.length();
            final existingDigest = await sha256.bind(target.openRead()).first;
            if (existingSize == item.size && existingDigest.toString() == item.sha256) {
              totalBytes += item.size;
              final finalStatus = await _postQueueStatusReliable(
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
              _finalSavedPaths[item.id] = await _persistReceivedFile(target, item);
              totalBytes += item.size;
              final finalStatus = await _postQueueStatusReliable(
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
          _finalSavedPaths[item.id] = await _persistReceivedFile(target, item);
          final finalStatus = await _postQueueStatusReliable(
            invite, item.id, 'done', item.size, client: client,
          );
          if (finalStatus == 'done') _updateJoinedQueueStatus(item.id, 'saved', item.size);
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
            ? 'Some files could not be received. Check Wi-Fi, then tap Retry failed in the room queue.'
            : 'One or more items were cancelled.',
        );
      }
      HttpClientResponse? completeResponse;
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          final completeRequest = await client.postUrl(_endpoint(invite, '/complete', {
            if (_joinedDeviceId != null) 'deviceId': _joinedDeviceId!,
          }));
          completeResponse = await completeRequest.close().timeout(const Duration(seconds: 8));
          break;
        } catch (error) {
          debugPrint('Plazma room completion acknowledgement retry: $error');
          await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        }
      }
      if (completeResponse == null) {
        throw TimeoutException('Files were saved, but the sender did not confirm completion. Reconnect and retry.', const Duration(seconds: 12));
      }
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

  Future<String> _deviceDisplayName() async {
    if (Platform.isAndroid) {
      try {
        final name = await const MethodChannel('com.plazma.s/device')
            .invokeMethod<String>('getDeviceName')
            .timeout(const Duration(seconds: 2));
        if (name != null && name.trim().isNotEmpty) return name.trim();
      } catch (error) {
        debugPrint('Plazma device name lookup unavailable: $error');
      }
    }
    final hostname = Platform.localHostname.trim();
    return hostname.isEmpty || hostname.toLowerCase() == 'localhost'
        ? 'Android device' : hostname;
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
    _lastDownloadDestination = null;
    _lastDownloadProgress = null;
    _retryingFailedQueue = false;
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
