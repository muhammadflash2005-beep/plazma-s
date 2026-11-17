import 'dart:math';
import 'dart:io';

import 'package:flutter/services.dart';

/// Connection details exchanged by the Xender-style QR pairing flow.
class PlazmaConnectionInvite {
  const PlazmaConnectionInvite({
    required this.ssid,
    required this.password,
    required this.host,
    required this.port,
    required this.token,
    this.roomId = '',
  });

  final String ssid;
  final String password;
  final String host;
  final int port;
  final String token;
  final String roomId;

  String toQrValue() {
    final uri = Uri(
      scheme: 'plazmas',
      host: 'connect',
      queryParameters: {
        'ssid': ssid,
        'password': password,
        'host': host,
        'port': port.toString(),
        'token': token,
        if (roomId.isNotEmpty) 'room': roomId,
        'capacity': '8',
      },
    );
    return uri.toString();
  }

  static PlazmaConnectionInvite? tryParse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'plazmas' || uri.host != 'connect') {
      return null;
    }
    final query = uri.queryParameters;
    final ssid = query['ssid'];
    final password = query['password'];
    final host = query['host'];
    final port = int.tryParse(query['port'] ?? '');
    final token = query['token'];
    final roomId = query['room'] ?? '';
    final address = host == null ? null : InternetAddress.tryParse(host);
    final octets = address?.type == InternetAddressType.IPv4
        ? address!.address.split('.').map(int.parse).toList()
        : const <int>[];
    final isPrivateIpv4 = octets.length == 4 &&
        (octets[0] == 10 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31));
    final hasHotspotCredentials =
        (ssid?.isNotEmpty ?? false) || (password?.isNotEmpty ?? false);
    final validHotspotCredentials = !hasHotspotCredentials ||
        (ssid != null && ssid.isNotEmpty && ssid.length <= 32 &&
            password != null && password.length >= 8 && password.length <= 63);
    const roomAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final validRoomId = roomId.isEmpty ||
        (roomId.length == 6 && roomId.split('').every(roomAlphabet.contains));
    if (ssid == null ||
        password == null ||
        !validHotspotCredentials ||
        !validRoomId ||
        !isPrivateIpv4 ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        token == null ||
        token.length != 32 ||
        !token.split('').every('0123456789abcdef'.contains)) {
      return null;
    }
    return PlazmaConnectionInvite(
      ssid: ssid,
      password: password,
      host: host!,
      port: port,
      token: token,
      roomId: roomId,
    );
  }
}

/// Android bridge for hosting and joining a private, internet-free Wi-Fi
/// session. The native side owns the Wi-Fi NetworkCallback so the connection
/// remains bound to the selected Wi-Fi network for the transfer session.
class AndroidWifiSessionService {
  static const MethodChannel _channel = MethodChannel('com.plazma.s/hotspot');

  Future<PlazmaConnectionInvite> createInvite({int port = 45454}) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 1 and 65535.');
    }
    final token = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final result = await _channel.invokeMapMethod<String, Object?>(
      'startHotspot',
    );
    if (result == null) {
      throw PlatformException(
        code: 'EMPTY_RESULT',
        message: 'Android did not return hotspot details.',
      );
    }
    final ssid = result['ssid'] as String? ?? '';
    final password = result['password'] as String? ?? '';
    final host = result['host'] as String? ?? '';
    if (ssid.isEmpty || password.isEmpty || host.isEmpty) {
      await stop();
      throw PlatformException(
        code: 'INCOMPLETE_HOTSPOT',
        message: 'Android started Wi-Fi but did not provide complete local connection details.',
      );
    }
    return PlazmaConnectionInvite(
      ssid: ssid,
      password: password,
      host: host,
      port: port,
      token: token,
    );
  }

  Future<void> join(PlazmaConnectionInvite invite) async {
    await _channel.invokeMethod<void>('joinHotspot', {
      'ssid': invite.ssid,
      'password': invite.password,
    });
  }

  Future<void> stop() => _channel.invokeMethod<void>('stopHotspot');

  Future<void> disconnect() =>
      _channel.invokeMethod<void>('disconnectHotspot');

  Future<void> openWifiSettings() =>
      _channel.invokeMethod<void>('openWifiSettings');
}
