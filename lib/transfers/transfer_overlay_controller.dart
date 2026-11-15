import 'package:flutter/foundation.dart';

enum TransferOverlayDirection { sending, receiving }

class TransferOverlaySnapshot {
  const TransferOverlaySnapshot({
    required this.direction,
    required this.fileCount,
    required this.label,
    this.progress,
  });

  final TransferOverlayDirection direction;
  final int fileCount;
  final String label;
  final double? progress;
}

class TransferOverlayController {
  TransferOverlayController._();

  static final ValueNotifier<TransferOverlaySnapshot?> current =
      ValueNotifier<TransferOverlaySnapshot?>(null);

  static void show(TransferOverlaySnapshot snapshot) => current.value = snapshot;
  static void clear() => current.value = null;
}
