import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/ble/kharcha_uuid.dart';

void main() {
  test('round-trips a backend-issued temporary id', () {
    const hex = 'a1b2c3d4e5f60718';
    final bytes = decodeTemporaryId(hex);
    expect(bytes, [0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x07, 0x18]);
    expect(encodeTemporaryId(bytes!), hex);
  });

  test('accepts uppercase and returns lowercase', () {
    expect(encodeTemporaryId(decodeTemporaryId('A1B2C3D4E5F60718')!), 'a1b2c3d4e5f60718');
  });

  test('rejects ids that are not 16 hex characters', () {
    expect(decodeTemporaryId(''), isNull);
    expect(decodeTemporaryId('short'), isNull);
    expect(decodeTemporaryId('a1b2c3d4e5f6071g'), isNull);
    expect(decodeTemporaryId('a1b2c3d4e5f6071819'), isNull);
    expect(encodeTemporaryId([1, 2, 3]), isNull);
  });
}
