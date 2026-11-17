import 'dart:collection';

import 'room_id.dart';
import 'room_models.dart';

typedef RoomPinVerifier = bool Function(String suppliedPin);

/// In-memory host-side room state machine. Transport authentication and
/// encrypted sessions must be established before using this over a network.
class RoomHost {
  RoomHost._({
    required this.id,
    required this.hostDeviceId,
    required this.maxMembers,
    required RoomPinVerifier? pinVerifier,
  }) : _pinVerifier = pinVerifier;

  static const defaultMaxMembers = 8;
  static const minimumMaxMembers = 2;
  static const maximumMaxMembers = 32;

  final String id;
  final String hostDeviceId;
  final int maxMembers;
  final RoomPinVerifier? _pinVerifier;
  final LinkedHashMap<String, RoomMember> _members = LinkedHashMap();
  final LinkedHashMap<String, RoomMember> _pending = LinkedHashMap();
  bool _locked = false;
  bool _closed = false;

  bool get isLocked => _locked;
  bool get isClosed => _closed;
  List<RoomMember> get members => List.unmodifiable(_members.values);
  List<RoomMember> get pendingMembers => List.unmodifiable(_pending.values);

  static RoomHost create({
    required String hostDeviceId,
    required String hostDeviceName,
    required String hostPlatform,
    int maxMembers = defaultMaxMembers,
    RoomPinVerifier? pinVerifier,
    String? roomId,
  }) {
    if (hostDeviceId.trim().isEmpty) {
      throw ArgumentError.value(hostDeviceId, 'hostDeviceId');
    }
    if (maxMembers < minimumMaxMembers || maxMembers > maximumMaxMembers) {
      throw RangeError.range(
        maxMembers,
        minimumMaxMembers,
        maximumMaxMembers,
        'maxMembers',
      );
    }
    final id = roomId ?? RoomId.generate();
    if (!RoomId.isValid(id)) throw ArgumentError.value(id, 'roomId');

    final room = RoomHost._(
      id: id,
      hostDeviceId: hostDeviceId,
      maxMembers: maxMembers,
      pinVerifier: pinVerifier,
    );
    room._members[hostDeviceId] = RoomMember(
      deviceId: hostDeviceId,
      deviceName: hostDeviceName,
      platform: hostPlatform,
      role: RoomMemberRole.host,
      status: RoomMemberStatus.joined,
    );
    return room;
  }

  /// Returns false for invalid, duplicate, locked, full, or wrong-PIN requests.
  bool requestJoin({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? suppliedPin,
  }) {
    _ensureOpen();
    if (_locked || _members.length >= maxMembers) return false;
    if (deviceId.trim().isEmpty || deviceId == hostDeviceId) return false;
    if (_members.containsKey(deviceId) || _pending.containsKey(deviceId)) {
      return false;
    }
    if (_pinVerifier != null && !_pinVerifier(suppliedPin ?? '')) return false;

    _pending[deviceId] = RoomMember(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      role: RoomMemberRole.member,
      status: RoomMemberStatus.pending,
    );
    return true;
  }

  bool approve(String deviceId) {
    _ensureOpen();
    final request = _pending.remove(deviceId);
    if (request == null || _locked || _members.length >= maxMembers) {
      if (request != null) _pending[deviceId] = request;
      return false;
    }
    _members[deviceId] = request.copyWith(status: RoomMemberStatus.joined);
    return true;
  }

  bool reject(String deviceId) {
    _ensureOpen();
    return _pending.remove(deviceId) != null;
  }

  bool kick(String deviceId) {
    _ensureOpen();
    if (deviceId == hostDeviceId) return false;
    return _members.remove(deviceId) != null;
  }

  void setLocked(bool locked) {
    _ensureOpen();
    _locked = locked;
  }

  bool leave(String deviceId) => kick(deviceId);

  void close() {
    if (_closed) return;
    _closed = true;
    _members.clear();
    _pending.clear();
  }

  RoomSnapshot snapshot() => RoomSnapshot(
        id: id,
        hostDeviceId: hostDeviceId,
        maxMembers: maxMembers,
        isLocked: _locked,
        members: members,
        pendingMembers: pendingMembers,
      );

  void _ensureOpen() {
    if (_closed) throw StateError('Room $id is closed.');
  }
}
