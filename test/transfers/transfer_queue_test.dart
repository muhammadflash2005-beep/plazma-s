import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/transfers/transfer_queue.dart';

void main() {
  TransferQueue itemQueue() {
    final queue = TransferQueue();
    queue.append(const TransferQueueItem(
      id: 1, name: 'photo.jpg', type: TransferItemType.image, size: 100));
    return queue;
  }

  test('items can be appended while another item is sending without replacing it', () {
    final queue = itemQueue();
    queue.update(1, (item) => item.copyWith(status: TransferItemStatus.sending, bytesTransferred: 40));
    queue.append(const TransferQueueItem(
      id: 2, name: 'app.apk', type: TransferItemType.app, size: 200));
    expect(queue.items.map((item) => item.id), [1, 2]);
    expect(queue.items.first.status, TransferItemStatus.sending);
    expect(queue.items.last.status, TransferItemStatus.waiting);
  });

  test('cancellation affects one item or all active items', () {
    final queue = itemQueue();
    queue.append(const TransferQueueItem(
      id: 2, name: 'clip.mp4', type: TransferItemType.video, size: 200));
    queue.update(1, (item) => item.copyWith(status: TransferItemStatus.sending));
    queue.cancel(1);
    expect(queue.items.first.status, TransferItemStatus.cancelled);
    queue.cancelAll();
    expect(queue.items.last.status, TransferItemStatus.cancelled);
  });

  test('retry resets failed item progress and preserves successful items', () {
    final queue = itemQueue();
    queue.update(1, (item) => item.copyWith(
      status: TransferItemStatus.failed, bytesTransferred: 35, error: 'network'));
    queue.retryFailed();
    expect(queue.items.single.status, TransferItemStatus.waiting);
    expect(queue.items.single.bytesTransferred, 0);
    expect(queue.items.single.error, isNull);
  });

  test('receiver manifest updates merge new items and latest progress', () {
    final queue = itemQueue();
    queue.mergeRemote([
      const TransferQueueItem(id: 1, name: 'photo.jpg',
        type: TransferItemType.image, size: 100,
        status: TransferItemStatus.sending, bytesTransferred: 75),
      const TransferQueueItem(id: 2, name: 'song.mp3',
        type: TransferItemType.music, size: 50),
    ]);
    expect(queue.length, 2);
    expect(queue.items.first.bytesTransferred, 75);
    expect(queue.items.last.type, TransferItemType.music);
  });


  test('one receiver cancelling an item does not cancel it for another', () {
    final statuses = ReceiverQueueStatusRegistry();
    expect(statuses.update('phone-a', 7, 'cancelled'), isTrue);
    expect(statuses.statusFor('phone-a', 7), 'cancelled');
    expect(statuses.statusFor('phone-b', 7), isNull);
    expect(statuses.update('phone-a', 7, 'sending'), isFalse);
    expect(statuses.update('phone-b', 7, 'sending'), isTrue);
    expect(statuses.statusFor('phone-b', 7), 'sending');
  });

  test('receiver cancellation state is removed when that device leaves', () {
    final statuses = ReceiverQueueStatusRegistry();
    statuses.update('phone-a', 2, 'cancelled');
    statuses.removeDevice('phone-a');
    expect(statuses.statusFor('phone-a', 2), isNull);
  });

}
