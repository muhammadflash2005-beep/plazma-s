import 'dart:collection';

enum TransferItemType { app, image, video, music, file }
enum TransferItemStatus { waiting, sending, done, failed, cancelled }

class TransferQueueItem {
  const TransferQueueItem({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    this.status = TransferItemStatus.waiting,
    this.bytesTransferred = 0,
    this.error,
  });

  final int id;
  final String name;
  final TransferItemType type;
  final int size;
  final TransferItemStatus status;
  final int bytesTransferred;
  final String? error;

  double get progress => size <= 0 ? (status == TransferItemStatus.done ? 1 : 0) :
      (bytesTransferred / size).clamp(0.0, 1.0);

  TransferQueueItem copyWith({
    TransferItemStatus? status,
    int? bytesTransferred,
    String? error,
    bool clearError = false,
  }) => TransferQueueItem(
    id: id, name: name, type: type, size: size,
    status: status ?? this.status,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'type': type.name, 'size': size,
    'status': status.name, 'bytesTransferred': bytesTransferred,
    'error': error,
  };

  factory TransferQueueItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'file';
    final statusName = json['status'] as String? ?? 'waiting';
    return TransferQueueItem(
      id: json['id'] as int,
      name: json['name'] as String,
      type: TransferItemType.values.firstWhere(
        (value) => value.name == typeName, orElse: () => TransferItemType.file),
      size: json['size'] as int,
      status: TransferItemStatus.values.firstWhere(
        (value) => value.name == statusName, orElse: () => TransferItemStatus.waiting),
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }
}

/// Mutable queue state for one local room. The queue is append-only by ID;
/// status changes never reorder items, so receivers can safely merge updates.
class TransferQueue {
  final LinkedHashMap<int, TransferQueueItem> _items = LinkedHashMap();
  List<TransferQueueItem> get items => List.unmodifiable(_items.values);
  int get length => _items.length;
  int get totalBytes => _items.values.fold(0, (sum, item) => sum + item.size);
  int get transferredBytes => _items.values.fold(
    0, (sum, item) => sum + item.bytesTransferred.clamp(0, item.size));
  double get progress => totalBytes == 0 ? 0 : transferredBytes / totalBytes;

  void append(TransferQueueItem item) {
    if (_items.containsKey(item.id)) throw StateError('Queue item ${item.id} already exists.');
    _items[item.id] = item;
  }

  void update(int id, TransferQueueItem Function(TransferQueueItem) change) {
    final item = _items[id];
    if (item == null) return;
    _items[id] = change(item);
  }

  void cancel(int id) => update(id, (item) =>
    item.copyWith(status: TransferItemStatus.cancelled, clearError: true));

  void cancelAll() {
    for (final item in items) {
      if (item.status == TransferItemStatus.waiting ||
          item.status == TransferItemStatus.sending) {
        cancel(item.id);
      }
    }
  }

  void retryFailed() {
    for (final item in items) {
      if (item.status == TransferItemStatus.failed) {
        update(item.id, (current) => current.copyWith(
          status: TransferItemStatus.waiting, bytesTransferred: 0, clearError: true));
      }
    }
  }

  void mergeRemote(Iterable<TransferQueueItem> remote) {
    for (final item in remote) {
      final current = _items[item.id];
      if (current == null) {
        _items[item.id] = item;
      } else if (item.bytesTransferred >= current.bytesTransferred ||
          item.status == TransferItemStatus.done ||
          item.status == TransferItemStatus.failed ||
          item.status == TransferItemStatus.cancelled) {
        _items[item.id] = item;
      }
    }
  }
}


/// Tracks cancellation independently for each receiver. One recipient leaving
/// an item must not cancel that item for every other device in the room.
class ReceiverQueueStatusRegistry {
  final Map<String, Map<int, String>> _statuses = {};

  String? statusFor(String deviceId, int itemId) => _statuses[deviceId]?[itemId];

  bool update(String deviceId, int itemId, String status) {
    final receiverItems = _statuses.putIfAbsent(deviceId, () => <int, String>{});
    if (receiverItems[itemId] == 'cancelled' && status != 'cancelled') {
      return false;
    }
    receiverItems[itemId] = status;
    return true;
  }

  void removeDevice(String deviceId) => _statuses.remove(deviceId);
  void clear() => _statuses.clear();
}
