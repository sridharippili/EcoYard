import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the sample Home content bundled with the app. Real content arrives
/// from `content/*.json` in Phase 2.
Future<Map<String, dynamic>> loadBundledHomeSample() async {
  final raw = await rootBundle.loadString('assets/sample_home.json');
  return jsonDecode(raw) as Map<String, dynamic>;
}
