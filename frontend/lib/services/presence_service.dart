import 'dart:async';

import '../api/presence_api.dart';
import '../models/temporary_id.dart';

/// Keeps the backend-issued BLE temporary ID fresh.
///
/// Fetches on [start], then again at each [TemporaryID.expiresAt]. The app
/// never computes the ID; it only caches what the API returned.
class PresenceService {
  PresenceService();

  TemporaryID? _id;
  Timer? _timer;

  /// Called whenever the ID to advertise changes, including when it is cleared.
  void Function(TemporaryID? id)? onId;

  TemporaryID? get current => _id;

  /// [fetch] should perform the authenticated GET, including token refresh.
  Future<void> start(Future<TemporaryID?> Function() fetch) async {
    stop();
    await _load(fetch);
  }

  /// Returns a non-expired ID, fetching if the cache is empty or stale.
  Future<TemporaryID?> ensure(Future<TemporaryID?> Function() fetch) async {
    final id = _id;
    if (id != null && !id.isExpired) {
      return id;
    }
    await _load(fetch);
    return _id;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _set(null);
  }

  Future<void> _load(Future<TemporaryID?> Function() fetch) async {
    _timer?.cancel();
    try {
      final id = await fetch();
      if (id == null) {
        return;
      }
      _set(id);
      _timer = Timer(_until(id.expiresAt), () {
        _promoteNext();
        unawaited(_load(fetch));
      });
    } on ApiException {
      _timer = Timer(const Duration(minutes: 1), () => unawaited(_load(fetch)));
    }
  }

  void _promoteNext() {
    final id = _id;
    if (id == null || id.nextId.isEmpty) {
      return;
    }
    _set(
      TemporaryID(
        id: id.nextId,
        expiresAt: id.nextExpiresAt,
        nextId: id.nextId,
        nextExpiresAt: id.nextExpiresAt,
      ),
    );
  }

  void _set(TemporaryID? id) {
    _id = id;
    onId?.call(id);
  }

  Duration _until(DateTime expiresAt) {
    final wait = expiresAt.difference(DateTime.now().toUtc());
    if (wait.isNegative) {
      return Duration.zero;
    }
    return wait;
  }
}
