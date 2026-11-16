import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// What happened when the user was offered the export.
enum ExportOutcome {
  /// The share sheet was used (saved to Files, sent, copied, and so on).
  shared,

  /// The user closed the share sheet without choosing anything.
  dismissed,

  /// The file could not be written or the share sheet could not open.
  failed,
}

/// Hands the user's data to the system share sheet as a JSON file.
///
/// An interface so screens and tests never touch the file system or the
/// share sheet.
abstract interface class DataExporter {
  /// Offers [json] as a file. Never throws.
  Future<ExportOutcome> export(String json, {Rect? origin});

  /// Deletes any export file a crash left behind. Never throws.
  Future<int> sweep();
}

/// The real one, backed by `share_plus`.
///
/// The file holds the user's plan, so it exists only while the share sheet is
/// open: it is written to the temporary folder and deleted as soon as the
/// sheet closes, whatever the outcome.
class ShareSheetExporter implements DataExporter {
  ShareSheetExporter({
    Future<Directory> Function()? tempDir,
    Future<ShareResult> Function(ShareParams)? share,
  })  : _tempDir = tempDir ?? getTemporaryDirectory,
        _share = share ?? SharePlus.instance.share;

  final Future<Directory> Function() _tempDir;

  /// The system share sheet. Replaced in tests, which cannot open one.
  final Future<ShareResult> Function(ShareParams) _share;

  /// Matches exactly the files this class creates.
  static final RegExp _ours = RegExp(r'^ecoyard-my-data-\d+\.json$');

  @override
  Future<ExportOutcome> export(String json, {Rect? origin}) async {
    File? file;
    try {
      final dir = await _tempDir();
      file = File(
        '${dir.path}/ecoyard-my-data-'
        '${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json, flush: true);
      final result = await _share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'My EcoYard data',
          sharePositionOrigin: origin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.dismissed => ExportOutcome.dismissed,
        _ => ExportOutcome.shared,
      };
    } catch (_) {
      return ExportOutcome.failed;
    } finally {
      // The data must not outlive the share sheet.
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  @override
  Future<int> sweep() async {
    var removed = 0;
    try {
      final dir = await _tempDir();
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        if (!_ours.hasMatch(e.uri.pathSegments.last)) continue;
        try {
          await e.delete();
          removed++;
        } catch (_) {}
      }
    } catch (_) {}
    return removed;
  }
}
