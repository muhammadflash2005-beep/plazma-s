import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/transfers/xender_local_transfer_service.dart';

void main() {
  const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('shared room items preserve live queue status and byte progress', () {
    final item = SharedLocalFile.fromJson({
      'id': 4,
      'name': 'movie.mp4',
      'relativePath': 'Videos/movie.mp4',
      'size': 2048,
      'sha256': digest,
      'status': 'sending',
      'bytesTransferred': 1024,
      'type': 'video',
    });

    expect(item.status, 'sending');
    expect(item.bytesTransferred, 1024);
    expect(item.size, 2048);
    expect(item.type, 'video');
  });

  test('sender and receiver keep independent states for the same item', () {
    final sender = SharedLocalFile.fromJson({
      'id': 9, 'name': 'photo.jpg', 'relativePath': 'photo.jpg',
      'size': 100, 'sha256': digest, 'status': 'sending',
      'bytesTransferred': 50, 'type': 'image',
    });
    final receiver = SharedLocalFile.fromJson({
      'id': 9, 'name': 'photo.jpg', 'relativePath': 'photo.jpg',
      'size': 100, 'sha256': digest, 'status': 'receiving',
      'bytesTransferred': 50, 'type': 'image',
    });
    final senderDone = SharedLocalFile.fromJson({
      'id': 9, 'name': 'photo.jpg', 'relativePath': 'photo.jpg',
      'size': 100, 'sha256': digest, 'status': 'done',
      'bytesTransferred': 100, 'type': 'image',
    });
    final receiverSaved = SharedLocalFile.fromJson({
      'id': 9, 'name': 'photo.jpg', 'relativePath': 'photo.jpg',
      'size': 100, 'sha256': digest, 'status': 'saved',
      'bytesTransferred': 100, 'type': 'image',
    });
    expect(sender.status, 'sending');
    expect(receiver.status, 'receiving');
    expect(senderDone.status, 'done');
    expect(receiverSaved.status, 'saved');
  });

  test('older room manifests default to waiting with zero progress', () {
    final item = SharedLocalFile.fromJson({
      'id': 0,
      'name': 'photo.jpg',
      'relativePath': 'photo.jpg',
      'size': 10,
      'sha256': digest,
    });

    expect(item.status, 'waiting');
    expect(item.bytesTransferred, 0);
  });
}
