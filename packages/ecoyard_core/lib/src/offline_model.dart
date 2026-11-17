import 'dart:convert';

import 'content_validator.dart' show ContentIssue, IssueSeverity;

/// One file the offline model needs. Plain values from
/// `content/offline_model.json`.
class OfflineFile {
  const OfflineFile({
    required this.role,
    required this.name,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  /// `model` or `labels`.
  final String role;
  final String name;

  /// Empty while the hosted address is not known yet.
  final String url;
  final int bytes;
  final String sha256;
}

/// The offline model's settings and files, parsed from JSON.
class OfflineModelConfig {
  const OfflineModelConfig({
    required this.modelVersion,
    required this.sampleRate,
    required this.minTailSeconds,
    required this.topN,
    required this.scoreFloor,
    required this.files,
  });

  /// No offline model: the Settings card says it is not available.
  static const OfflineModelConfig none = OfflineModelConfig(
    modelVersion: '',
    sampleRate: 48000,
    minTailSeconds: 1,
    topN: 5,
    scoreFloor: 0.25,
    files: [],
  );

  final String modelVersion;
  final int sampleRate;
  final double minTailSeconds;
  final int topN;
  final double scoreFloor;
  final List<OfflineFile> files;

  OfflineFile? fileFor(String role) {
    for (final f in files) {
      if (f.role == role) return f;
    }
    return null;
  }

  /// True when it can be downloaded: both files are listed with an https
  /// address. A file with no address yet means "not available".
  bool get isDownloadable =>
      fileFor('model') != null &&
      fileFor('labels') != null &&
      files.every((f) => Uri.tryParse(f.url)?.scheme == 'https');

  /// Total download size in bytes.
  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);

  /// Reads the JSON. Never throws: anything unreadable gives [none], so a
  /// broken file turns the feature off instead of crashing the app.
  factory OfflineModelConfig.parse(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, dynamic>) return none;
      final files = <OfflineFile>[];
      final raw = root['files'];
      if (raw is List) {
        for (final f in raw) {
          if (f is! Map<String, dynamic>) return none;
          final role = f['role'], name = f['name'];
          final url = f['url'], bytes = f['bytes'], sha = f['sha256'];
          if (role is! String ||
              name is! String ||
              url is! String ||
              bytes is! int ||
              sha is! String) {
            return none;
          }
          files.add(OfflineFile(
              role: role, name: name, url: url, bytes: bytes, sha256: sha));
        }
      }
      final version = root['modelVersion'];
      final rate = root['sampleRate'];
      final tail = root['minTailSeconds'];
      final top = root['topN'];
      final floor = root['scoreFloor'];
      if (version is! String ||
          rate is! int ||
          tail is! num ||
          top is! int ||
          floor is! num) {
        return none;
      }
      return OfflineModelConfig(
        modelVersion: version,
        sampleRate: rate,
        minTailSeconds: tail.toDouble(),
        topN: top,
        scoreFloor: floor.toDouble(),
        files: files,
      );
    } catch (_) {
      return none;
    }
  }
}

final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');

/// Checks `content/offline_model.json`. Mistakes are errors. Unfinished work
/// (no address yet, a provisional score floor, an open licence question, no
/// review) is a warning now and an error with [strict], so a release can never
/// point at a dead address.
List<ContentIssue> validateOfflineModel(String text, {bool strict = false}) {
  const file = 'offline_model.json';
  final issues = <ContentIssue>[];
  void error(String m) =>
      issues.add(ContentIssue(IssueSeverity.error, file, m));
  void gate(String m) => issues.add(ContentIssue(
      strict ? IssueSeverity.error : IssueSeverity.warning, file, m));

  final Object? root;
  try {
    root = jsonDecode(text);
  } catch (e) {
    error('not valid JSON');
    return issues;
  }
  if (root is! Map<String, dynamic>) {
    error('must be a JSON object');
    return issues;
  }
  if (root['schemaVersion'] != 1) error('schemaVersion must be 1');
  if (OfflineModelConfig.parse(text).modelVersion.isEmpty) {
    error('unreadable: check modelVersion, sampleRate, minTailSeconds, topN, '
        'scoreFloor and files');
    return issues;
  }
  final c = OfflineModelConfig.parse(text);
  if (c.sampleRate <= 0) error('sampleRate must be positive');
  if (c.minTailSeconds < 0) error('minTailSeconds must not be negative');
  if (c.topN < 1) error('topN must be at least 1');
  if (c.scoreFloor < 0 || c.scoreFloor > 1) {
    error('scoreFloor must be between 0 and 1');
  }
  final names = <String>{};
  for (final f in c.files) {
    if (!names.add(f.name)) error('duplicate file name ${f.name}');
    if (f.bytes <= 0) error('${f.name}: bytes must be positive');
    if (!_sha.hasMatch(f.sha256)) {
      error('${f.name}: sha256 must be 64 lowercase hex characters');
    }
    if (!f.name.contains(c.modelVersion)) {
      error('${f.name}: the file name must contain the modelVersion '
          '(${c.modelVersion}), so a replaced file is never trusted');
    }
    if (f.url.isEmpty) {
      gate('${f.name}: no download address yet');
    } else if (Uri.tryParse(f.url)?.scheme != 'https') {
      error('${f.name}: the address must be https');
    }
  }
  for (final role in ['model', 'labels']) {
    if (c.fileFor(role) == null) error('missing a "$role" file');
  }
  if (root['reviewStatus'] != 'reviewed') {
    gate('reviewStatus is not "reviewed"; a person must review it before '
        'release');
  }
  if (root['scoreFloorProvisional'] == true) {
    gate('scoreFloor is provisional; set it from real clips (acceptance R7)');
  }
  if (root['licenceCleared'] != true) {
    gate('the BirdNET licence (CC BY-NC-SA 4.0) is not cleared for release');
  }
  return issues;
}
