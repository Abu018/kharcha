import 'package:flutter/foundation.dart';

import '../api/expense_api.dart';
import '../models/expense.dart';
import 'notification_source.dart';
import 'payment_parser.dart';
import 'sms_source.dart';

/// Imports payment SMS from the inbox and payment notifications from UPI and
/// bank apps as expenses.
class AutoDetector {
  AutoDetector({
    required this.sms,
    required this.notifications,
    required this.api,
  });

  final SmsSource sms;
  final NotificationSource notifications;
  final ExpenseApi api;

  /// How far back the first sync looks.
  static const firstSyncWindow = Duration(days: 30);

  /// Saves every payment SMS received since the last sync for [userKey] and
  /// returns the newly created expenses. Messages are processed oldest first
  /// and progress is stored after each one, so a failure part-way (no
  /// network, expired token) resumes from the same place next time.
  Future<List<Expense>> sync({
    required String accessToken,
    required String userKey,
  }) async {
    final key = 'last_sms_sync:$userKey';
    final since =
        await sms.lastSync(key) ?? DateTime.now().subtract(firstSyncWindow);
    final messages = await sms.readInbox(since: since);

    final saved = <Expense>[];
    for (final message in messages) {
      final input = parsePaymentSms(message);
      if (input != null) {
        final expense = await api.createExpense(
          accessToken: accessToken,
          input: input,
        );
        if (expense != null) {
          saved.add(expense);
        }
      }
      await sms.setLastSync(key, message.date);
    }
    return saved;
  }

  /// Saves the payment notifications queued since the last call and returns
  /// the newly created expenses. Each one is acknowledged once handled, so a
  /// failure part-way leaves the rest queued for next time.
  Future<List<Expense>> syncNotifications({required String accessToken}) async {
    final saved = <Expense>[];
    for (final notification in await notifications.pending()) {
      final expense = await _saveNotification(accessToken, notification);
      if (expense != null) {
        saved.add(expense);
      }
    }
    return saved;
  }

  /// Saves one SMS that just arrived. Returns `null` if it is not a payment
  /// or was already recorded.
  Future<Expense?> handleIncoming({
    required String accessToken,
    required SmsMessageData message,
  }) async {
    final input = parsePaymentSms(message);
    if (input == null) {
      return null;
    }
    return api.createExpense(accessToken: accessToken, input: input);
  }

  /// Saves one payment notification that was just posted. Returns `null` if
  /// it is not a payment or was already recorded.
  Future<Expense?> handleIncomingNotification({
    required String accessToken,
    required PaymentNotification notification,
  }) => _saveNotification(accessToken, notification);

  Future<Expense?> _saveNotification(
    String accessToken,
    PaymentNotification notification,
  ) async {
    final input = parsePaymentNotification(notification);
    if (input == null && kDebugMode) {
      debugPrint(
        'PaymentNotification not a payment: ${notification.app} | '
        '${notification.title} | ${notification.text}',
      );
    }
    final expense = input == null
        ? null
        : await api.createExpense(accessToken: accessToken, input: input);
    await notifications.acknowledge([notification.ref]);
    return expense;
  }
}
