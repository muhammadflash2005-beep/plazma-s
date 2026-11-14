import 'dart:async';
import 'dart:math';

import '../network/lan_tcp.dart';
import 'room_host.dart';
import 'room_id.dart';
import 'room_models.dart';

/// A QR invitation is a LAN locator plus a short-lived bearer credential.
/// The room ID alone is never accepted as proof of membership.
class RoomInvitation {
  const RoomInvitation({
    required this.roomId,
    required this.host,
    required this.port,
    required this.token,
  });

  final String roomId;
  final String host;
  final int port;
  final String token;

  Uri toUri() => Uri(
        scheme: 'plazmas',
        host: 'join',
        queryParameters: {
          'room': roomId,
          'host': host,
          'port': '$port',
          'token': token,
        },
      );

  static RoomInvitation? tryParse(Uri uri) {
    if (uri.scheme != 'plazmas' || uri.host != 'join') return null;
    final room = uri.queryParameters['room'];
    final host = uri.queryParameters['host'];
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final token = uri.queryParameters['token'];
    if (room == null ||
        !RoomId.isValid(room) ||
        host == null ||
        host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        token == null ||
        token.length < 32) {
      return null;
    }
    return RoomInvitation(roomId: room, host: host, port: port, token: token);
  }
}

enum RoomNetworkEventType { pending, joined, rejected, snapshot, disconnected }

class RoomNetworkEvent {
  const RoomNetworkEvent(this.type, {this.message, this.snapshot});

  final RoomNetworkEventType type;
  final String? message;
  final RoomSnapshot? snapshot;
}

/// LAN room signaling host. File payloads continue to use the transfer
/// transport; this service only handles room membership and state.
class RoomNetworkHost {
  RoomNetworkHost._({
    required this.room,
    required this.invitation,
    required this._server,
  });

  final RoomHost room;
  final RoomInvitation invitation;
  final LanTcpServer _server;
  final Map<String, TcpPeer> _peersByDevice = {};
  final Map<TcpPeer, String> _deviceByPeer = {};
  bool _closed = false;

  RoomSnapshot get snapshot => room.snapshot();

  static Future<RoomNetworkHost> start({
    required String hostDeviceId,
    required String hostDeviceName,
    required String hostPlatform,
    required String advertisedAddress,
    int port = 45454,
    int maxMembers = RoomHost.defaultMaxMembers,
    String? roomId,
  }) async {
    final id = roomId ?? RoomId.generate();
    final token = _newToken();
    final room = RoomHost.create(
      roomId: id,
      hostDeviceId: hostDeviceId,
      hostDeviceName: hostDeviceName,
      hostPlatform: hostPlatform,
      maxMembers: maxMembers,
    );
    late final RoomNetworkHost host;
    final server = LanTcpServer(
      onMessage: (peer, message) => host._handleMessage(peer, message),
      onPeerDisconnected: (peer) => host._handleDisconnect(peer),
    );
    await server.start(port: port);
    host = RoomNetworkHost._(
      room: room,
      invitation: RoomInvitation(
        roomId: id,
        host: advertisedAddress,
        port: server.port!,
        token: token,
      ),
      _server: server,
    );
    return host;
  }

  List<RoomMember> get pendingMembers => room.pendingMembers;

  Future<bool> approve(String deviceId) async {
    _ensureOpen();
    final peer = _peersByDevice[deviceId];
    if (peer == null || peer.isClosed || !room.approve(deviceId)) return false;
    await peer.send({
      'type': 'room.joined',
      'snapshot': _snapshotJson(room.snapshot()),
    });
    await _broadcastSnapshot();
    return true;
  }

  Future<bool> reject(String deviceId) async {
    _ensureOpen();
    final peer = _peersByDevice[deviceId];
    if (!room.reject(deviceId)) return false;
    _peersByDevice.remove(deviceId);
    if (peer != null) {
      _deviceByPeer.remove(peer);
      if (!peer.isClosed) {
        await peer.send({'type': 'room.rejected', 'reason': 'Host declined the request.'});
        await peer.close();
      }
    }
    return true;
  }

  Future<bool> kick(String deviceId) async {
    _ensureOpen();
    final peer = _peersByDevice.remove(deviceId);
    if (!room.kick(deviceId)) {
      if (peer != null) _peersByDevice[deviceId] = peer;
      return false;
    }
    if (peer != null) {
      _deviceByPeer.remove(peer);
      if (!peer.isClosed) {
        await peer.send({'type': 'room.rejected', 'reason': 'You were removed by the host.'});
        await peer.close();
      }
    }
    await _broadcastSnapshot();
    return true;
  }

  Future<void> setLocked(bool locked) async {
    _ensureOpen();
    room.setLocked(locked);
    await _broadcastSnapshot();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    room.close();
    await _server.close();
    _peersByDevice.clear();
    _deviceByPeer.clear();
  }

  Future<void> _handleMessage(TcpPeer peer, Map<String, Object?> message) async {
    if (_closed) return;
    if (message['type'] != 'room.join') {
      await peer.send({'type': 'room.rejected', 'reason': 'Unsupported room message.'});
      await peer.close();
      return;
    }

    final roomId = message['roomId'];
    final token = message['token'];
    final deviceId = message['deviceId'];
    final deviceName = message['deviceName'];
    final platform = message['platform'];
    if (roomId is! String ||
        token is! String ||
        deviceId is! String ||
        deviceName is! String ||
        platform is! String ||
        roomId != room.id ||
        !_constantTimeEquals(token, invitation.token)) {
      await peer.send({'type': 'room.rejected', 'reason': 'Invalid room invitation.'});
      await peer.close();
      return;
    }

    final accepted = room.requestJoin(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
    if (!accepted) {
      await peer.send({'type': 'room.rejected', 'reason': 'Room is full, locked, or request is invalid.'});
      await peer.close();
      return;
    }
    _peersByDevice[deviceId] = peer;
    _deviceByPeer[peer] = deviceId;
    await peer.send({'type': 'room.pending', 'roomId': room.id});
  }

  Future<void> _handleDisconnect(TcpPeer peer) async {
    final deviceId = _deviceByPeer.remove(peer);
    if (deviceId == null) return;
    _peersByDevice.remove(deviceId);
    if (room.pendingMembers.any((member) => member.deviceId == deviceId)) {
      room.reject(deviceId);
    } else {
      room.leave(deviceId);
      await _broadcastSnapshot();
    }
  }

  Future<void> _broadcastSnapshot() async {
    final payload = {
      'type': 'room.snapshot',
      'snapshot': _snapshotJson(room.snapshot()),
    };
    for (final peer in _peersByDevice.values.toList()) {
      if (!peer.isClosed) {
        try {
          await peer.send(payload);
        } catch (_) {
          // Disconnect handling removes peers whose sockets have closed.
        }
      }
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Room host is closed.');
  }
}

/// Client-side room signaling connection. A successful TCP connection only
/// means the invitation was presented; host approval is still required.
class RoomNetworkClient {
  RoomNetworkClient._(this._peer, this._events);

  final TcpPeer _peer;
  final StreamController<RoomNetworkEvent> _events;
  Stream<RoomNetworkEvent> get events => _events.stream;

  static Future<RoomNetworkClient> join({
    required RoomInvitation invitation,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final events = StreamController<RoomNetworkEvent>();
    final peer = await TcpPeer.connect(
      host: invitation.host,
      port: invitation.port,
      onMessage: (_, message) {
        final type = message['type'];
        if (type == 'room.pending') {
          events.add(const RoomNetworkEvent(RoomNetworkEventType.pending));
        } else if (type == 'room.joined' || type == 'room.snapshot') {
          final snapshot = _snapshotFromJson(message['snapshot']);
          events.add(RoomNetworkEvent(
            type == 'room.joined'
                ? RoomNetworkEventType.joined
                : RoomNetworkEventType.snapshot,
            snapshot: snapshot,
          ));
        } else if (type == 'room.rejected') {
          events.add(RoomNetworkEvent(
            RoomNetworkEventType.rejected,
            message: message['reason'] as String? ?? 'Join request rejected.',
          ));
        }
      },
      onDisconnected: (_) {
        if (!events.isClosed) {
          events.add(const RoomNetworkEvent(RoomNetworkEventType.disconnected));
          unawaited(events.close());
        }
      },
    );
    final client = RoomNetworkClient._(peer, events);
    await peer.send({
      'type': 'room.join',
      'roomId': invitation.roomId,
      'token': invitation.token,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
    });
    return client;
  }

  Future<void> close() async {
    if (!_peer.isClosed) {
      try {
        await _peer.send({'type': 'room.leave'});
      } catch (_) {}
      await _peer.close();
    }
    if (!_events.isClosed) await _events.close();
  }
}

String _newToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return Uri.encodeComponent(bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join());
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return difference == 0;
}

Map<String, Object?> _snapshotJson(RoomSnapshot snapshot) => {
      'id': snapshot.id,
      'hostDeviceId': snapshot.hostDeviceId,
      'maxMembers': snapshot.maxMembers,
      'isLocked': snapshot.isLocked,
      'members': snapshot.members.map(_memberJson).toList(),
      'pendingMembers': snapshot.pendingMembers.map(_memberJson).toList(),
    };

Map<String, Object?> _memberJson(RoomMember member) => {
      'deviceId': member.deviceId,
      'deviceName': member.deviceName,
      'platform': member.platform,
      'role': member.role.name,
      'status': member.status.name,
    };

RoomSnapshot _snapshotFromJson(Object? value) {
  if (value is! Map) throw const FormatException('Invalid room snapshot.');
  List<RoomMember> parseMembers(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((member) => RoomMember(
      deviceId: member['deviceId'] as String,
      deviceName: member['deviceName'] as String,
      platform: member['platform'] as String,
      role: RoomMemberRole.values.byName(member['role'] as String),
      status: RoomMemberStatus.values.byName(member['status'] as String),
    )).toList(growable: false);
  }

  return RoomSnapshot(
    id: value['id'] as String,
    hostDeviceId: value['hostDeviceId'] as String,
    maxMembers: value['maxMembers'] as int,
    isLocked: value['isLocked'] as bool,
    members: parseMembers(value['members']),
    pendingMembers: parseMembers(value['pendingMembers']),
  );
}
