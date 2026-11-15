import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ecoyard_core/ecoyard_core.dart' show AppSettings;

import '../features/birds/birds_screen.dart';
import '../features/home/home_screen.dart';
import '../features/plants/plant_finder_controller.dart';
import '../features/plants/plant_finder_screen.dart';
import '../features/plan/plan_controller.dart';
import '../features/plan/plan_screen.dart';
import '../features/weather/weather_controller.dart';
import '../features/settings/onboarding_screen.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_screen.dart';
import 'app_environment.dart';
import 'bird_icon.dart';
import 'content.dart';
import 'glass_nav_bar.dart';

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

  // The app database, opened once and shared by the plan and the settings.
  // Only a SUCCESSFUL open is remembered, so "Try again" really retries.
  AppStorage? _storage;
  Future<AppStorage>? _opening;

  Future<AppStorage> _openStorage() {
    final open = _storage;
    if (open != null) return Future.value(open);
    return _opening ??= _openOnce();
  }

  Future<AppStorage> _openOnce() async {
    try {
      final s = await widget.env.openStorage();
      _storage = s;
      return s;
    } finally {
      _opening = null;
    }
  }

  late final SettingsController _settings = SettingsController(
    storage: _openStorage,
    audio: widget.env.audioCache,
    now: widget.env.now,
  );

  late final PlanController _plan = PlanController(
    repo: widget.content.repo,
    openStore: () async => (await _openStorage()).plans,
    now: widget.env.now,
  );

  late final WeatherController _weather = WeatherController(
    service: widget.env.weather,
    location: widget.env.location,
    now: widget.env.now,
    readPlace: () => _settings.settings,
    savePlace: ({place, useDeviceLocation}) =>
        _settings.savePlace(place: place, useDeviceLocation: useDeviceLocation),
  );

  late final PlantFinderController _finder = PlantFinderController(
    content: widget.content,
    now: widget.env.now,
    settings: () => _settings.settings,
  );

  @override
  void initState() {
    super.initState();
    _plan.init();
    _settings.addListener(_onSettingsChanged);
    _settings.init();
  }

  /// Set when the introduction could not be marked as seen (a failed write):
  /// the app opens for this session anyway rather than leave a dead end.
  bool _introSkippedThisSession = false;

  Future<void> _finishIntro() async {
    final saved = await _settings.markOnboarded();
    if (!saved && mounted) setState(() => _introSkippedThisSession = true);
  }

  SettingsLoadState _lastSettingsState = SettingsLoadState.loading;
  AppSettings _lastSettings = AppSettings.initial;

  void _onSettingsChanged() {
    final loadedNow =
        _lastSettingsState != SettingsLoadState.ready &&
        _settings.state == SettingsLoadState.ready;
    final s = _settings.settings;
    final defaultsChanged =
        s.defaultSpace != _lastSettings.defaultSpace ||
        s.defaultSun != _lastSettings.defaultSun ||
        s.defaultBudget != _lastSettings.defaultBudget;
    // An untouched Plants tab follows the saved defaults (on first load, and
    // when they change in Settings). One the user has already adjusted keeps
    // their choice until they ask for the defaults ("Find Native Plants").
    if (loadedNow || defaultsChanged) _finder.adoptDefaultsIfUntouched();
    // A saved place means the weather can load; no place means it asks.
    if (loadedNow || _lastSettings.place != s.place) {
      unawaited(_weather.refreshIfNeeded());
    }
    _lastSettingsState = _settings.state;
    _lastSettings = s;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _weather.dispose();
    _finder.dispose();
    _plan.dispose();
    _settings.dispose();
    unawaited(_storage?.close());
    super.dispose();
  }

  /// After "Delete my data": drop every in-memory copy of what was erased.
  /// (The app also returns to the introduction, which discards the Birds tab
  /// and any recording or result it held.)
  Future<void> _onErased() async {
    _introSkippedThisSession = false;
    _weather.reset();
    _finder.showDefaults();
    await _plan.init();
    if (mounted) _showTab(0);
  }

  /// Switches tab. Showing Home reloads the weather if the last reading is
  /// over an hour old (spec 4.1: at most once an hour while the app is open).
  void _showTab(int index) {
    setState(() => _index = index);
    if (index == 0) unawaited(_weather.refreshIfNeeded());
  }

  /// Opens the Plants tab from the user's own starting choices.
  void _showPlants() {
    _finder.showDefaults();
    setState(() => _index = 1);
  }

  @override
  Widget build(BuildContext context) {
    // First launch: a short introduction. While the settings are loading
    // there is a brief spinner; if they cannot be read the app opens anyway
    // (Settings then says what went wrong), never a dead end.
    switch (_settings.state) {
      case SettingsLoadState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SettingsLoadState.ready
          when !_settings.settings.onboardingDone && !_introSkippedThisSession:
        return OnboardingScreen(onDone: _finishIntro);
      case _:
        break;
    }
    final screens = <Widget>[
      HomeScreen(
        content: widget.content,
        weather: _weather,
        now: widget.env.now,
        onIdentify: () => _showTab(2),
        onFindPlants: _showPlants,
        onSmallSpace: () {
          _finder.showSmallSpace();
          setState(() => _index = 1);
        },
        onMyPlan: () => _showTab(3),
      ),
      PlantFinderScreen(controller: _finder, content: widget.content),
      BirdsScreen(
        env: widget.env,
        content: widget.content,
        plan: _plan,
        settings: () => _settings.settings,
        onOpenPlan: () => _showTab(3),
      ),
      PlanScreen(controller: _plan, onShowPlants: _showPlants),
      SettingsScreen(
        controller: _settings,
        content: widget.content,
        onErased: _onErased,
      ),
    ];
    return Scaffold(
      // The tab bar floats over the content (frosted glass), so the body runs
      // behind it; each tab's list adds the bar's height to its bottom padding.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: screens),
      ),
      bottomNavigationBar: GlassNavBar(
        selectedIndex: _index,
        onSelected: _showTab,
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
            icon: BirdIcon(),
            selectedIcon: BirdIcon(filled: true),
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
