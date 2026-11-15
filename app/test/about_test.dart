import 'dart:io';

import 'package:ecoyard/app/about.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version shown in About equals pubspec.yaml', () {
    // Reads the real file, not a copy of the constant.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(
      r'^version:\s*([0-9.]+)(\+\d+)?\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'no version: line in pubspec.yaml');
    expect(appVersion, m!.group(1));
  });
}
