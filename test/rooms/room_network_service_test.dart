import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/rooms/room_network_service.dart';

void main() {
  group('Room network signaling', () {
    test('invitation URI round-trips and rejects incomplete payloads', () async {
      final host = await RoomNetworkHost.start(
        hostDeviceId: 'host-1',
        hostDeviceName: 'Host',
        hostPlatform: 'linux',
        advertisedAddress: InternetAddress.loopbackIPv4.address,
        port: 0,
        roomId: 'ABC234',
      );
      try {
        final parsed = RoomInvitation.tryParse(host.invitation.toUri());
        expect(parsed, isNotNull);
        expect(parsed!.roomId, 'ABC234');
        expect(parsed.host, InternetAddress.loopbackIPv4.address);
        expect(parsed.port, host.invitation.port);
        expect(RoomInvitation.tryParse(Uri.parse('plazmas://join?room=ABC234')), isNull);
      } finally {
        await host.close();
      }
    });

    test('client requests entry and joins only after host approval', () async {
      final host = await RoomNetworkHost.start(
        hostDeviceId: 'host-1',
        hostDeviceName: 'Host PC',
        hostPlatform: 'linux',
        advertisedAddress: InternetAddress.loopbackIPv4.address,
        port: 0,
        roomId: 'ABC234',
      );
      RoomNetworkClient? client;
      try {
        client = await RoomNetworkClient.join(
          invitation: host.invitation,
          deviceId: 'phone-1',
          deviceName: 'Android phone',
          platform: 'android',
        );
        final events = StreamIterator(client.events);
        expect(await events.moveNext().timeout(const Duration(seconds: 3)), isTrue);
        final pending = events.current;
        expect(pending.type, RoomNetworkEventType.pending);
        expect(host.pendingMembers.single.deviceId, 'phone-1');

        expect(await host.approve('phone-1'), isTrue);
        expect(await events.moveNext().timeout(const Duration(seconds: 3)), isTrue);
        final joined = events.current;
        await events.cancel();
        expect(joined.type, RoomNetworkEventType.joined);
        expect(joined.snapshot!.joinedCount, 2);
        expect(joined.snapshot!.members.last.deviceId, 'phone-1');
      } finally {
        await client?.close();
        await host.close();
      }
    });

    test('invalid invitation token is rejected', () async {
      final host = await RoomNetworkHost.start(
        hostDeviceId: 'host-1',
        hostDeviceName: 'Host',
        hostPlatform: 'linux',
        advertisedAddress: InternetAddress.loopbackIPv4.address,
        port: 0,
        roomId: 'ABC234',
      );
      RoomNetworkClient? client;
      try {
        final invalid = RoomInvitation(
          roomId: host.invitation.roomId,
          host: host.invitation.host,
          port: host.invitation.port,
          token: List.filled(64, '0').join(),
        );
        client = await RoomNetworkClient.join(
          invitation: invalid,
          deviceId: 'phone-1',
          deviceName: 'Phone',
          platform: 'android',
        );
        final rejected = await client.events.first.timeout(const Duration(seconds: 3));
        expect(rejected.type, RoomNetworkEventType.rejected);
        expect(host.snapshot.joinedCount, 1);
        expect(host.pendingMembers, isEmpty);
      } finally {
        await client?.close();
        await host.close();
      }
    });
  });
}
