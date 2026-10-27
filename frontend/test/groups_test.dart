import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/api/expense_api.dart';
import 'package:my_app/api/profile_api.dart';
import 'package:my_app/models/app_user.dart';
import 'package:my_app/models/expense_group.dart';
import 'package:my_app/screens/groups_screen.dart';
import 'package:my_app/theme/app_theme.dart';

const _amit = AppUser(
  id: '52d0da55-3e16-4c32-bf18-d3cca9d33633',
  email: 'amit@gmail.com',
  firstName: 'Amit',
  lastName: 'Shah',
);
const _yash = AppUser(
  id: '5b2dde30-658f-46be-8e3f-1f1c960ae5ef',
  email: 'yash@gmail.com',
  firstName: 'Yash',
);
const _everyone = [_amit, _yash];

/// Holds the groups like the app does, so a created group shows up.
class _Host extends StatefulWidget {
  const _Host({required this.created, required this.queries});

  final List<(String, List<AppUser>)> created;
  final List<String> queries;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _groups = <ExpenseGroup>[];

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark(),
    home: GroupsScreen(
      groups: _groups,
      onSearchUsers: (query) async {
        widget.queries.add(query);
        final q = query.toLowerCase();
        return _everyone
            .where(
              (u) =>
                  u.displayName.toLowerCase().contains(q) ||
                  u.email.contains(q),
            )
            .toList();
      },
      onCreateGroup: (name, members) async {
        widget.created.add((name, members));
        setState(() {
          _groups = [
            ExpenseGroup(id: 'g-${_groups.length}', name: name, members: members),
            ..._groups,
          ];
        });
      },
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.8125;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  test('createGroup posts the name and member IDs', () async {
    late http.Request sent;
    final api = ExpenseApi(
      baseUrl: 'http://api',
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Group created',
            'data': {'id': 'group-1', 'name': 'Goa trip'},
          }),
          201,
        );
      }),
    );

    final group = await api.createGroup(
      accessToken: 'token',
      name: 'Goa trip',
      members: [_amit],
    );

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://api/api/v1/create-group');
    expect(sent.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(sent.body), {
      'name': 'Goa trip',
      'userIDs': [_amit.id],
    });
    expect(group.id, 'group-1');
    expect(group.members.single.id, _amit.id);
  });

  test('listUsers sends the search and reads the users', () async {
    late Uri url;
    final api = ProfileApi(
      baseUrl: 'http://api',
      client: MockClient((request) async {
        url = request.url;
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'users',
            'data': [
              {
                'user_id': _amit.id,
                'email': 'amit@gmail.com',
                'first_name': 'Amit',
                'last_name': 'Shah',
              },
            ],
          }),
          200,
        );
      }),
    );

    final users = await api.listUsers(accessToken: 'token', query: ' am it ');

    expect(url.path, '/api/v1/users');
    expect(url.queryParameters, {'q': 'am it'});
    expect(users.single.displayName, 'Amit Shah');
    expect(users.single.initials, 'AS');
  });

  testWidgets('shows an empty state before any group exists', (tester) async {
    await _pump(tester, const _Host(created: [], queries: []));

    expect(find.byKey(const Key('groups-empty')), findsOneWidget);
  });

  testWidgets('picks members from the user list and creates the group', (
    tester,
  ) async {
    final created = <(String, List<AppUser>)>[];
    final queries = <String>[];
    await _pump(tester, _Host(created: created, queries: queries));

    await tester.tap(find.byKey(const Key('new-group-button')));
    await tester.pumpAndSettle();

    expect(queries, ['']);
    expect(find.text('Amit Shah'), findsOneWidget);
    expect(find.text('Yash'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group-create-button')));
    await tester.pump();
    expect(find.text('Give the group a name.'), findsOneWidget);
    expect(find.text('Pick at least one member.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('group-name-field')),
      'Goa trip',
    );
    await tester.enterText(find.byKey(const Key('group-member-search')), 'ya');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(queries.last, 'ya');
    expect(find.byKey(ValueKey('group-user-${_amit.id}')), findsNothing);

    await tester.tap(find.byKey(ValueKey('group-user-${_yash.id}')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Create group · 2 people'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('group-user-${_yash.id}')));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('group-user-${_yash.id}')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('group-create-button')));
    await tester.pumpAndSettle();

    expect(created, hasLength(1));
    expect(created.single.$1, 'Goa trip');
    expect(created.single.$2.map((u) => u.id), [_yash.id]);
    expect(find.text('Goa trip'), findsOneWidget);
    expect(find.text('You, Yash'), findsOneWidget);
    expect(find.byKey(const Key('groups-empty')), findsNothing);
  });
}
