import 'dart:async';

import 'package:flutter/material.dart';

import 'api/analytics_api.dart';
import 'api/auth_api.dart';
import 'api/expense_api.dart';
import 'api/presence_api.dart';
import 'api/profile_api.dart';
import 'models/analytics_overview.dart';
import 'models/app_user.dart';
import 'models/auth_session.dart';
import 'models/expense.dart';
import 'models/expense_group.dart';
import 'models/nearby_sighting.dart';
import 'models/spending_chart.dart';
import 'screens/app_shell.dart';
import 'screens/groups_screen.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/login_screen.dart';
import 'screens/nearby_screen.dart';
import 'services/auto_detect.dart';
import 'services/ble_presence.dart';
import 'services/nearby_session.dart';
import 'services/notification_source.dart';
import 'services/presence_service.dart';
import 'services/session_store.dart';
import 'services/sms_source.dart';
import 'theme/app_theme.dart';
import 'widgets/split_proposal_sheet.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.authApi,
    this.profileApi,
    this.expenseApi,
    this.analyticsApi,
    this.smsSource,
    this.notificationSource,
    this.sessionStore,
    this.presenceApi,
    this.presenceService,
    this.blePresence,
  });

  final AuthApi? authApi;
  final ProfileApi? profileApi;
  final ExpenseApi? expenseApi;
  final AnalyticsApi? analyticsApi;
  final SmsSource? smsSource;
  final NotificationSource? notificationSource;
  final SessionStore? sessionStore;
  final PresenceApi? presenceApi;
  final PresenceService? presenceService;
  final BlePresence? blePresence;

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
  late final AnalyticsApi _analyticsApi =
      widget.analyticsApi ?? AnalyticsApi();
  late final SmsSource _sms = widget.smsSource ?? SmsSource();
  late final NotificationSource _notifications =
      widget.notificationSource ?? NotificationSource();
  late final AutoDetector _detector = AutoDetector(
    sms: _sms,
    notifications: _notifications,
    api: _expenseApi,
  );
  late final SessionStore _store = widget.sessionStore ?? SessionStore();
  late final PresenceApi _presenceApi = widget.presenceApi ?? PresenceApi();
  late final PresenceService _presence =
      widget.presenceService ?? PresenceService();
  late final BlePresence _ble = widget.blePresence ?? BlePresence();
  late final NearbySession _nearby = NearbySession(
    ble: _ble,
    ids: _presence,
    fetchId: () => _authed((token) => _presenceApi.current(accessToken: token)),
    resolve: (sightings) => _authed(
      (token) => _presenceApi.reportSightings(
        accessToken: token,
        sightings: sightings,
      ),
    ),
  );

  AuthSession? _session;
  String? _loginNotice;
  String? _lastEmail;
  bool _restoring = true;
  Future<AuthSession?>? _renewing;

  List<Expense> _expenses = const [];
  SpendingChart? _monthlyChart;
  AnalyticsOverview? _insights;
  bool _loadingInsights = false;
  String? _insightsError;

  /// Inclusive filter for every Insights chart; `null` = current month.
  DateTimeRange? _insightsRange;

  /// What a payment can be moved to; empty until loaded.
  List<ExpenseCategory> _categories = const [];

  /// Groups created since signing in, newest first.
  List<ExpenseGroup> _groups = const [];

  /// Days shown on the home screen, both inclusive; `null` shows everything.
  DateTimeRange? _range;
  bool _loadingExpenses = false;
  String? _loadError;

  AutoDetectState _autoDetect = AutoDetectState.unsupported;
  AutoDetectState _notificationDetect = AutoDetectState.unsupported;

  /// The user turned off reading SMS and notifications on this device.
  bool _detectPaused = false;
  bool _syncing = false;
  bool _syncAgain = false;
  DateTime? _lastSynced;
  StreamSubscription<SmsMessageData>? _incoming;
  StreamSubscription<PaymentNotification>? _incomingNotifications;

  bool get _detecting =>
      !_detectPaused &&
      (_autoDetect == AutoDetectState.on ||
          _notificationDetect == AutoDetectState.on);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nearby.onUpdate = () {
      if (mounted) {
        setState(() {});
      }
    };
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incoming?.cancel();
    _incomingNotifications?.cancel();
    unawaited(_nearby.dispose());
    _presence.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_nearby.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_nearby.resume());
    }
    if (state != AppLifecycleState.resumed ||
        _session == null ||
        _detectPaused) {
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
    unawaited(_loadInsights());
    unawaited(_loadCategories());
    unawaited(_loadGroups());
    unawaited(_initAutoDetect());
    unawaited(_initPresence());
  }

  /// Loads the backend-issued BLE temporary ID and refreshes it at each
  /// 15-minute slot. The app never computes the ID itself.
  Future<void> _initPresence() async {
    await _presence.start(
      () => _authed((token) => _presenceApi.current(accessToken: token)),
    );
  }

  Future<void> _loadGroups() async {
    final userId = _session?.userId ?? '';
    try {
      final groups = await _authed(
        (token) =>
            _expenseApi.listGroups(accessToken: token, currentUserId: userId),
      );
      if (mounted && groups != null && _session != null) {
        setState(() => _groups = groups);
      }
    } on ApiException {
      // Groups already shown stay; tried again on the next refresh.
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _authed(
        (token) => _expenseApi.listCategories(accessToken: token),
      );
      if (mounted && categories != null && _session != null) {
        setState(() => _categories = categories);
      }
    } on ApiException {
      // Tried again on the next refresh.
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

  Future<void> _loadInsights() async {
    if (_session == null) {
      return;
    }
    setState(() {
      _loadingInsights = true;
      _insightsError = null;
    });
    final range = _insightsRange;
    try {
      final overview = await _authed(
        (token) => _analyticsApi.overview(
          accessToken: token,
          from: range?.start,
          to: range?.end,
        ),
      );
      if (!mounted || _session == null) {
        return;
      }
      setState(() {
        _insights = overview;
        _loadingInsights = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingInsights = false;
        _insightsError = e.message;
      });
    }
  }

  void _setInsightsRange(DateTimeRange? range) {
    setState(() => _insightsRange = range);
    unawaited(_loadInsights());
  }

  void _signOut({String? notice}) {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _incoming?.cancel();
    _incoming = null;
    _incomingNotifications?.cancel();
    _incomingNotifications = null;
    unawaited(_nearby.stop());
    _presence.stop();
    unawaited(_store.clear());
    setState(() {
      _session = null;
      _loginNotice = notice;
      _expenses = const [];
      _monthlyChart = null;
      _insights = null;
      _insightsError = null;
      _loadingInsights = false;
      _insightsRange = null;
      _categories = const [];
      _groups = const [];
      _range = null;
      _loadError = null;
      _autoDetect = AutoDetectState.unsupported;
      _notificationDetect = AutoDetectState.unsupported;
      _detectPaused = false;
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
    final paused = await _store.autoDetectPaused();
    if (!mounted || _session == null) {
      return;
    }
    if (paused) {
      final available =
          (_notifications.isSupported && await _notifications.isDeclared()) ||
          (_sms.isSupported && await _sms.isDeclared());
      if (mounted && _session != null && available) {
        setState(() => _detectPaused = true);
      }
      return;
    }
    if (_notifications.isSupported && await _notifications.isDeclared()) {
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

  /// Stops reading SMS and payment notifications on this device. Android
  /// permissions stay granted, so turning it back on needs no prompts.
  Future<void> _pauseAutoDetect() async {
    _incoming?.cancel();
    _incoming = null;
    _incomingNotifications?.cancel();
    _incomingNotifications = null;
    await _store.setAutoDetectPaused(true);
    if (!mounted) {
      return;
    }
    setState(() {
      _detectPaused = true;
      _autoDetect = AutoDetectState.unsupported;
      _notificationDetect = AutoDetectState.unsupported;
    });
  }

  Future<void> _resumeAutoDetect() async {
    await _store.setAutoDetectPaused(false);
    if (!mounted) {
      return;
    }
    setState(() => _detectPaused = false);
    await _initAutoDetect();
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
        unawaited(_offerNearbySplit(saved));
      }
    } on ApiException {
      // Picked up by the next sync.
    }
  }

  bool _splitPromptOpen = false;

  /// Asks the payer (in-app) before splitting an auto-detected debit with
  /// people currently heard on Nearby. No silent AddExpenses.
  Future<void> _offerNearbySplit(Expense personal) async {
    if (personal.isCredit || !personal.isAutoDetected) {
      return;
    }
    final nearby = _nearby.identifiedNearby;
    if (nearby.isEmpty) {
      return;
    }
    final groupId = _sharedGroupFor(nearby);
    if (groupId == null) {
      return;
    }
    final candidates = [
      for (final s in nearby)
        if (s.sharedGroups.any((g) => g.id == groupId)) s,
    ];
    if (candidates.isEmpty) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted || _splitPromptOpen) {
      return;
    }
    final groupName = _groups
            .where((g) => g.id == groupId)
            .map((g) => g.name)
            .firstOrNull ??
        candidates.first.sharedGroups
            .where((g) => g.id == groupId)
            .map((g) => g.name)
            .firstOrNull ??
        'group';

    _splitPromptOpen = true;
    SplitProposalResult? decision;
    try {
      decision = await showSplitProposalSheet(
        context: context,
        expense: personal,
        groupName: groupName,
        candidates: candidates,
      );
    } finally {
      _splitPromptOpen = false;
    }
    if (decision == null || !decision.split || !mounted) {
      return;
    }
    final description = personal.title.isNotEmpty
        ? personal.title
        : 'Shared payment';
    try {
      final saved = await _authed(
        (token) => _expenseApi.addGroupExpense(
          accessToken: token,
          groupId: groupId,
          amountPaise: personal.amountPaise,
          description: description,
          ephemeralIds: decision!.selectedEphemeralIds,
        ),
      );
      if (saved != null && mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Split ${personal.formattedAmount} with '
              '${decision.selectedEphemeralIds.length} nearby · $groupName',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Could not split: ${error.message}')),
        );
      }
    }
  }

  /// Group that covers the most in-range people, preferring ones already
  /// loaded into [_groups].
  String? _sharedGroupFor(List<NearbySighting> nearby) {
    final known = {for (final g in _groups) g.id};
    final scores = <String, int>{};
    for (final s in nearby) {
      for (final g in s.sharedGroups) {
        if (g.id.isEmpty) {
          continue;
        }
        if (known.isNotEmpty && !known.contains(g.id)) {
          continue;
        }
        scores[g.id] = (scores[g.id] ?? 0) + 1;
      }
    }
    if (scores.isEmpty) {
      for (final s in nearby) {
        for (final g in s.sharedGroups) {
          if (g.id.isNotEmpty) {
            scores[g.id] = (scores[g.id] ?? 0) + 1;
          }
        }
      }
    }
    if (scores.isEmpty) {
      return null;
    }
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
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
        // One confirm sheet at a time; offer split for the newest debit first.
        for (final expense in saved.reversed) {
          await _offerNearbySplit(expense);
          if (!mounted) {
            return;
          }
        }
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
    await Future.wait([
      _loadExpenses(),
      _loadChart(),
      _loadInsights(),
      _sync(),
      _loadGroups(),
      if (_categories.isEmpty) _loadCategories(),
    ]);
  }

  Future<void> _addExpense(ExpenseInput input) async {
    final saved = await _authed(
      (token) => _expenseApi.createExpense(accessToken: token, input: input),
    );
    if (saved != null) {
      setState(() => _merge([saved]));
      unawaited(_loadChart());
      unawaited(_loadInsights());
    }
  }

  Future<void> _changeCategory(
    Expense expense,
    ExpenseCategory category,
  ) async {
    final updated = await _authed(
      (token) => _expenseApi.updateCategory(
        accessToken: token,
        expenseId: expense.id,
        categoryId: category.id,
      ),
    );
    if (updated != null && mounted) {
      setState(() => _merge([updated]));
      unawaited(_loadInsights());
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
                autoDetectPaused: _detectPaused,
                onPauseAutoDetect: _pauseAutoDetect,
                onResumeAutoDetect: _resumeAutoDetect,
                monthlyChart: _monthlyChart,
                categories: _categories,
                onChangeCategory: _changeCategory,
              ),
              insights: InsightsScreen(
                overview: _insights,
                loading: _loadingInsights,
                error: _insightsError,
                dateRange: _insightsRange,
                onDateRangeChanged: _setInsightsRange,
                onRefresh: _loadInsights,
              ),
              groups: GroupsScreen(
                groups: _groups,
                currentUserId: session.userId,
                onCreateGroup: _createGroup,
                onSearchUsers: _searchUsers,
                onListGroupExpenses: _listGroupExpenses,
                onAddGroupExpense: _addGroupExpense,
                onRefresh: _loadGroups,
              ),
              nearby: NearbyScreen(
                supported: _ble.isSupported,
                running: _nearby.running,
                canAdvertise: _nearby.canAdvertise,
                ownId: _nearby.ownId,
                nearby: _nearby.nearby,
                error: _nearby.error,
                onStart: _nearby.start,
                onStop: _nearby.stop,
              ),
            ),
    );
  }
}
