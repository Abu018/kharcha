import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/services/payment_parser.dart';
import 'package:my_app/services/sms_source.dart';

final _date = DateTime(2026, 10, 25, 14, 5);

SmsMessageData sms(String address, String body) =>
    SmsMessageData(ref: 'sms:test', address: address, body: body, date: _date);

void main() {
  group('detects payments', () {
    test('HDFC UPI debit', () {
      final p = parsePaymentSms(
        sms(
          'VM-HDFCBK',
          'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 25/10/26\n'
              'Ref 429812345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808',
        ),
      )!;
      expect(p.type, 'debit');
      expect(p.amountPaise, 25000);
      expect(p.vendor, 'Swiggy');
      expect(p.bankName, 'HDFC Bank');
      expect(p.accountType, 'savings');
      expect(p.source, 'sms');
      expect(p.sourceRef, 'sms:test');
      expect(p.occurredAt, _date);
    });

    test('SBI UPI debit without a currency symbol', () {
      final p = parsePaymentSms(
        sms(
          'JD-SBIUPI',
          'Dear UPI user A/C X1234 debited by 120.0 on date 25Oct26 trf to '
              'RAMESH KUMAR Refno 429812345678. If not u? call 1800111109. -SBI',
        ),
      )!;
      expect(p.type, 'debit');
      expect(p.amountPaise, 12000);
      expect(p.vendor, 'Ramesh Kumar');
      expect(p.bankName, 'SBI');
    });

    test('ICICI credit card spend skips the available limit', () {
      final p = parsePaymentSms(
        sms(
          'AX-ICICIT',
          'INR 1,499.00 spent using ICICI Bank Card XX9876 on 24-Oct-26 on AMAZON. '
              'Avl Limit: INR 98,501.00. If not you, call 1800 2662/SMS BLOCK 9876 to 9215676766.',
        ),
      )!;
      expect(p.type, 'debit');
      expect(p.amountPaise, 149900);
      expect(p.vendor, 'Amazon');
      expect(p.accountType, 'credit_card');
      expect(p.bankName, 'ICICI Bank');
    });

    test('card purchase "at" a merchant', () {
      final p = parsePaymentSms(
        sms(
          'BZ-AXISBK',
          'Rs.450.50 debited from A/c XX1234 at RELIANCE FRESH on 23-10-26. Avl Bal Rs.10,200.00',
        ),
      )!;
      expect(p.amountPaise, 45050);
      expect(p.vendor, 'Reliance Fresh');
      expect(p.bankName, 'Axis Bank');
    });

    test('UPI credit from a person', () {
      final p = parsePaymentSms(
        sms(
          'VM-KOTAKB',
          'Rs.5000.00 credited to your Kotak Bank A/c XX4321 on 24-10-26 by UPI '
              'from priya.s@okaxis. UPI Ref 4298123. -Kotak',
        ),
      )!;
      expect(p.type, 'credit');
      expect(p.amountPaise, 500000);
      expect(p.vendorUpi, 'priya.s@okaxis');
      expect(p.vendor, isNotEmpty);
      expect(p.bankName, 'Kotak Bank');
    });

    test('Paytm payment', () {
      final p = parsePaymentSms(
        sms(
          'AD-PAYTMB',
          'Rs.320 paid to Zomato via Paytm UPI from your wallet. Txn ID 1234567',
        ),
      )!;
      expect(p.type, 'debit');
      expect(p.amountPaise, 32000);
      expect(p.vendor, 'Zomato');
      expect(p.accountType, 'upi_wallet');
      expect(p.bankName, 'Paytm');
    });

    test('debit then credit wording is a debit', () {
      final p = parsePaymentSms(
        sms(
          'VM-HDFCBK',
          'Rs 99 debited from a/c **1234 and credited to chai.point@ybl via UPI',
        ),
      )!;
      expect(p.type, 'debit');
      expect(p.vendorUpi, 'chai.point@ybl');
    });

    test('ignores the bank e-mail address as a UPI id', () {
      final p = parsePaymentSms(
        sms(
          'VM-HDFCBK',
          'Rs.75 spent on HDFC Bank Card x1234 at UBER on 2026-10-25. '
              'Not you? Mail alerts@hdfcbank.net',
        ),
      )!;
      expect(p.vendor, 'Uber');
      expect(p.vendorUpi, isEmpty);
    });
  });

  group('ignores', () {
    for (final (name, address, body) in [
      (
        'OTP',
        'VM-HDFCBK',
        'Your OTP for txn of Rs 2000 at AMAZON on HDFC Bank card is 123456',
      ),
      (
        'offers',
        'VM-PAYTMB',
        'Get up to Rs 500 cashback on UPI payments. Pay bills from your Paytm wallet',
      ),
      (
        'upcoming debits',
        'VM-HDFCBK',
        'Rs 1,200 will be debited from your a/c XX1234 on 01-11-26 for NETFLIX',
      ),
      (
        'payment requests',
        'VM-ICICIB',
        'RAMESH has requested money of Rs 500 on UPI. Pay via iMobile',
      ),
      (
        'failed transactions',
        'VM-SBIUPI',
        'Your UPI txn of Rs 300 to ZOMATO has failed. A/c not debited',
      ),
      (
        'balance updates',
        'VM-SBIINB',
        'Avl balance in your a/c XX1234 is Rs 5,000.00 as on 25-10-26',
      ),
      (
        'personal messages',
        '+919876543210',
        'I sent you Rs 500 on UPI, check your account',
      ),
    ]) {
      test(name, () => expect(parsePaymentSms(sms(address, body)), isNull));
    }
  });
}
