import 'package:balage_radio/core/icy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows-1250 dalcím dekódolása', () {
    // "Kovács Kati - Úgy" cp1250 bájtokkal
    final bytes = [75, 111, 118, 0xE1, 99, 115, 32, 75, 97, 116, 105, 32, 45, 32, 0xDA, 103, 121];
    expect(IcyReader.decode(bytes), 'Kovács Kati - Úgy');
  });
}
