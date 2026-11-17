import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum TransferOverlayDirection { sending, receiving }

class TransferOverlaySnapshot {
  const TransferOverlaySnapshot({
    required this.direction,
    required this.fileCount,
    required this.label,
    this.progress,
    this.isAppTransfer = false,
  });

  final TransferOverlayDirection direction;
  final int fileCount;
  final String label;
  final double? progress;
  final bool isAppTransfer;
}

class TransferOverlayController {
  TransferOverlayController._();

  static final ValueNotifier<TransferOverlaySnapshot?> current =
      ValueNotifier<TransferOverlaySnapshot?>(null);

  // Icons are keyed by the package folder at the start of each app transfer path.
  static final Map<String, Uint8List> _appIcons = <String, Uint8List>{};
  static final ValueNotifier<int> appIconRevision = ValueNotifier<int>(0);

  static void registerAppIcon(String packageName, Uint8List icon) {
    if (packageName.isNotEmpty && icon.isNotEmpty) {
      _appIcons[packageName] = icon;
      appIconRevision.value++;
    }
  }

  static Uint8List? appIconFor(String relativePath) {
    final separator = relativePath.indexOf('/');
    if (separator <= 0) return null;
    return _appIcons[relativePath.substring(0, separator)];
  }

  static void show(TransferOverlaySnapshot snapshot) => current.value = snapshot;
  static void clear() => current.value = null;
}
