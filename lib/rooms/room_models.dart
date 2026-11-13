enum RoomMemberRole { host, member }

enum RoomMemberStatus { pending, joined }

class RoomMember {
  const RoomMember({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.role,
    required this.status,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final RoomMemberRole role;
  final RoomMemberStatus status;

  RoomMember copyWith({RoomMemberStatus? status}) => RoomMember(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        role: role,
        status: status ?? this.status,
      );
}

class RoomSnapshot {
  const RoomSnapshot({
    required this.id,
    required this.hostDeviceId,
    required this.maxMembers,
    required this.isLocked,
    required this.members,
    required this.pendingMembers,
  });

  final String id;
  final String hostDeviceId;
  final int maxMembers;
  final bool isLocked;
  final List<RoomMember> members;
  final List<RoomMember> pendingMembers;

  int get joinedCount => members.length;
  int get pendingCount => pendingMembers.length;
  bool get isFull => joinedCount >= maxMembers;
}
