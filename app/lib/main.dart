import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app/app_environment.dart';
import 'app/content.dart';
import 'app/shell.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnvironment.live(
    offlineConfig: await loadOfflineModelConfig(),
  );
  runApp(EcoYardApp(env: env));
  // Remove a recording a crash may have left behind. Started right away,
  // before the user can reach Record, so it cannot touch one in progress;
  // it never throws and does not delay the first frame.
  unawaited(env.audioCache.sweep());
  // An export file a crash left behind holds the user's data.
  unawaited(env.exporter.sweep());
}

class EcoYardApp extends StatelessWidget {
  const EcoYardApp({super.key, required this.env});

  final AppEnvironment env;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoYard',
      debugShowCheckedModeBanner: false,
      theme: ecoTheme(Brightness.light),
      darkTheme: ecoTheme(Brightness.dark),
      home: _ContentGate(env: env),
    );
  }
}

/// Loads the content once, then shows the app. If loading fails the user sees
/// that, with a retry, instead of a half-working app.
class _ContentGate extends StatefulWidget {
  const _ContentGate({required this.env});

  final AppEnvironment env;

  @override
  State<_ContentGate> createState() => _ContentGateState();
}

class _ContentGateState extends State<_ContentGate> {
  late Future<AppContent> _content = widget.env.loadContent();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppContent>(
      future: _content,
      builder: (context, snap) {
        if (snap.hasData) return Shell(env: widget.env, content: snap.data!);
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "EcoYard couldn't load its bird and plant information.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {
                        _content = widget.env.loadContent();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
