import 'package:flutter/material.dart';

/// Bottom tabs for the signed-in app. Both tabs stay alive, so switching
/// keeps each one's scroll position and filters.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.home, required this.groups});

  final Widget home;
  final Widget groups;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _tab, children: [widget.home, widget.groups]),
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
          key: Key('tab-groups'),
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups_rounded),
          label: 'Groups',
        ),
      ],
    ),
  );
}
