import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/placeholder/placeholder_screen.dart';

/// Five-tab bottom navigation, as in the mockup.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _titles = ['Home', 'Plants', 'Birds', 'My Plan', 'Settings'];
  static const _phase = [
    '',
    'Native Plant Finder arrives in Phase 5.',
    'Bird identification arrives in Phase 1, after the BirdNET spike.',
    'Your habitat plan arrives in Phase 4.',
    'Privacy & Settings arrive in Phase 6.',
  ];

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onNavigate: (i) => setState(() => _index = i)),
      for (var i = 1; i < 5; i++)
        PlaceholderScreen(title: _titles[i], message: _phase[i]),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco),
            label: 'Plants',
          ),
          NavigationDestination(
            icon: Icon(Icons.flutter_dash_outlined),
            selectedIcon: Icon(Icons.flutter_dash),
            label: 'Birds',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'My Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
