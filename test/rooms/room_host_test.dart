import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/rooms/room_host.dart';
import 'package:plazma_s/rooms/room_models.dart';

void main() {
  RoomHost makeRoom({
    int maxMembers = 8,
    RoomPinVerifier? pinVerifier,
  }) =>
      RoomHost.create(
        roomId: 'ABC234',
        hostDeviceId: 'host-1',
        hostDeviceName: 'Host PC',
        hostPlatform: 'windows',
        maxMembers: maxMembers,
        pinVerifier: pinVerifier,
      );

  group('RoomHost', () {
    test('starts with the host as the first joined member', () {
      final room = makeRoom();
      expect(room.members, hasLength(1));
      expect(room.members.single.role, RoomMemberRole.host);
      expect(room.snapshot().joinedCount, 1);
    });

    test('join requests remain pending until host approval', () {
      final room = makeRoom();
      expect(
        room.requestJoin(
          deviceId: 'phone-1',
          deviceName: 'Android phone',
          platform: 'android',
        ),
        isTrue,
      );
      expect(room.members, hasLength(1));
      expect(room.pendingMembers, hasLength(1));
      expect(room.approve('phone-1'), isTrue);
      expect(room.pendingMembers, isEmpty);
      expect(room.members, hasLength(2));
      expect(room.members.last.status, RoomMemberStatus.joined);
    });

    test('rejects duplicate requests and supports rejection', () {
      final room = makeRoom();
      final request = {
        'deviceId': 'phone-1',
        'deviceName': 'Phone',
        'platform': 'android',
      };
      expect(room.requestJoin(
        deviceId: request['deviceId']!,
        deviceName: request['deviceName']!,
        platform: request['platform']!,
      ), isTrue);
      expect(room.requestJoin(
        deviceId: request['deviceId']!,
        deviceName: request['deviceName']!,
        platform: request['platform']!,
      ), isFalse);
      expect(room.reject('phone-1'), isTrue);
      expect(room.pendingMembers, isEmpty);
    });

    test('enforces PIN verifier, lock, and member capacity', () {
      final room = makeRoom(
        maxMembers: 2,
        pinVerifier: (pin) => pin == '2468',
      );
      expect(room.requestJoin(
        deviceId: 'bad',
        deviceName: 'Bad',
        platform: 'android',
        suppliedPin: '0000',
      ), isFalse);
      expect(room.requestJoin(
        deviceId: 'phone',
        deviceName: 'Phone',
        platform: 'android',
        suppliedPin: '2468',
      ), isTrue);
      expect(room.approve('phone'), isTrue);
      expect(room.requestJoin(
        deviceId: 'laptop',
        deviceName: 'Laptop',
        platform: 'linux',
        suppliedPin: '2468',
      ), isFalse);
      room.setLocked(true);
      expect(room.requestJoin(
        deviceId: 'tablet',
        deviceName: 'Tablet',
        platform: 'android',
        suppliedPin: '2468',
      ), isFalse);
    });

    test('host cannot be kicked; members can be kicked', () {
      final room = makeRoom();
      room.requestJoin(
        deviceId: 'phone',
        deviceName: 'Phone',
        platform: 'android',
      );
      room.approve('phone');
      expect(room.kick('host-1'), isFalse);
      expect(room.kick('phone'), isTrue);
      expect(room.members, hasLength(1));
    });

    test('closing clears room state and prevents further operations', () {
      final room = makeRoom();
      room.close();
      expect(room.isClosed, isTrue);
      expect(room.members, isEmpty);
      expect(() => room.setLocked(true), throwsStateError);
    });
  });
}
