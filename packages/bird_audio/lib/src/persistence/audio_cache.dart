import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Housekeeping for recordings the recorder left behind.
///
/// The recorder writes a short `.m4a` to the temporary folder and deletes it
/// as soon as the clip is read or cancelled. If the app was killed mid-
/// recording the file can stay behind; this removes such leftovers.
class AudioCache {
  AudioCache({Future<Directory> Function()? tempDir})
      : _tempDir = tempDir ?? getTemporaryDirectory;

  final Future<Directory> Function() _tempDir;

  /// Matches exactly the names `RecordPackageRecorder` creates.
  static final RegExp _ours = RegExp(r'^ecoyard_\d+\.m4a$');

  /// Deletes leftover recordings and returns how many it removed.
  ///
  /// Only call this when no recording can be in progress (at start-up before
  /// the recorder exists, or after a wipe with no recorder running).
  /// Never throws: a file-system problem must not block the app.
  Future<int> sweep() async {
    var removed = 0;
    try {
      final dir = await _tempDir();
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!_ours.hasMatch(name)) continue;
        try {
          await e.delete();
          removed++;
        } catch (_) {}
      }
    } catch (_) {}
    return removed;
  }
}
