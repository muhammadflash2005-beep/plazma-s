class RoomDevice {
  RoomDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.completed = false,
    DateTime? lastSeenAt,
  }) : lastSeenAt = lastSeenAt ?? DateTime.now();

  final String deviceId;
  final String deviceName;
  final String platform;
  final bool completed;
  final DateTime lastSeenAt;

  bool get isConnected => DateTime.now().difference(lastSeenAt) < const Duration(seconds: 55);

  RoomDevice copyWith({bool? completed, DateTime? lastSeenAt}) => RoomDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        completed: completed ?? this.completed,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );

  Map<String, Object> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'status': completed ? 'completed' : (isConnected ? 'joined' : 'reconnecting'),
      };
}

/// In-memory membership for one sender and up to seven receiving devices.
class RoomRegistry {
  RoomRegistry({required this.roomId, this.maxMembers = 8})
      : assert(maxMembers >= 2 && maxMembers <= 8);

  final String roomId;
  final int maxMembers;
  final Map<String, RoomDevice> _members = {};

  List<RoomDevice> get members => List.unmodifiable(_members.values);
  int get joinedCount => _members.length + 1;
  int get receiverCount => _members.length;
  int get completedCount => _members.values.where((member) => member.completed).length;
  bool get isFull => joinedCount >= maxMembers;

  bool join({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    if (deviceId.length != 32 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(deviceId) ||
        deviceName.trim().isEmpty ||
        deviceName.length > 80 ||
        platform.trim().isEmpty ||
        platform.length > 40) {
      return false;
    }
    if (_members.containsKey(deviceId)) return true;
    if (isFull) return false;
    _members[deviceId] = RoomDevice(
      deviceId: deviceId,
      deviceName: deviceName.trim(),
      platform: platform.trim(),
      lastSeenAt: DateTime.now(),
    );
    return true;
  }

  bool heartbeat(String deviceId) {
    final member = _members[deviceId];
    if (member == null) return false;
    _members[deviceId] = member.copyWith(lastSeenAt: DateTime.now());
    return true;
  }

  bool markCompleted(String deviceId) {
    final member = _members[deviceId];
    if (member == null) return false;
    _members[deviceId] = member.copyWith(completed: true);
    return true;
  }

  bool leave(String deviceId) => _members.remove(deviceId) != null;
}
