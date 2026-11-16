import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/rooms/room_registry.dart';

void main() {
  group('RoomRegistry', () {
    test('allows one host and seven receiving devices, then rejects the next', () {
      final room = RoomRegistry(roomId: 'ABC234');
      for (var index = 1; index <= 7; index++) {
        expect(room.join(
          deviceId: index.toString().padLeft(32, '0'),
          deviceName: 'Device $index',
          platform: index.isEven ? 'windows' : 'android',
        ), isTrue);
      }
      expect(room.joinedCount, 8);
      expect(room.receiverCount, 7);
      expect(room.isFull, isTrue);
      expect(room.join(
        deviceId: 'f'.padLeft(32, 'f'),
        deviceName: 'Extra device',
        platform: 'linux',
      ), isFalse);
    });

    test('allows an existing member to reconnect without consuming another slot', () {
      final room = RoomRegistry(roomId: 'ABC234', maxMembers: 2);
      const id = '0123456789abcdef0123456789abcdef';
      expect(room.join(deviceId: id, deviceName: 'Phone', platform: 'android'), isTrue);
      expect(room.join(deviceId: id, deviceName: 'Phone', platform: 'android'), isTrue);
      expect(room.joinedCount, 2);
      expect(room.receiverCount, 1);
    });

    test('tracks completion independently and supports leaving', () {
      final room = RoomRegistry(roomId: 'ABC234');
      const first = '0123456789abcdef0123456789abcdef';
      const second = 'abcdef0123456789abcdef0123456789';
      room.join(deviceId: first, deviceName: 'Phone', platform: 'android');
      room.join(deviceId: second, deviceName: 'PC', platform: 'windows');
      expect(room.markCompleted(first), isTrue);
      expect(room.completedCount, 1);
      expect(room.members.firstWhere((m) => m.deviceId == first).completed, isTrue);
      expect(room.leave(second), isTrue);
      expect(room.joinedCount, 2);
      expect(room.receiverCount, 1);
    });
  });
}
