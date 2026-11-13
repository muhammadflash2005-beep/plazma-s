import 'dart:math';

/// Room IDs are short locators, never authentication credentials.
class RoomId {
  RoomId._();

  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 6;

  static String generate({Random? random}) {
    final source = random ?? Random.secure();
    return List.generate(
      length,
      (_) => alphabet[source.nextInt(alphabet.length)],
    ).join();
  }

  static bool isValid(String value) {
    if (value.length != length) return false;
    return value.split('').every(alphabet.contains);
  }
}
