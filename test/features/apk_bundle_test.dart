import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/features/apps/apk_bundle.dart';

void main() {
  group('ApkBundle.isBundle', () {
    test('recognizes APKS and XAPK archives case-insensitively', () {
      expect(ApkBundle.isBundle('/received/game.apks'), isTrue);
      expect(ApkBundle.isBundle('/received/game.XAPK'), isTrue);
    });

    test('does not classify standalone APKs or ordinary ZIPs as split bundles', () {
      expect(ApkBundle.isBundle('/received/base.apk'), isFalse);
      expect(ApkBundle.isBundle('/received/archive.zip'), isFalse);
    });
  });
}
