/// BLE payload issued by the backend. The app advertises [id] until
/// [expiresAt], then switches to [nextId].
class TemporaryID {
  const TemporaryID({
    required this.id,
    required this.expiresAt,
    required this.nextId,
    required this.nextExpiresAt,
  });

  factory TemporaryID.fromJson(Map<String, dynamic> json) {
    final id = json['temporary_id'];
    final expiresAt = json['expires_at'];
    final nextId = json['next_temporary_id'];
    final nextExpiresAt = json['next_expires_at'];
    if (id is! String ||
        id.isEmpty ||
        expiresAt is! String ||
        nextId is! String ||
        nextExpiresAt is! String) {
      throw const FormatException('temporary id response was incomplete');
    }
    return TemporaryID(
      id: id,
      expiresAt: DateTime.parse(expiresAt).toUtc(),
      nextId: nextId,
      nextExpiresAt: DateTime.parse(nextExpiresAt).toUtc(),
    );
  }

  final String id;
  final DateTime expiresAt;
  final String nextId;
  final DateTime nextExpiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}
