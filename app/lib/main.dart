import 'package:flutter/material.dart';

import 'app/shell.dart';
import 'app/theme.dart';

void main() => runApp(const EcoYardApp());

class EcoYardApp extends StatelessWidget {
  const EcoYardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoYard',
      debugShowCheckedModeBanner: false,
      theme: ecoTheme(Brightness.light),
      darkTheme: ecoTheme(Brightness.dark),
      home: const Shell(),
    );
  }
}
