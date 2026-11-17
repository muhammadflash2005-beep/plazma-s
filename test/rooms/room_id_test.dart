import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plazma_s/rooms/room_id.dart';

void main() {
  group('RoomId', () {
    test('generates six characters from the unambiguous alphabet', () {
      final id = RoomId.generate(random: Random(12));
      expect(id, hasLength(6));
      expect(RoomId.isValid(id), isTrue);
      expect(id, isNot(contains('0')));
      expect(id, isNot(contains('1')));
      expect(id, isNot(contains('O')));
      expect(id, isNot(contains('I')));
    });

    test('rejects malformed room IDs', () {
      expect(RoomId.isValid('ABC12'), isFalse);
      expect(RoomId.isValid('ABC12O'), isFalse);
      expect(RoomId.isValid('abc234'), isFalse);
    });
  });
}
