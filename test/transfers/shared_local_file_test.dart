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
    });

    expect(item.status, 'sending');
    expect(item.bytesTransferred, 1024);
    expect(item.size, 2048);
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
