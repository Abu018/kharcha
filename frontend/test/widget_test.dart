import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/api/auth_api.dart';
import 'package:my_app/api/expense_api.dart';
import 'package:my_app/api/profile_api.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models/auth_session.dart';
import 'package:my_app/models/expense.dart';
import 'package:my_app/services/session_store.dart';
import 'package:my_app/services/sms_source.dart';

const _session = AuthSession(
  accessToken: 'token',
  email: 'ada@example.com',
  userId: 'user-1',
  firstName: 'Ada',
  lastName: 'Lovelace',
);

const _hdfcSms =
    'Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 25/10/26 Ref 429812345678';

Widget _app({
  AuthApi? authApi,
  ProfileApi? profileApi,
  ExpenseApi? expenseApi,
  SmsSource? smsSource,
  SessionStore? sessionStore,
}) => MyApp(
  authApi: authApi,
  profileApi: profileApi,
  expenseApi: expenseApi ?? _FakeExpenseApi(_echo),
  smsSource: smsSource ?? _FakeSms(),
  sessionStore: sessionStore ?? _FakeStore(),
);

/// Pumps [app] on a phone-sized screen (Galaxy M34: 1080x2340 px) and waits
/// for the saved session to be restored.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.8125;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

AuthSession _withRefresh(AuthSession s, String refreshToken) => AuthSession(
  accessToken: s.accessToken,
  refreshToken: refreshToken,
  email: s.email,
  userId: s.userId,
  firstName: s.firstName,
  lastName: s.lastName,
);

var _nextId = 0;

Expense _echo(String token, ExpenseInput input) => Expense(
  id: 'tx-${_nextId++}',
  amountPaise: input.amountPaise,
  currency: input.currency,
  bankName: input.bankName,
  accountType: input.accountType,
  type: input.type,
  vendor: input.vendor,
  vendorUpi: input.vendorUpi,
  source: input.source,
  occurredAt: input.occurredAt,
  createdAt: DateTime.now(),
);

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('email-field')),
    'ada@example.com',
  );
  await tester.enterText(find.byKey(const Key('password-field')), 'secret');
  await tester.ensureVisible(find.byKey(const Key('sign-in-button')));
  await tester.tap(find.byKey(const Key('sign-in-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty sign in shows validation and does not call the API', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () {
            calls++;
            return _session;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('sign-in-button')));
    await tester.pump();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('successful sign in opens the home screen', (tester) async {
    await _pump(tester, _app(authApi: _FakeAuthApi(onLogin: () => _session)));

    await _signIn(tester);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
  });

  testWidgets('a failed sign in stays on the form and shows the error', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => throw const ApiException('invalid email or password'),
        ),
      ),
    );

    await _signIn(tester);

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('invalid email or password'), findsOneWidget);
  });

  testWidgets('sign out returns to the login form', (tester) async {
    await _pump(tester, _app(authApi: _FakeAuthApi(onLogin: () => _session)));

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('sign-out-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email-field')), findsOneWidget);
  });

  testWidgets('sign in remembers the session and sign out forgets it', (
    tester,
  ) async {
    final store = _FakeStore();
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => _withRefresh(_session, 'refresh-1'),
        ),
        sessionStore: store,
      ),
    );

    await _signIn(tester);
    expect(store.token, 'refresh-1');
    expect(store.email, 'ada@example.com');

    await tester.tap(find.byKey(const Key('sign-out-button')));
    await tester.pumpAndSettle();

    expect(store.token, isNull);
    final email = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('email-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(email.controller!.text, 'ada@example.com');
  });

  testWidgets('a saved session signs straight in on launch', (tester) async {
    String? usedToken;
    final store = _FakeStore(token: 'saved', email: 'ada@example.com');
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => throw StateError('should not ask for the password'),
          onRefresh: (token) {
            usedToken = token;
            return _withRefresh(_session, 'rotated');
          },
        ),
        sessionStore: store,
      ),
    );

    expect(usedToken, 'saved');
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(store.token, 'rotated');
  });

  testWidgets('an expired saved session shows the sign in form', (
    tester,
  ) async {
    final store = _FakeStore(token: 'stale', email: 'ada@example.com');
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        sessionStore: store,
      ),
    );

    expect(find.byKey(const Key('email-field')), findsOneWidget);
    expect(find.text('Your session expired. Sign in again.'), findsOneWidget);
    expect(store.token, isNull);
  });

  testWidgets('an expired access token is refreshed and the call retried', (
    tester,
  ) async {
    final sentTokens = <String>[];
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => _withRefresh(_session, 'refresh-1'),
          onRefresh: (_) => _withRefresh(
            const AuthSession(
              accessToken: 'fresh',
              email: 'ada@example.com',
              userId: 'user-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
            ),
            'refresh-2',
          ),
        ),
        profileApi: _FakeProfileApi((token, first, last) {
          sentTokens.add(token);
          if (token == 'token') {
            throw const ApiException('invalid token', statusCode: 401);
          }
          return ProfileUpdate(firstName: first, lastName: last);
        }),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('edit-profile-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-last-name-field')),
      'King',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(sentTokens, ['token', 'fresh']);
    expect(find.text('Ada King'), findsOneWidget);
  });

  testWidgets('registering returns to login with the email filled in', (
    tester,
  ) async {
    String? registeredEmail;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => _session,
          onRegister: (email) => registeredEmail = email,
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('create-account-button')));
    await tester.tap(find.byKey(const Key('create-account-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('register-username-field')),
      'ada',
    );
    await tester.enterText(
      find.byKey(const Key('register-first-name-field')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('register-last-name-field')),
      'Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'ada@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'secret123',
    );
    await tester.ensureVisible(find.byKey(const Key('register-button')));
    await tester.tap(find.byKey(const Key('register-button')));
    await tester.pumpAndSettle();

    expect(registeredEmail, 'ada@example.com');
    expect(find.byKey(const Key('login-notice')), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
  });

  testWidgets('a duplicate email is shown on the register form', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(
          onLogin: () => _session,
          onRegister: (_) =>
              throw const ApiException('email already registered'),
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('create-account-button')));
    await tester.tap(find.byKey(const Key('create-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('register-username-field')),
      'ada',
    );
    await tester.enterText(
      find.byKey(const Key('register-first-name-field')),
      'Ada',
    );
    await tester.enterText(
      find.byKey(const Key('register-last-name-field')),
      'L',
    );
    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'ada@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'secret123',
    );
    await tester.ensureVisible(find.byKey(const Key('register-button')));
    await tester.tap(find.byKey(const Key('register-button')));
    await tester.pumpAndSettle();

    expect(find.text('email already registered'), findsOneWidget);
  });

  testWidgets('editing the profile updates the name on the home screen', (
    tester,
  ) async {
    String? sentToken;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        profileApi: _FakeProfileApi((token, first, last) {
          sentToken = token;
          return ProfileUpdate(firstName: first, lastName: last);
        }),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('edit-profile-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profile-last-name-field')),
      'King',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(sentToken, 'token');
    expect(find.text('Ada King'), findsOneWidget);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('an expired token on profile save signs the user out', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        profileApi: _FakeProfileApi(
          (_, _, _) =>
              throw const ApiException('invalid token', statusCode: 401),
        ),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('edit-profile-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email-field')), findsOneWidget);
    expect(find.text('Your session expired. Sign in again.'), findsOneWidget);
  });

  testWidgets('adding an expense saves it and lists it on the home screen', (
    tester,
  ) async {
    String? sentToken;
    ExpenseInput? sentInput;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: _FakeExpenseApi((token, input) {
          sentToken = token;
          sentInput = input;
          return Expense(
            id: 'tx-1',
            amountPaise: input.amountPaise,
            currency: input.currency,
            bankName: input.bankName,
            accountType: input.accountType,
            type: input.type,
            vendor: input.vendor,
          );
        }),
      ),
    );

    await _signIn(tester);
    expect(find.byKey(const Key('expenses-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '450.5',
    );
    await tester.enterText(find.byKey(const Key('expense-bank-field')), 'HDFC');
    await tester.enterText(
      find.byKey(const Key('expense-vendor-field')),
      'Swiggy',
    );
    await tester.ensureVisible(find.byKey(const Key('expense-save-button')));
    await tester.tap(find.byKey(const Key('expense-save-button')));
    await tester.pumpAndSettle();

    expect(sentToken, 'token');
    expect(sentInput?.amountPaise, 45050);
    expect(sentInput?.accountType, 'savings');
    expect(sentInput?.type, 'debit');
    expect(find.text('Expense saved'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('-₹450.50'), findsOneWidget);
  });

  testWidgets('an invalid amount is rejected without calling the API', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: _FakeExpenseApi((_, _) {
          calls++;
          throw StateError('should not be called');
        }),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-amount-field')), '0');
    await tester.ensureVisible(find.byKey(const Key('expense-save-button')));
    await tester.tap(find.byKey(const Key('expense-save-button')));
    await tester.pump();

    expect(find.text('Enter an amount like 450 or 450.50.'), findsOneWidget);
    expect(find.text('Enter the bank name.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a server error stays on the expense form', (tester) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: _FakeExpenseApi(
          (_, _) => throw const ApiException('failed to save transaction'),
        ),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-amount-field')), '99');
    await tester.enterText(find.byKey(const Key('expense-bank-field')), 'SBI');
    await tester.ensureVisible(find.byKey(const Key('expense-save-button')));
    await tester.tap(find.byKey(const Key('expense-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expense-error')), findsOneWidget);
    expect(find.text('failed to save transaction'), findsOneWidget);
  });

  testWidgets('saved expenses load from the server after sign in', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: _FakeExpenseApi(
          _echo,
          history: [
            Expense(
              id: 'old-1',
              amountPaise: 12000,
              currency: 'INR',
              bankName: 'SBI',
              accountType: 'savings',
              type: 'debit',
              vendor: 'Chai Point',
              category: 'Food',
              source: 'sms',
              occurredAt: DateTime.now(),
            ),
          ],
        ),
      ),
    );

    await _signIn(tester);

    expect(find.text('Chai Point'), findsOneWidget);
    expect(find.text('-₹120.00'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
  });

  testWidgets('turning on auto-detect imports payment SMS from the inbox', (
    tester,
  ) async {
    final api = _FakeExpenseApi(_echo);
    final sms = _FakeSms(
      supported: true,
      grantOnRequest: true,
      inbox: [
        _message('sms:1', 'VM-HDFCBK', _hdfcSms),
        _message('sms:2', 'VM-HDFCBK', 'Your OTP for txn of Rs 500 is 123456'),
        _message('sms:3', '+919876543210', 'Paid you Rs 100 on UPI'),
      ],
    );
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: api,
        smsSource: sms,
      ),
    );

    await _signIn(tester);
    expect(find.byKey(const Key('enable-auto-detect')), findsOneWidget);

    await tester.tap(find.byKey(const Key('enable-auto-detect')));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1));
    expect(api.created.single.source, 'sms');
    expect(api.created.single.sourceRef, 'sms:1');
    expect(api.created.single.amountPaise, 25000);
    expect(find.text('Added 1 payment from your messages'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Auto-detect is on'), findsOneWidget);
    expect(sms.lastSyncs['last_sms_sync:user-1'], isNotNull);
  });

  testWidgets('a payment SMS that arrives while the app is open is added', (
    tester,
  ) async {
    final api = _FakeExpenseApi(_echo);
    final sms = _FakeSms(supported: true, granted: true);
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: api,
        smsSource: sms,
      ),
    );

    await _signIn(tester);
    expect(find.text('Auto-detect is on'), findsOneWidget);

    sms.incomingController.add(_message('sms:live', 'VM-HDFCBK', _hdfcSms));
    await tester.pumpAndSettle();

    expect(api.created.single.sourceRef, 'sms:live');
    expect(find.text('Spent ₹250.00 · Swiggy'), findsOneWidget);
    expect(find.text('-₹250.00'), findsOneWidget);
  });

  testWidgets('declining SMS access keeps the turn-on card', (tester) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        smsSource: _FakeSms(supported: true),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('enable-auto-detect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('enable-auto-detect')), findsOneWidget);
    expect(
      find.text(
        'SMS access was not allowed. You can still add expenses by hand.',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi({required this.onLogin, this.onRegister, this.onRefresh});

  final AuthSession Function() onLogin;
  final void Function(String email)? onRegister;
  final AuthSession Function(String refreshToken)? onRefresh;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return onLogin();
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final onRefresh = this.onRefresh;
    if (onRefresh == null) {
      throw const ApiException('expired', statusCode: 401);
    }
    return onRefresh(refreshToken);
  }

  @override
  Future<void> register({
    required String userName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    onRegister?.call(email);
  }
}

class _FakeProfileApi extends ProfileApi {
  _FakeProfileApi(this._update);

  final ProfileUpdate Function(String token, String first, String last) _update;

  @override
  Future<ProfileUpdate> updateProfile({
    required String accessToken,
    required String firstName,
    required String lastName,
  }) async {
    return _update(accessToken, firstName, lastName);
  }
}

class _FakeExpenseApi extends ExpenseApi {
  _FakeExpenseApi(this._create, {this.history = const []});

  final Expense Function(String token, ExpenseInput input) _create;
  final List<Expense> history;
  final created = <ExpenseInput>[];

  @override
  Future<Expense?> createExpense({
    required String accessToken,
    required ExpenseInput input,
  }) async {
    created.add(input);
    return _create(accessToken, input);
  }

  @override
  Future<List<Expense>> listExpenses({
    required String accessToken,
    int limit = 200,
  }) async => history;
}

class _FakeSms extends SmsSource {
  _FakeSms({
    this.supported = false,
    this.granted = false,
    this.grantOnRequest = false,
    this.inbox = const [],
  });

  final bool supported;
  bool granted;
  final bool grantOnRequest;
  final List<SmsMessageData> inbox;
  final incomingController = StreamController<SmsMessageData>.broadcast();
  final lastSyncs = <String, DateTime>{};

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted = grantOnRequest;

  @override
  Future<List<SmsMessageData>> readInbox({
    required DateTime since,
    int limit = 300,
  }) async => inbox.where((m) => m.date.isAfter(since)).toList();

  @override
  Stream<SmsMessageData> incoming() => incomingController.stream;

  @override
  Future<DateTime?> lastSync(String key) async => lastSyncs[key];

  @override
  Future<void> setLastSync(String key, DateTime value) async =>
      lastSyncs[key] = value;
}

class _FakeStore extends SessionStore {
  _FakeStore({this.token, this.email});

  String? token;
  String? email;

  @override
  Future<String?> refreshToken() async => token;

  @override
  Future<String?> lastEmail() async => email;

  @override
  Future<void> save({required String refreshToken, String? email}) async {
    token = refreshToken;
    this.email = email ?? this.email;
  }

  @override
  Future<void> clear() async => token = null;
}

SmsMessageData _message(String ref, String address, String body) =>
    SmsMessageData(
      ref: ref,
      address: address,
      body: body,
      date: DateTime.now().subtract(const Duration(hours: 1)),
    );
