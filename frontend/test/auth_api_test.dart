import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/api/auth_api.dart';
import 'package:my_app/api/expense_api.dart';
import 'package:my_app/api/profile_api.dart';
import 'package:my_app/models/expense.dart';
import 'package:my_app/screens/add_expense_screen.dart';

String fakeJwt(Map<String, Object> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

http.Response envelope(int status, String message, [Object? data]) {
  return http.Response(
    jsonEncode({'success': status < 400, 'message': message, 'data': ?data}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test('requests fail clearly when no API address was configured', () {
    final api = AuthApi(
      baseUrl: '',
      client: MockClient((_) async => fail('should not send a request')),
    );

    expect(
      () => api.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('API_BASE_URL'),
        ),
      ),
    );
  });

  group('AuthApi.login', () {
    test('posts credentials and reads the session from the token', () async {
      late http.Request captured;
      final token = fakeJwt({
        'sub': 'user-1',
        'email': 'ada@example.com',
        'preferred_username': 'ada',
        'given_name': 'Ada',
        'family_name': 'Lovelace',
      });
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'Login successful', {
            'access_token': token,
            'refresh_token': 'refresh',
            'token_type': 'Bearer',
          });
        }),
      );

      final session = await api.login(
        email: 'ada@example.com',
        password: 'secret',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://example.test/api/v1/login');
      expect(jsonDecode(captured.body), {
        'email': 'ada@example.com',
        'password': 'secret',
      });
      expect(session.accessToken, token);
      expect(session.refreshToken, 'refresh');
      expect(session.userId, 'user-1');
      expect(session.userName, 'ada');
      expect(session.displayName, 'Ada Lovelace');
    });

    test('surfaces the server message on failure', () async {
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient(
          (_) async => envelope(401, 'invalid email or password'),
        ),
      );

      expect(
        () => api.login(email: 'ada@example.com', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'invalid email or password')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('AuthApi.refresh', () {
    test('exchanges the refresh token for a new session', () async {
      late http.Request captured;
      final token = fakeJwt({'sub': 'user-1', 'email': 'ada@example.com'});
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'Success', {
            'access_token': token,
            'refresh_token': 'rotated',
          });
        }),
      );

      final session = await api.refresh('old');

      expect(
        captured.url.toString(),
        'http://example.test/api/v1/auth/refresh',
      );
      expect(jsonDecode(captured.body), {'refresh_token': 'old'});
      expect(session.accessToken, token);
      expect(session.refreshToken, 'rotated');
      expect(session.email, 'ada@example.com');
    });

    test('flags an expired refresh token as unauthorized', () async {
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient(
          (_) async => envelope(401, 'invalid or expired refresh token'),
        ),
      );

      expect(
        () => api.refresh('old'),
        throwsA(
          isA<ApiException>().having((e) => e.isUnauthorized, '401', true),
        ),
      );
    });
  });

  group('AuthApi.register', () {
    test('posts the registration fields', () async {
      late http.Request captured;
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'Success');
        }),
      );

      await api.register(
        userName: 'ada',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        password: 'secret123',
      );

      expect(captured.url.toString(), 'http://example.test/api/v1/register');
      expect(jsonDecode(captured.body), {
        'user_name': 'ada',
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'email': 'ada@example.com',
        'password': 'secret123',
      });
    });

    test('reports a duplicate email', () async {
      final api = AuthApi(
        baseUrl: 'http://example.test',
        client: MockClient(
          (_) async => envelope(409, 'email already registered'),
        ),
      );

      expect(
        () => api.register(
          userName: 'ada',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
          password: 'secret123',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'email already registered',
          ),
        ),
      );
    });
  });

  group('ProfileApi.updateProfile', () {
    test('sends the bearer token and returns the saved name', () async {
      late http.Request captured;
      final api = ProfileApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'profile updated', {
            'user_id': 'user-1',
            'first_name': 'Ada',
            'last_name': 'King',
          });
        }),
      );

      final updated = await api.updateProfile(
        accessToken: 'token-123',
        profile: const Profile(firstName: 'Ada', lastName: 'King'),
      );

      expect(captured.method, 'PUT');
      expect(captured.url.toString(), 'http://example.test/api/v1/profile');
      expect(captured.headers['Authorization'], 'Bearer token-123');
      expect(jsonDecode(captured.body), {
        'first_name': 'Ada',
        'last_name': 'King',
      });
      expect(updated.firstName, 'Ada');
      expect(updated.lastName, 'King');
    });

    test('sends age and salary when they are set', () async {
      late http.Request captured;
      final api = ProfileApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'profile updated', {
            'first_name': 'Ada',
            'last_name': 'King',
            'age': 36,
            'salary': 85000,
          });
        }),
      );

      final updated = await api.updateProfile(
        accessToken: 'token-123',
        profile: const Profile(
          firstName: 'Ada',
          lastName: 'King',
          age: 36,
          salaryRupees: 85000,
        ),
      );

      expect(jsonDecode(captured.body), {
        'first_name': 'Ada',
        'last_name': 'King',
        'age': 36,
        'salary': 85000,
      });
      expect(updated.age, 36);
      expect(updated.salaryRupees, 85000);
    });

    test('flags an expired token as unauthorized', () async {
      final api = ProfileApi(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => envelope(401, 'invalid token')),
      );

      expect(
        () => api.updateProfile(
          accessToken: 'expired',
          profile: const Profile(firstName: 'Ada', lastName: 'King'),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            true,
          ),
        ),
      );
    });
  });

  group('ProfileApi.getProfile', () {
    test('reads the saved profile, with age and salary unset', () async {
      late http.Request captured;
      final api = ProfileApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'profile', {
            'first_name': 'Ada',
            'last_name': 'Lovelace',
            'age': null,
            'salary': null,
          });
        }),
      );

      final profile = await api.getProfile(accessToken: 'token-123');

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://example.test/api/v1/profile');
      expect(captured.headers['Authorization'], 'Bearer token-123');
      expect(profile.firstName, 'Ada');
      expect(profile.age, isNull);
      expect(profile.salaryRupees, isNull);
    });
  });

  group('ExpenseApi.createExpense', () {
    const input = ExpenseInput(
      amountPaise: 45050,
      bankName: 'HDFC',
      accountType: 'savings',
      type: 'debit',
      vendor: 'Swiggy',
      vendorUpi: 'swiggy@upi',
    );

    test('posts the expense with the bearer token', () async {
      late http.Request captured;
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(201, 'transaction saved successfully', {
            'id': 'tx-1',
            'created_at': '2026-10-25T17:00:00Z',
            'amount_paise': 45050,
            'currency': 'INR',
            'bank_name': 'HDFC',
            'account_type': 'savings',
            'type': 'debit',
            'vendor': 'Swiggy',
            'vendor_upi': 'swiggy@upi',
            'category': 'Food',
            'user_id': 'user-1',
          });
        }),
      );

      final saved = (await api.createExpense(
        accessToken: 'token-123',
        input: input,
      ))!;

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://example.test/api/v1/expense');
      expect(captured.headers['Authorization'], 'Bearer token-123');
      expect(jsonDecode(captured.body), {
        'amount_paise': 45050,
        'currency': 'INR',
        'bank_name': 'HDFC',
        'account_type': 'savings',
        'type': 'debit',
        'vendor': 'Swiggy',
        'vendor_upi': 'swiggy@upi',
      });
      expect(saved.id, 'tx-1');
      expect(saved.formattedAmount, '₹450.50');
      expect(saved.category, 'Food');
      expect(saved.createdAt?.toUtc(), DateTime.utc(2026, 10, 25, 17));
    });

    test('returns null when the SMS was already recorded', () async {
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient(
          (_) async => envelope(200, 'transaction already recorded'),
        ),
      );

      final saved = await api.createExpense(
        accessToken: 'token-123',
        input: const ExpenseInput(
          amountPaise: 100,
          bankName: 'HDFC Bank',
          accountType: 'savings',
          type: 'debit',
          source: 'sms',
          sourceRef: 'sms:abc',
        ),
      );

      expect(saved, isNull);
    });

    test('lists expenses newest first as returned', () async {
      late http.Request captured;
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'ok', [
            {
              'id': 'tx-2',
              'amount_paise': 9900,
              'currency': 'INR',
              'type': 'debit',
              'source': 'sms',
              'occurred_at': '2026-10-25T10:00:00Z',
            },
            {'id': 'tx-1', 'amount_paise': 100, 'type': 'credit'},
          ]);
        }),
      );

      final list = await api.listExpenses(accessToken: 'token-123');

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'http://example.test/api/v1/expenses?limit=200',
      );
      expect(list.map((e) => e.id), ['tx-2', 'tx-1']);
      expect(list.first.isAutoDetected, isTrue);
      expect(list.first.occurredAt?.toUtc(), DateTime.utc(2026, 10, 25, 10));
      expect(list.last.isCredit, isTrue);
    });

    test('sends SMS details for detected payments', () async {
      late http.Request captured;
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(201, 'saved', {'id': 'tx-3'});
        }),
      );

      await api.createExpense(
        accessToken: 't',
        input: ExpenseInput(
          amountPaise: 25000,
          bankName: 'HDFC Bank',
          accountType: 'savings',
          type: 'debit',
          vendor: 'Swiggy',
          occurredAt: DateTime.utc(2026, 10, 25, 8, 30),
          source: 'sms',
          sourceRef: 'sms:abc',
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['occurred_at'], '2026-10-25T08:30:00.000Z');
      expect(body['source'], 'sms');
      expect(body['source_ref'], 'sms:abc');
    });

    test('flags an expired token as unauthorized', () async {
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => envelope(401, 'invalid token')),
      );

      expect(
        () => api.createExpense(accessToken: 'expired', input: input),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            true,
          ),
        ),
      );
    });
  });

  group('ExpenseApi.listExpenses', () {
    test('sends the date range as inclusive YYYY-MM-DD days', () async {
      late http.Request captured;
      final api = ExpenseApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'ok', []);
        }),
      );

      await api.listExpenses(
        accessToken: 't',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59),
      );

      expect(
        captured.url.toString(),
        'http://example.test/api/v1/expenses?limit=200&start_date=2026-10-01&end_date=2026-10-31',
      );
    });
  });

  group('formatPaise', () {
    test('uses Indian digit grouping', () {
      expect(formatPaise(45050), '₹450.50');
      expect(formatPaise(12345678900), '₹12,34,56,789.00');
      expect(formatPaise(100000000, decimals: false), '₹10,00,000');
      expect(formatPaise(99900, currency: 'USD'), 'USD 999.00');
    });
  });

  group('parseAmountPaise', () {
    test('converts rupees to paise', () {
      expect(parseAmountPaise('450'), 45000);
      expect(parseAmountPaise('450.5'), 45050);
      expect(parseAmountPaise(' 450.05 '), 45005);
    });

    test('rejects zero, negatives and bad input', () {
      expect(parseAmountPaise('0'), isNull);
      expect(parseAmountPaise('-5'), isNull);
      expect(parseAmountPaise('4.505'), isNull);
      expect(parseAmountPaise('abc'), isNull);
      expect(parseAmountPaise(''), isNull);
    });
  });
}
