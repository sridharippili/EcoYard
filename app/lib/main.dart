import 'package:material_ui/material_ui.dart';

import 'app/app_environment.dart';
import 'app/shell.dart';
import 'app/theme.dart';

void main() => runApp(EcoYardApp(env: AppEnvironment.live()));

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
      home: Shell(env: env),
    );
  }
}
