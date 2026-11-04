/// Shared Kharcha BLE advertisement format.
///
/// Keep the UUID in sync with `PresenceBle.kt`. The packet carries only
/// Service Data (this UUID + 8 ID bytes) so it fits in a 31-byte legacy
/// advertisement. The phone never derives the ID; it broadcasts whatever
/// `GET /api/v1/presence/temporary-id` returned.
const kharchaServiceUuid = 'a7c4e91b-5d2f-4b8a-9e31-6f0c2d8a4b17';

final _hexId = RegExp(r'^[0-9a-f]{16}$');

/// 16 lowercase hex characters → 8 bytes, or `null` if the string is not
/// a backend-issued temporary ID.
List<int>? decodeTemporaryId(String hex) {
  final id = hex.trim().toLowerCase();
  if (!_hexId.hasMatch(id)) {
    return null;
  }
  return [
    for (var i = 0; i < 16; i += 2) int.parse(id.substring(i, i + 2), radix: 16),
  ];
}

/// 8 raw Service Data bytes → 16 lowercase hex characters.
String? encodeTemporaryId(List<int> bytes) {
  if (bytes.length != 8) {
    return null;
  }
  final out = StringBuffer();
  for (final b in bytes) {
    if (b < 0 || b > 255) {
      return null;
    }
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
