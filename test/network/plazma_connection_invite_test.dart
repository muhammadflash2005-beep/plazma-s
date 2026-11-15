import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/network/android_wifi_session_service.dart';

void main() {
  group('PlazmaConnectionInvite', () {
    test('parses a desktop LAN invite without hotspot credentials', () {
      const invite = PlazmaConnectionInvite(
        ssid: '',
        password: '',
        host: '192.168.1.20',
        port: 45454,
        token: '0123456789abcdef0123456789abcdef',
      );

      final parsed = PlazmaConnectionInvite.tryParse(invite.toQrValue());

      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.20');
      expect(parsed.ssid, isEmpty);
      expect(parsed.password, isEmpty);
      expect(parsed.port, 45454);
    });

    test('rejects a non-private network address', () {
      final value = Uri(
        scheme: 'plazmas',
        host: 'connect',
        queryParameters: {
          'ssid': '',
          'password': '',
          'host': '8.8.8.8',
          'port': '45454',
          'token': '0123456789abcdef0123456789abcdef',
        },
      );

      expect(PlazmaConnectionInvite.tryParse(value.toString()), isNull);
    });

    test('preserves room ID and eight-device capacity in QR invites', () {
      const invite = PlazmaConnectionInvite(
        ssid: '',
        password: '',
        host: '192.168.1.20',
        port: 45454,
        token: '0123456789abcdef0123456789abcdef',
        roomId: 'ABC234',
      );

      final parsed = PlazmaConnectionInvite.tryParse(invite.toQrValue());

      expect(parsed, isNotNull);
      expect(parsed!.roomId, 'ABC234');
      expect(Uri.parse(invite.toQrValue()).queryParameters['capacity'], '8');
    });

    test('rejects malformed room IDs', () {
      final value = Uri(
        scheme: 'plazmas',
        host: 'connect',
        queryParameters: {
          'ssid': '',
          'password': '',
          'host': '192.168.1.20',
          'port': '45454',
          'token': '0123456789abcdef0123456789abcdef',
          'room': 'BAD!ID',
        },
      );

      expect(PlazmaConnectionInvite.tryParse(value.toString()), isNull);
    });
  });
}
