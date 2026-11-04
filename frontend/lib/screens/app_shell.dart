import 'package:flutter/material.dart';

/// Bottom tabs for the signed-in app. Tabs stay alive, so switching
/// keeps each one's scroll position and filters.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.home,
    required this.insights,
    required this.groups,
    required this.nearby,
  });

  final Widget home;
  final Widget insights;
  final Widget groups;
  final Widget nearby;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [widget.home, widget.insights, widget.groups, widget.nearby],
    ),
    bottomNavigationBar: NavigationBar(
      key: const Key('main-tabs'),
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(
          key: Key('tab-expenses'),
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Expenses',
        ),
        NavigationDestination(
          key: Key('tab-insights'),
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights_rounded),
          label: 'Insights',
        ),
        NavigationDestination(
          key: Key('tab-groups'),
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups_rounded),
          label: 'Groups',
        ),
        NavigationDestination(
          key: Key('tab-nearby'),
          icon: Icon(Icons.bluetooth_searching_outlined),
          selectedIcon: Icon(Icons.bluetooth_searching_rounded),
          label: 'Nearby',
        ),
      ],
    ),
  );
}
