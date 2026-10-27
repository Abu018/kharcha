/// Account types accepted by `POST /api/v1/expense`.
const expenseAccountTypes = {
  'savings': 'Savings',
  'current': 'Current',
  'credit_card': 'Credit card',
  'upi_wallet': 'UPI wallet',
};

/// Formats paise with Indian digit grouping, e.g. `₹1,25,000.50`.
String formatPaise(int paise, {String currency = 'INR', bool decimals = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final digits = (abs ~/ 100).toString();

  final buffer = StringBuffer();
  if (digits.length <= 3) {
    buffer.write(digits);
  } else {
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    for (var i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 2 == 0) {
        buffer.write(',');
      }
      buffer.write(head[i]);
    }
    buffer.write(',$tail');
  }
  if (decimals) {
    buffer.write('.${(abs % 100).toString().padLeft(2, '0')}');
  }

  final prefix = currency == 'INR' ? '₹' : '$currency ';
  return '${negative ? '-' : ''}$prefix$buffer';
}

/// Fields for a new expense, typed in or detected from an SMS or app
/// notification. Amounts are in paise.
class ExpenseInput {
  const ExpenseInput({
    required this.amountPaise,
    required this.bankName,
    required this.accountType,
    required this.type,
    this.currency = 'INR',
    this.vendor = '',
    this.vendorUpi = '',
    this.occurredAt,
    this.source = 'manual',
    this.sourceRef,
  });

  final int amountPaise;
  final String currency;
  final String bankName;
  final String accountType;

  /// `debit` or `credit`.
  final String type;
  final String vendor;
  final String vendorUpi;

  /// When the payment happened; the server uses "now" when omitted.
  final DateTime? occurredAt;

  /// `manual`, `sms` or `notification`.
  final String source;

  /// Identifies the SMS or notification this came from so it is only saved
  /// once.
  final String? sourceRef;

  Map<String, Object> toJson() => {
    'amount_paise': amountPaise,
    'currency': currency,
    'bank_name': bankName,
    'account_type': accountType,
    'type': type,
    'vendor': vendor,
    'vendor_upi': vendorUpi,
    'occurred_at': ?occurredAt?.toUtc().toIso8601String(),
    if (source != 'manual') 'source': source,
    'source_ref': ?sourceRef,
  };
}

/// A transaction saved by the API.
class Expense {
  const Expense({
    required this.id,
    required this.amountPaise,
    required this.currency,
    required this.bankName,
    required this.accountType,
    required this.type,
    this.vendor = '',
    this.vendorUpi = '',
    this.category = '',
    this.source = 'manual',
    this.occurredAt,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final amount = json['amount_paise'];
    final source = text('source');
    return Expense(
      id: text('id'),
      amountPaise: amount is num ? amount.toInt() : 0,
      currency: text('currency'),
      bankName: text('bank_name'),
      accountType: text('account_type'),
      type: text('type'),
      vendor: text('vendor'),
      vendorUpi: text('vendor_upi'),
      category: text('category'),
      source: source.isEmpty ? 'manual' : source,
      occurredAt: DateTime.tryParse(text('occurred_at'))?.toLocal(),
      createdAt: DateTime.tryParse(text('created_at'))?.toLocal(),
    );
  }

  final String id;
  final int amountPaise;
  final String currency;
  final String bankName;
  final String accountType;
  final String type;
  final String vendor;
  final String vendorUpi;

  /// Set by the server's classifier, e.g. `Food`. `Unknown` when it could not
  /// decide or was unavailable.
  final String category;

  /// `manual`, `sms` or `notification`.
  final String source;
  final DateTime? occurredAt;
  final DateTime? createdAt;

  bool get isCredit => type == 'credit';
  bool get isAutoDetected => source == 'sms' || source == 'notification';

  /// Payment time, falling back to when it was saved.
  DateTime? get when => occurredAt ?? createdAt;

  String get title => vendor.isNotEmpty
      ? vendor
      : (vendorUpi.isNotEmpty ? vendorUpi : bankName);

  /// e.g. `₹450.50` for INR, `USD 450.50` otherwise.
  String get formattedAmount => formatPaise(amountPaise, currency: currency);
}
