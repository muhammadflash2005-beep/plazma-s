import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/network/android_wifi_session_service.dart';

void main() {
  group('PlazmaConnectionInvite', () {
    const invite = PlazmaConnectionInvite(
      ssid: 'Plazma S Local',
      password: 'test pass#123',
      host: '192.168.43.1',
      port: 45454,
      token: '0123456789abcdef0123456789abcdef',
    );

    test('round-trips QR data including reserved Wi-Fi password characters', () {
      final parsed = PlazmaConnectionInvite.tryParse(invite.toQrValue());
      expect(parsed, isNotNull);
      expect(parsed!.ssid, invite.ssid);
      expect(parsed.password, invite.password);
      expect(parsed.host, invite.host);
      expect(parsed.port, invite.port);
      expect(parsed.token, invite.token);
      expect(parsed.hasHotspotCredentials, isTrue);
    });

    test('recognizes same-Wi-Fi invites without hotspot credentials', () {
      const lanInvite = PlazmaConnectionInvite(
        ssid: '',
        password: '',
        host: '192.168.1.12',
        port: 45454,
        token: '0123456789abcdef0123456789abcdef',
      );
      final parsed = PlazmaConnectionInvite.tryParse(lanInvite.toQrValue());
      expect(parsed, isNotNull);
      expect(parsed!.hasHotspotCredentials, isFalse);
    });

    test('rejects unrelated QR codes', () {
      expect(PlazmaConnectionInvite.tryParse('https://example.com'), isNull);
      expect(PlazmaConnectionInvite.tryParse('plazmas://join?room=ABC123'), isNull);
    });

    test('rejects non-private hosts and invalid Wi-Fi credentials', () {
      const token = '0123456789abcdef0123456789abcdef';
      expect(
        PlazmaConnectionInvite.tryParse(
          'plazmas://connect?ssid=x&password=12345678&host=8.8.8.8&port=45454&token=$token',
        ),
        isNull,
      );
      expect(
        PlazmaConnectionInvite.tryParse(
          'plazmas://connect?ssid=x&password=short&host=192.168.1.2&port=45454&token=$token',
        ),
        isNull,
      );
      expect(
        PlazmaConnectionInvite.tryParse(
          'plazmas://connect?ssid=abcdefghijklmnopqrstuvwxyz123456789&password=12345678&host=192.168.1.2&port=45454&token=$token',
        ),
        isNull,
      );
    });

    test('rejects invalid ports and malformed tokens', () {
      expect(
        PlazmaConnectionInvite.tryParse(
          'plazmas://connect?ssid=x&password=y&host=192.168.1.2&port=99999&token=0123456789abcdef0123456789abcdef',
        ),
        isNull,
      );
      expect(
        PlazmaConnectionInvite.tryParse(
          'plazmas://connect?ssid=x&password=y&host=192.168.1.2&port=45454&token=bad',
        ),
        isNull,
      );
    });
  });
}
