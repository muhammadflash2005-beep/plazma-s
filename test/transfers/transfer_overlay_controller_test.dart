import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/transfers/transfer_overlay_controller.dart';

void main() {
  test('app transfer icon is resolved from its package path', () {
    const packageName = 'com.plazma.icon_cache_test';
    final icon = Uint8List.fromList([1, 2, 3]);
    final previousRevision = TransferOverlayController.appIconRevision.value;

    TransferOverlayController.registerAppIcon(packageName, icon);

    expect(
      TransferOverlayController.appIconFor('$packageName/$packageName.apks'),
      same(icon),
    );
    expect(TransferOverlayController.appIconRevision.value, previousRevision + 1);
  });

  test('non-app paths do not resolve an app icon', () {
    expect(TransferOverlayController.appIconFor('photo.jpg'), isNull);
  });
}
