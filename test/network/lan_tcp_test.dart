import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/network/lan_tcp.dart';

void main() {
  group('LAN TCP transport', () {
    test('client sends a framed message to the server', () async {
      final received = Completer<Map<String, Object?>>();
      final server = LanTcpServer(
        onMessage: (_, message) {
          if (!received.isCompleted) received.complete(message);
        },
      );
      TcpPeer? client;

      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        client = await TcpPeer.connect(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port!,
          onMessage: (_, __) {},
        );

        await client.send({'type': 'hello', 'device': 'test-device'});
        expect(
          await received.future.timeout(const Duration(seconds: 3)),
          {'type': 'hello', 'device': 'test-device'},
        );
      } finally {
        await client?.close();
        await server.close();
      }
    });

    test('server reports connected peers', () async {
      final connected = Completer<TcpPeer>();
      final server = LanTcpServer(
        onMessage: (_, __) {},
        onPeerConnected: (peer) {
          if (!connected.isCompleted) connected.complete(peer);
        },
      );
      TcpPeer? client;

      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        client = await TcpPeer.connect(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port!,
          onMessage: (_, __) {},
        );

        final peer = await connected.future.timeout(const Duration(seconds: 3));
        expect(peer.address, InternetAddress.loopbackIPv4.address);
        expect(server.peers, contains(peer));
      } finally {
        await client?.close();
        await server.close();
      }
    });
  });
}
