import 'dart:async';

import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'api/expense_api.dart';
import 'api/notification_api.dart';
import 'api/profile_api.dart';
import 'models/app_user.dart';
import 'models/auth_session.dart';
import 'models/expense.dart';
import 'models/expense_group.dart';
import 'models/spending_chart.dart';
import 'screens/app_shell.dart';
import 'screens/groups_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auto_detect.dart';
import 'services/notification_source.dart';
import 'services/push_service.dart';
import 'services/session_store.dart';
import 'services/sms_source.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.authApi,
    this.profileApi,
    this.expenseApi,
    this.smsSource,
    this.notificationSource,
    this.sessionStore,
    this.notificationApi,
    this.pushService,
  });

  final AuthApi? authApi;
  final ProfileApi? profileApi;
  final ExpenseApi? expenseApi;
  final SmsSource? smsSource;
  final NotificationSource? notificationSource;
  final SessionStore? sessionStore;
  final NotificationApi? notificationApi;
  final PushService? pushService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const _expiredNotice = 'Your session expired. Sign in again.';

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final AuthApi _authApi = widget.authApi ?? AuthApi();
  late final ProfileApi _profileApi = widget.profileApi ?? ProfileApi();
  late final ExpenseApi _expenseApi = widget.expenseApi ?? ExpenseApi();
  late final SmsSource _sms = widget.smsSource ?? SmsSource();
  late final NotificationSource _notifications =
      widget.notificationSource ?? NotificationSource();
  late final AutoDetector _detector = AutoDetector(
    sms: _sms,
    notifications: _notifications,
    api: _expenseApi,
  );
  late final SessionStore _store = widget.sessionStore ?? SessionStore();
  late final NotificationApi _notificationApi =
      widget.notificationApi ?? NotificationApi();
  late final PushService _push = widget.pushService ?? PushService();

  AuthSession? _session;
  String? _loginNotice;
  String? _lastEmail;
  bool _restoring = true;
  Future<AuthSession?>? _renewing;

  List<Expense> _expenses = const [];
  SpendingChart? _monthlyChart;

  /// Groups created since signing in, newest first.
  List<ExpenseGroup> _groups = const [];

  /// Days shown on the home screen, both inclusive; `null` shows everything.
  DateTimeRange? _range;
  bool _loadingExpenses = false;
  String? _loadError;

  AutoDetectState _autoDetect = AutoDetectState.unsupported;
  AutoDetectState _notificationDetect = AutoDetectState.unsupported;
  bool _syncing = false;
  bool _syncAgain = false;
  DateTime? _lastSynced;
  StreamSubscription<SmsMessageData>? _incoming;
  StreamSubscription<PaymentNotification>? _incomingNotifications;
  StreamSubscription<String>? _pushTokenRefreshes;
  StreamSubscription<PushMessage>? _pushMessages;

  bool get _detecting =>
      _autoDetect == AutoDetectState.on ||
      _notificationDetect == AutoDetectState.on;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incoming?.cancel();
    _incomingNotifications?.cancel();
    _pushTokenRefreshes?.cancel();
    _pushMessages?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _session == null) {
      return;
    }
    // Notification access is granted in Android settings, so the only way
    // to learn about it is to check again when the user comes back.
    if (_notificationDetect == AutoDetectState.off) {
      unawaited(_checkNotificationAccess());
    } else if (_detecting) {
      _sync();
    }
  }

  String get _userKey {
    final session = _session!;
    return session.userId.isNotEmpty ? session.userId : session.email;
  }

  /// Signs back in with the stored refresh token, if there is one.
  Future<void> _restore() async {
    final email = await _store.lastEmail();
    final refreshToken = await _store.refreshToken();
    AuthSession? session;
    String? notice;
    if (refreshToken != null) {
      try {
        session = await _authApi.refresh(refreshToken);
        await _remember(session);
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await _store.clear();
          notice = _expiredNotice;
        } else {
          notice = '${error.message} Sign in, or reopen the app to try again.';
        }
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _restoring = false;
      _lastEmail = email;
      _session = session;
      _loginNotice = notice;
    });
    if (session != null) {
      _startSession();
    }
  }

  Future<void> _remember(AuthSession session) async {
    if (session.refreshToken.isNotEmpty) {
      await _store.save(
        refreshToken: session.refreshToken,
        email: session.email,
      );
    }
  }

  Future<void> _signIn(String email, String password) async {
    final session = await _authApi.login(email: email, password: password);
    await _remember(session);
    setState(() {
      _session = session;
      _lastEmail = email;
      _loginNotice = null;
    });
    _startSession();
  }

  void _startSession() {
    unawaited(_loadExpenses());
    unawaited(_loadChart());
    unawaited(_initAutoDetect());
    unawaited(_initPush());
  }

  /// Gets this device's FCM token and links it to the signed-in user, then
  /// keeps the backend up to date when Firebase issues a new one.
  Future<void> _initPush() async {
    final token = await _push.getToken();
    if (token == null || !mounted || _session == null) {
      return;
    }
    await _sendPushToken(token);
    _pushTokenRefreshes ??= _push.tokenRefreshes().listen(
      (token) => unawaited(_sendPushToken(token)),
      onError: (_) {},
    );
    _pushMessages ??= _push.foregroundMessages().listen((message) {
      final text = [
        message.title,
        message.body,
      ].where((s) => s.isNotEmpty).join(' · ');
      if (text.isNotEmpty) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
    }, onError: (_) {});
  }

  Future<void> _sendPushToken(String token) async {
    try {
      await _authed(
        (accessToken) => _notificationApi.registerDeviceToken(
          accessToken: accessToken,
          token: token,
        ),
      );
    } on ApiException {
      // Sent again on the next sign-in or app start.
    }
  }

  /// Reloads spending per month of the current year. Failures keep the chart
  /// that is already shown; the list's own error message covers being offline.
  Future<void> _loadChart() async {
    try {
      final chart = await _authed(
        (token) => _expenseApi.monthlySpending(accessToken: token),
      );
      if (mounted && chart != null && _session != null) {
        setState(() => _monthlyChart = chart);
      }
    } on ApiException {
      // Shown again on the next refresh.
    }
  }

  void _signOut({String? notice}) {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _incoming?.cancel();
    _incoming = null;
    _incomingNotifications?.cancel();
    _incomingNotifications = null;
    _pushTokenRefreshes?.cancel();
    _pushTokenRefreshes = null;
    _pushMessages?.cancel();
    _pushMessages = null;
    unawaited(_push.deleteToken());
    unawaited(_store.clear());
    setState(() {
      _session = null;
      _loginNotice = notice;
      _expenses = const [];
      _monthlyChart = null;
      _groups = const [];
      _range = null;
      _loadError = null;
      _autoDetect = AutoDetectState.unsupported;
      _notificationDetect = AutoDetectState.unsupported;
      _syncing = false;
      _syncAgain = false;
      _lastSynced = null;
    });
  }

  /// Runs [action] with the current token. On 401 it refreshes the token
  /// once and retries, signing out only if that fails. Returns `null` when
  /// there is no session.
  Future<T?> _authed<T>(Future<T> Function(String token) action) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    try {
      return await action(session.accessToken);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }
    }

    final renewed = await _renew(session);
    if (renewed == null) {
      throw const ApiException(_expiredNotice, statusCode: 401);
    }
    try {
      return await action(renewed.accessToken);
    } on ApiException catch (error) {
      if (error.isUnauthorized && identical(renewed, _session)) {
        _signOut(notice: _expiredNotice);
      }
      rethrow;
    }
  }

  /// Returns a session with a fresh access token, sharing one refresh
  /// between concurrent callers. Signs out and returns `null` when the
  /// refresh token is no longer valid.
  Future<AuthSession?> _renew(AuthSession stale) {
    final current = _session;
    if (current == null || !identical(current, stale)) {
      return Future.value(current);
    }
    return _renewing ??= _refreshSession(current)
        .whenComplete(() => _renewing = null);
  }

  Future<AuthSession?> _refreshSession(AuthSession current) async {
    if (current.refreshToken.isEmpty) {
      _signOut(notice: _expiredNotice);
      return null;
    }
    final AuthSession fresh;
    try {
      fresh = await _authApi.refresh(current.refreshToken);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }
      if (identical(current, _session)) {
        _signOut(notice: _expiredNotice);
      }
      return null;
    }
    if (!mounted || !identical(current, _session)) {
      return _session;
    }
    setState(() => _session = fresh);
    await _remember(fresh);
    return fresh;
  }

  void _merge(Iterable<Expense> added) {
    final byId = {for (final e in _expenses) e.id: e};
    for (final e in added.where(_inRange)) {
      byId[e.id] = e;
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    _expenses = byId.values.toList()
      ..sort((a, b) => (b.when ?? epoch).compareTo(a.when ?? epoch));
  }

  bool _inRange(Expense e) {
    final range = _range;
    final when = e.when;
    if (range == null || when == null) {
      return true;
    }
    final start = DateUtils.dateOnly(range.start);
    final end = DateUtils.dateOnly(range.end).add(const Duration(days: 1));
    return !when.isBefore(start) && when.isBefore(end);
  }

  void _setRange(DateTimeRange? range) {
    if (range == _range) {
      return;
    }
    setState(() {
      _range = range;
      _expenses = const [];
    });
    unawaited(_loadExpenses());
  }

  Future<void> _loadExpenses() async {
    final range = _range;
    setState(() {
      _loadingExpenses = true;
      _loadError = null;
    });
    try {
      final list = await _authed(
        (token) => _expenseApi.listExpenses(
          accessToken: token,
          startDate: range?.start,
          endDate: range?.end,
        ),
      );
      // A newer range was picked while this one was loading.
      if (range != _range) {
        return;
      }
      if (mounted && list != null) {
        setState(() => _merge(list));
      }
    } on ApiException catch (error) {
      if (mounted && _session != null && range == _range) {
        setState(() => _loadError = error.message);
      }
    } finally {
      if (mounted && range == _range) {
        setState(() => _loadingExpenses = false);
      }
    }
  }

  Future<void> _initAutoDetect() async {
    if (_notifications.isSupported) {
      final access = await _notifications.hasAccess();
      if (!mounted || _session == null) {
        return;
      }
      if (access) {
        _startNotificationDetect();
      } else {
        setState(() => _notificationDetect = AutoDetectState.off);
      }
    }
    if (!_sms.isSupported || !await _sms.isDeclared()) {
      return;
    }
    final granted = await _sms.hasPermission();
    if (!mounted || _session == null) {
      return;
    }
    if (granted) {
      _startAutoDetect();
    } else {
      setState(() => _autoDetect = AutoDetectState.off);
    }
  }

  Future<void> _enableAutoDetect() async {
    final granted = await _sms.requestPermission();
    if (!mounted || _session == null) {
      return;
    }
    if (granted) {
      _startAutoDetect();
    } else {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'SMS access was not allowed. You can still add expenses by hand.',
          ),
        ),
      );
    }
  }

  void _startAutoDetect() {
    setState(() => _autoDetect = AutoDetectState.on);
    _incoming ??= _sms.incoming().listen(_onIncomingSms, onError: (_) {});
    _sync();
  }

  /// Sends the user to Android settings; [didChangeAppLifecycleState] picks
  /// up the result when they return.
  Future<void> _enableNotifications() => _notifications.openSettings();

  Future<void> _checkNotificationAccess() async {
    final access = await _notifications.hasAccess();
    if (!mounted || _session == null) {
      return;
    }
    if (access) {
      _startNotificationDetect();
    } else if (_detecting) {
      _sync();
    }
  }

  void _startNotificationDetect() {
    setState(() => _notificationDetect = AutoDetectState.on);
    _incomingNotifications ??= _notifications.incoming().listen(
      (notification) => _onIncoming(
        (token) => _detector.handleIncomingNotification(
          accessToken: token,
          notification: notification,
        ),
      ),
      onError: (_) {},
    );
    _sync();
  }

  Future<void> _onIncomingSms(SmsMessageData message) => _onIncoming(
    (token) => _detector.handleIncoming(accessToken: token, message: message),
  );

  /// Saves a payment that just arrived and announces it.
  Future<void> _onIncoming(Future<Expense?> Function(String token) save) async {
    try {
      final saved = await _authed(save);
      if (saved != null && mounted) {
        setState(() => _merge([saved]));
        unawaited(_loadChart());
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              '${saved.isCredit ? 'Received' : 'Spent'} '
              '${saved.formattedAmount} · ${saved.title}',
            ),
          ),
        );
      }
    } on ApiException {
      // Picked up by the next sync.
    }
  }

  /// Imports new payments from every source that is on. A call made while a
  /// sync is running (e.g. a second source was just turned on) runs another
  /// sync once the current one finishes.
  Future<void> _sync() async {
    if (!_detecting || _session == null) {
      return;
    }
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    setState(() => _syncing = true);
    try {
      final saved = await _authed(
        (token) async => [
          if (_autoDetect == AutoDetectState.on)
            ...await _detector.sync(accessToken: token, userKey: _userKey),
          if (_notificationDetect == AutoDetectState.on)
            ...await _detector.syncNotifications(accessToken: token),
        ],
      );
      if (!mounted || saved == null) {
        return;
      }
      setState(() {
        _merge(saved);
        _lastSynced = DateTime.now();
      });
      if (saved.isNotEmpty) {
        unawaited(_loadChart());
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Added ${saved.length} payment${saved.length == 1 ? '' : 's'} '
              'automatically',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted && _session != null) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Could not import payments: ${error.message}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_sync());
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadExpenses(), _loadChart(), _sync()]);
  }

  Future<void> _addExpense(ExpenseInput input) async {
    final saved = await _authed(
      (token) => _expenseApi.createExpense(accessToken: token, input: input),
    );
    if (saved != null) {
      setState(() => _merge([saved]));
      unawaited(_loadChart());
    }
  }

  Future<void> _createGroup(String name, List<AppUser> members) async {
    final group = await _authed(
      (token) => _expenseApi.createGroup(
        accessToken: token,
        name: name,
        members: members,
      ),
    );
    if (group != null && mounted) {
      setState(() => _groups = [group, ..._groups]);
    }
  }

  Future<List<GroupExpense>> _listGroupExpenses(ExpenseGroup group) async {
    final list = await _authed(
      (token) =>
          _expenseApi.listGroupExpenses(accessToken: token, groupId: group.id),
    );
    return list ?? const [];
  }

  Future<GroupExpense> _addGroupExpense(
    ExpenseGroup group,
    int amountPaise,
    String description,
  ) async {
    final saved = await _authed(
      (token) => _expenseApi.addGroupExpense(
        accessToken: token,
        groupId: group.id,
        amountPaise: amountPaise,
        description: description,
      ),
    );
    if (saved == null) {
      throw const ApiException('Could not save the expense.');
    }
    return saved;
  }

  Future<List<AppUser>> _searchUsers(String query) async {
    final users = await _authed(
      (token) => _profileApi.listUsers(accessToken: token, query: query),
    );
    return users ?? const [];
  }

  Future<Profile?> _loadProfile() {
    return _authed((token) => _profileApi.getProfile(accessToken: token));
  }

  Future<void> _updateProfile(Profile profile) async {
    final session = _session;
    final updated = await _authed(
      (token) =>
          _profileApi.updateProfile(accessToken: token, profile: profile),
    );
    if (updated != null && session != null) {
      setState(() {
        _session = session.copyWith(
          firstName: updated.firstName,
          lastName: updated.lastName,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return MaterialApp(
      title: 'Expenses',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.dark(),
      home: _restoring
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.lime),
              ),
            )
          : session == null
          ? LoginScreen(
              key: ValueKey(_loginNotice),
              onSubmit: _signIn,
              onRegister: _authApi.register,
              notice: _loginNotice,
              initialEmail: _lastEmail,
            )
          : AppShell(
              home: HomeScreen(
                session: session,
                onSignOut: _signOut,
                onLoadProfile: _loadProfile,
                onUpdateProfile: _updateProfile,
                onAddExpense: _addExpense,
                expenses: _expenses,
                dateRange: _range,
                onDateRangeChanged: _setRange,
                loading: _loadingExpenses,
                loadError: _loadError,
                onRefresh: _refresh,
                autoDetect: _autoDetect,
                notificationDetect: _notificationDetect,
                syncing: _syncing,
                lastSynced: _lastSynced,
                onEnableAutoDetect: _enableAutoDetect,
                onEnableNotifications: _enableNotifications,
                monthlyChart: _monthlyChart,
              ),
              groups: GroupsScreen(
                groups: _groups,
                currentUserId: session.userId,
                onCreateGroup: _createGroup,
                onSearchUsers: _searchUsers,
                onListGroupExpenses: _listGroupExpenses,
                onAddGroupExpense: _addGroupExpense,
              ),
            ),
    );
  }
}
