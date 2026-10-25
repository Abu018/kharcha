import '../models/expense.dart';
import 'sms_source.dart';

/// Turns a bank or UPI transaction SMS into an [ExpenseInput], or returns
/// `null` for anything that is not a completed payment (OTPs, offers,
/// reminders, failed transactions, personal messages).
ExpenseInput? parsePaymentSms(SmsMessageData sms) {
  final body = sms.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = body.toLowerCase();

  if (body.isEmpty || _isPersonalNumber(sms.address)) {
    return null;
  }
  if (_ignored.any(lower.contains)) {
    return null;
  }
  if (!_accountWords.hasMatch(lower)) {
    return null;
  }

  final type = _type(lower);
  if (type == null) {
    return null;
  }
  final amount = _amountPaise(body);
  if (amount == null) {
    return null;
  }

  final upi = _upiId(body);
  var vendor = _vendor(body, type);
  if (vendor.isEmpty && upi.isNotEmpty) {
    vendor = _prettify(upi.split('@').first);
  }

  return ExpenseInput(
    amountPaise: amount,
    bankName: _bank(sms.address) ?? _bank(body) ?? 'Bank',
    accountType: _accountType(lower),
    type: type,
    vendor: vendor,
    vendorUpi: upi,
    occurredAt: sms.date,
    source: 'sms',
    sourceRef: sms.ref,
  );
}

const _ignored = [
  'otp',
  'one time password',
  'one-time password',
  'verification code',
  'will be debited',
  'will be credited',
  'is due',
  'due on',
  'due date',
  'payment reminder',
  'requested money',
  'has requested',
  'collect request',
  'pre-approved',
  'pre approved',
  'failed',
  'declined',
  'unsuccessful',
  'could not be',
  'get up to',
  'cashback up to',
  'apply now',
  'click here to claim',
];

final _accountWords = RegExp(
  r'a/c|acct|account|card|upi|vpa|wallet|bank|imps|neft|rtgs',
);

final _creditWords = RegExp(
  r'\b(credited|received|refund(ed)?|deposited|reversed|cashback of)\b',
);
final _debitWords = RegExp(
  r'\b(debited|spent|paid|sent|withdrawn|purchase|deducted|transferred|txn of|used for|payment of)\b',
);

/// Whichever keyword comes first decides the direction: "Rs 500 debited from
/// your a/c and credited to VPA x@y" is a debit for the user.
String? _type(String lower) {
  final credit = _creditWords.firstMatch(lower);
  final debit = _debitWords.firstMatch(lower);
  if (credit == null && debit == null) {
    return null;
  }
  if (credit == null) {
    return 'debit';
  }
  if (debit == null) {
    return 'credit';
  }
  return debit.start <= credit.start ? 'debit' : 'credit';
}

final _amount = RegExp(
  r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

/// Some banks (e.g. SBI UPI) omit the currency: "debited by 120.0".
final _bareAmount = RegExp(
  r'\b(?:debited|credited|paid|sent|spent)\s+(?:by|with|for|of)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b',
  caseSensitive: false,
);

/// The first amount that is not a balance or limit.
int? _amountPaise(String body) {
  for (final match in _amount.allMatches(body)) {
    final before = body
        .substring(match.start < 20 ? 0 : match.start - 20, match.start)
        .toLowerCase();
    if (RegExp(r'(bal|balance|limit|avl|available)[\s.:=-]*$')
        .hasMatch(before)) {
      continue;
    }
    final total = _toPaise(match.group(1)!);
    if (total != null) {
      return total;
    }
  }
  final bare = _bareAmount.firstMatch(body);
  return bare == null ? null : _toPaise(bare.group(1)!);
}

int? _toPaise(String text) {
  final parts = text.replaceAll(',', '').split('.');
  final rupees = int.tryParse(parts[0]);
  if (rupees == null) {
    return null;
  }
  final paise = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final total = rupees * 100 + paise;
  return total > 0 ? total : null;
}

final _upi = RegExp(r'\b([a-zA-Z0-9][a-zA-Z0-9.\-_]{1,}@[a-zA-Z]{2,})\b');

String _upiId(String body) {
  for (final match in _upi.allMatches(body)) {
    final id = match.group(1)!;
    // Skip e-mail addresses such as alerts@hdfcbank.net.
    final after = body.substring(match.end);
    if (after.startsWith('.') && RegExp(r'^\.[a-z]').hasMatch(after)) {
      continue;
    }
    return id.toLowerCase();
  }
  return '';
}

const _stop =
    r'(?=\s+(?:on|via|using|ref|refno|txn|for|dated|upi|from|thru|through|avl|bal|-)\b|[.,;(]|\s*$)';

String _vendor(String body, String type) {
  final patterns = <RegExp>[
    RegExp(r'\bat\s+(.{2,40}?)' + _stop, caseSensitive: false),
    if (type == 'debit')
      RegExp(
        r'\b(?:paid to|sent to|trf to|transfer(?:red)? to|to vpa|to)\s+(.{2,40}?)' +
            _stop,
        caseSensitive: false,
      ),
    if (type == 'credit')
      RegExp(
        r'\b(?:received from|from vpa|by vpa|from|by)\s+(.{2,40}?)' + _stop,
        caseSensitive: false,
      ),
    RegExp(r'\binfo[:\-]\s*(.{2,40}?)' + _stop, caseSensitive: false),
    // Card alerts: "... on 24-Oct-26 on AMAZON."
    RegExp(
      r"\bon\s+([A-Za-z][A-Za-z0-9&' ]{1,40}?)" + _stop,
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    for (final match in pattern.allMatches(body)) {
      final candidate = _cleanVendor(match.group(1)!);
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
  }
  return '';
}

String _cleanVendor(String raw) {
  var text = raw
      .replaceAll(
        RegExp(r'^(vpa|upi|mr\.?|ms\.?|m/s\.?)\s+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[*:\-\s]+$'), '')
      .trim();
  final lower = text.toLowerCase();
  if (text.length < 2 ||
      _notVendors.contains(lower) ||
      _months.hasMatch(lower) ||
      RegExp(r'^(your|you|a/c|ac|acct|account|card|xx|x+\d|\*|\d)')
          .hasMatch(lower) ||
      RegExp(r'^[\d\s/:-]+$').hasMatch(text) ||
      lower.contains('a/c') ||
      lower.contains('account')) {
    return '';
  }
  if (text.contains('@')) {
    text = text.split('@').first;
  }
  return _prettify(text);
}

const _notVendors = {
  'upi',
  'imps',
  'neft',
  'rtgs',
  'vpa',
  'bank',
  'date',
  'your',
  'mobile',
  'net banking',
  'netbanking',
};

final _months = RegExp(
  r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b',
);

/// `RELIANCE FRESH` -> `Reliance Fresh`, `swiggy.food` -> `Swiggy Food`.
String _prettify(String text) {
  final words = text
      .replaceAll(RegExp(r'[._]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  return words
      .map(
        (w) =>
            w.length <= 3 && w == w.toUpperCase() && !RegExp(r'\d').hasMatch(w)
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _accountType(String lower) {
  if (lower.contains('credit card') ||
      (RegExp(r'\bcard\b').hasMatch(lower) && !lower.contains('debit card'))) {
    return 'credit_card';
  }
  if (lower.contains('wallet')) {
    return 'upi_wallet';
  }
  return 'savings';
}

const _banks = {
  'HDFC': 'HDFC Bank',
  'ICICI': 'ICICI Bank',
  'SBI': 'SBI',
  'AXIS': 'Axis Bank',
  'KOTAK': 'Kotak Bank',
  'KMBL': 'Kotak Bank',
  'PNB': 'PNB',
  'BOB': 'Bank of Baroda',
  'BARODA': 'Bank of Baroda',
  'CANBNK': 'Canara Bank',
  'CANARA': 'Canara Bank',
  'UNION': 'Union Bank',
  'UBOI': 'Union Bank',
  'IDFC': 'IDFC First Bank',
  'YESBNK': 'Yes Bank',
  'YES BANK': 'Yes Bank',
  'INDUS': 'IndusInd Bank',
  'FEDBNK': 'Federal Bank',
  'FEDERAL': 'Federal Bank',
  'IDBI': 'IDBI Bank',
  'BOIIND': 'Bank of India',
  'AUBANK': 'AU Bank',
  'RBL': 'RBL Bank',
  'PAYTM': 'Paytm',
  'PYTM': 'Paytm',
  'AIRTEL': 'Airtel Payments Bank',
  'JUPITER': 'Jupiter',
  'AMAZON': 'Amazon Pay',
};

String? _bank(String text) {
  final upper = text.toUpperCase();
  for (final entry in _banks.entries) {
    if (upper.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

bool _isPersonalNumber(String address) =>
    RegExp(r'^\+?[0-9 ]{10,}$').hasMatch(address.trim());
