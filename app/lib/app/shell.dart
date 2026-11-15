import 'package:material_ui/material_ui.dart';

import '../features/birds/birds_screen.dart';
import '../features/home/home_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/plan/plan_controller.dart';
import '../features/plan/plan_screen.dart';
import 'app_environment.dart';
import 'content.dart';

/// Five-tab bottom navigation, as in the mockup.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.env, required this.content});

  final AppEnvironment env;
  final AppContent content;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  late final PlanController _plan = PlanController(
    repo: widget.content.repo,
    openStore: widget.env.openPlanStore,
    now: widget.env.now,
  );

  @override
  void initState() {
    super.initState();
    _plan.init();
  }

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(
        onNavigate: (i) => setState(() => _index = i),
        loadSample: widget.env.loadHomeSample,
      ),
      const PlaceholderScreen(
        title: 'Plants',
        message: 'Native Plant Finder arrives in Phase 5.',
      ),
      BirdsScreen(
        env: widget.env,
        content: widget.content,
        plan: _plan,
        onOpenPlan: () => setState(() => _index = 3),
      ),
      PlanScreen(controller: _plan),
      const PlaceholderScreen(
        title: 'Settings',
        message: 'Privacy & Settings arrive in Phase 6.',
      ),
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
