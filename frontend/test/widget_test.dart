import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/api/auth_api.dart';
import 'package:my_app/api/expense_api.dart';
import 'package:my_app/api/profile_api.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models/auth_session.dart';
import 'package:my_app/models/expense.dart';
import 'package:my_app/models/spending_chart.dart';
import 'package:my_app/screens/home_screen.dart';
import 'package:my_app/services/notification_source.dart';
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
  NotificationSource? notificationSource,
  SessionStore? sessionStore,
}) => MyApp(
  authApi: authApi,
  profileApi: profileApi,
  expenseApi: expenseApi ?? _FakeExpenseApi(_echo),
  smsSource: smsSource ?? _FakeSms(),
  notificationSource: notificationSource ?? _FakeNotifications(),
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
        profileApi: _FakeProfileApi((token, profile) {
          sentTokens.add(token);
          if (token == 'token') {
            throw const ApiException('invalid token', statusCode: 401);
          }
          return profile;
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
        profileApi: _FakeProfileApi((token, profile) {
          sentToken = token;
          return profile;
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

  testWidgets('the profile screen shows and saves age and salary', (
    tester,
  ) async {
    Profile? sent;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        profileApi: _FakeProfileApi(
          (_, profile) => sent = profile,
          saved: const Profile(
            firstName: 'Ada',
            lastName: 'Lovelace',
            age: 36,
            salaryRupees: 85000,
          ),
        ),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('edit-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('36'), findsOneWidget);
    expect(find.text('85000'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-age-field')), '37');
    await tester.enterText(
      find.byKey(const Key('profile-salary-field')),
      '90000',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(sent?.age, 37);
    expect(sent?.salaryRupees, 90000);
    expect(sent?.lastName, 'Lovelace');
  });

  testWidgets('an age outside 1 to 120 is rejected before saving', (
    tester,
  ) async {
    var saves = 0;
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        profileApi: _FakeProfileApi((_, profile) {
          saves++;
          return profile;
        }),
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('edit-profile-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-age-field')), '200');
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter an age between 1 and 120.'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('an expired token on profile save signs the user out', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        profileApi: _FakeProfileApi(
          (_, _) => throw const ApiException('invalid token', statusCode: 401),
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

  testWidgets('picking a date range reloads that range, clearing resets it', (
    tester,
  ) async {
    final api = _FakeExpenseApi(_echo);
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: api,
      ),
    );
    await _signIn(tester);
    expect(api.listRanges, [(null, null)]);

    await tester.ensureVisible(find.byKey(const Key('date-range-button')));
    await tester.tap(find.byKey(const Key('date-range-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());
    final monthStart = DateTime(today.year, today.month);
    expect(api.listRanges.last, (monthStart, today));
    expect(
      find.text(formatDateRange(DateTimeRange(start: monthStart, end: today))),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('date-range-clear')));
    await tester.pumpAndSettle();

    expect(api.listRanges.last, (null, null));
    expect(find.byKey(const Key('date-range-clear')), findsNothing);
  });

  test('formatDateRange shows one day, a range, and other years', () {
    final now = DateTime(2026, 10, 26);
    String fmt(DateTime a, DateTime b) => formatDateRange(
      DateTimeRange(start: a, end: b),
      now: now,
    );

    expect(fmt(DateTime(2026, 10, 5), DateTime(2026, 10, 5)), '5 Oct');
    expect(
      fmt(DateTime(2026, 10, 1), DateTime(2026, 10, 15)),
      '1 Oct – 15 Oct',
    );
    expect(
      fmt(DateTime(2025, 12, 20), DateTime(2026, 1, 3)),
      '20 Dec 2025 – 3 Jan',
    );
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
    expect(find.text('Added 1 payment automatically'), findsOneWidget);
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

  testWidgets(
    'turning on notification access imports queued payment notifications',
    (tester) async {
      final api = _FakeExpenseApi(_echo);
      final notifications = _FakeNotifications(
        supported: true,
        queued: [
          _notification('notif:1', '₹250 paid to Swiggy', 'Paid via HDFC Bank'),
          _notification('notif:2', 'Win ₹100 cashback', 'Scratch card waiting'),
        ],
      );
      await _pump(
        tester,
        _app(
          authApi: _FakeAuthApi(onLogin: () => _session),
          expenseApi: api,
          notificationSource: notifications,
        ),
      );

      await _signIn(tester);
      await tester.tap(find.byKey(const Key('enable-notifications')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-disclosure')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('notification-disclosure-continue')),
      );
      await tester.pumpAndSettle();
      expect(notifications.settingsOpened, 1);
      expect(api.created, isEmpty);

      // The user turns on access in Android settings and comes back.
      notifications.access = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(api.created, hasLength(1));
      expect(api.created.single.source, 'notification');
      expect(api.created.single.sourceRef, 'notif:1');
      expect(api.created.single.bankName, 'Google Pay');
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Auto-detect is on'), findsOneWidget);
      expect(notifications.queued, isEmpty);
    },
  );

  testWidgets('a payment notification posted while the app is open is added', (
    tester,
  ) async {
    final api = _FakeExpenseApi(_echo);
    final notifications = _FakeNotifications(supported: true, access: true);
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: api,
        notificationSource: notifications,
      ),
    );

    await _signIn(tester);
    expect(find.text('Auto-detect is on'), findsOneWidget);
    expect(find.byKey(const Key('enable-notifications')), findsNothing);

    notifications.incomingController.add(
      _notification('notif:live', 'Paid ₹99 to Zomato', ''),
    );
    await tester.pumpAndSettle();

    expect(api.created.single.sourceRef, 'notif:live');
    expect(find.text('Spent ₹99.00 · Zomato'), findsOneWidget);
    expect(notifications.acknowledged, contains('notif:live'));
  });

  testWidgets('the monthly chart loads after sign in and after saving', (
    tester,
  ) async {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final api = _FakeExpenseApi(
      _echo,
      chart: SpendingChart(
        title: 'Spent in 2026',
        xLabel: 'Month',
        yLabel: 'Spent (₹)',
        points: [
          for (final (i, m) in months.indexed)
            ChartPoint(label: m, paise: i == 1 ? 20000 : 1000),
        ],
      ),
    );
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        expenseApi: api,
      ),
    );

    await _signIn(tester);
    expect(find.text('Spent in 2026'), findsOneWidget);
    expect(find.byKey(const Key('monthly-chart')), findsOneWidget);
    expect(api.chartLoads, 1);

    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '120',
    );
    await tester.enterText(find.byKey(const Key('expense-bank-field')), 'HDFC');
    await tester.ensureVisible(find.byKey(const Key('expense-save-button')));
    await tester.tap(find.byKey(const Key('expense-save-button')));
    await tester.pumpAndSettle();

    expect(api.chartLoads, 2);
  });

  testWidgets('declining the notification explanation opens nothing', (
    tester,
  ) async {
    final notifications = _FakeNotifications(supported: true);
    await _pump(
      tester,
      _app(
        authApi: _FakeAuthApi(onLogin: () => _session),
        notificationSource: notifications,
      ),
    );

    await _signIn(tester);
    await tester.tap(find.byKey(const Key('enable-notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(notifications.settingsOpened, 0);
    expect(find.byKey(const Key('enable-notifications')), findsOneWidget);
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
  _FakeProfileApi(this._update, {this.saved});

  final Profile Function(String token, Profile profile) _update;

  /// What `GET /profile` returns; `null` makes it fail like a network error.
  final Profile? saved;

  @override
  Future<Profile> getProfile({required String accessToken}) async {
    final profile = saved;
    if (profile == null) {
      throw const ApiException('offline');
    }
    return profile;
  }

  @override
  Future<Profile> updateProfile({
    required String accessToken,
    required Profile profile,
  }) async {
    return _update(accessToken, profile);
  }
}

class _FakeExpenseApi extends ExpenseApi {
  _FakeExpenseApi(this._create, {this.history = const [], this.chart});

  final Expense Function(String token, ExpenseInput input) _create;
  final List<Expense> history;
  final created = <ExpenseInput>[];

  /// What `GET /expenses/monthly` returns; `null` fails like being offline,
  /// which hides the chart.
  SpendingChart? chart;
  var chartLoads = 0;

  @override
  Future<SpendingChart> monthlySpending({
    required String accessToken,
    int? year,
  }) async {
    chartLoads++;
    final chart = this.chart;
    if (chart == null) {
      throw const ApiException('offline');
    }
    return chart;
  }

  @override
  Future<Expense?> createExpense({
    required String accessToken,
    required ExpenseInput input,
  }) async {
    created.add(input);
    return _create(accessToken, input);
  }

  /// The `(startDate, endDate)` of every list request, in order.
  final listRanges = <(DateTime?, DateTime?)>[];

  @override
  Future<List<Expense>> listExpenses({
    required String accessToken,
    int limit = 200,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    listRanges.add((startDate, endDate));
    return history;
  }
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
  Future<bool> isDeclared() async => supported;

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

class _FakeNotifications extends NotificationSource {
  _FakeNotifications({
    this.supported = false,
    this.access = false,
    List<PaymentNotification> queued = const [],
  }) : queued = [...queued];

  final bool supported;
  bool access;
  final List<PaymentNotification> queued;
  final acknowledged = <String>[];
  var settingsOpened = 0;
  final incomingController = StreamController<PaymentNotification>.broadcast();

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<List<PaymentNotification>> pending() async => [...queued];

  @override
  Future<void> acknowledge(List<String> refs) async {
    acknowledged.addAll(refs);
    queued.removeWhere((n) => refs.contains(n.ref));
  }

  @override
  Stream<PaymentNotification> incoming() => incomingController.stream;
}

PaymentNotification _notification(String ref, String title, String text) =>
    PaymentNotification(
      ref: ref,
      app: 'Google Pay',
      title: title,
      text: text,
      date: DateTime.now().subtract(const Duration(minutes: 5)),
    );

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
