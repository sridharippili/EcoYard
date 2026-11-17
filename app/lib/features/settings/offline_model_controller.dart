import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter/foundation.dart';

enum OfflineState {
  /// Looking at what is on the phone.
  checking,

  /// This build has nowhere to download it from yet.
  unavailable,
  notDownloaded,

  /// The user tapped Download and is being asked to confirm.
  confirming,
  downloading,
  ready,

  /// The last download or removal failed; [OfflineModelController.error] says
  /// why. Downloading again is always possible.
  failed,
}

/// The Settings card for the offline model, and the one place that starts or
/// stops a download.
class OfflineModelController extends ChangeNotifier {
  OfflineModelController({required this.model, this.onReadyChanged});

  final OfflineModel model;

  /// Called whenever the model becomes ready or stops being ready, so the
  /// identification chain looks at it afresh.
  final VoidCallback? onReadyChanged;

  OfflineState state = OfflineState.checking;

  /// 0..1 while downloading, once both files are being fetched.
  double progress = 0;

  /// A short sentence when [state] is [OfflineState.failed].
  String? error;

  CancelToken? _cancel;
  Future<void>? _running;
  bool _disposed = false;

  /// While the files are fetched the phone is also checking them: shown as
  /// "Checking the model" rather than a bar stuck at 100%.
  bool get isChecking => state == OfflineState.downloading && progress >= 1;

  /// "52 MB", from the configured sizes.
  String get sizeLabel => '${(model.config.totalBytes / 1e6).round()} MB';

  void _set(OfflineState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  /// Run at start-up: clears partial downloads a crash left, then reads what
  /// is on the phone.
  Future<void> init() async {
    await model.sweepPartials();
    await refresh();
  }

  /// Re-reads what is on the phone. The system may purge cached files, so
  /// this is also the way "ready" turns back into "not downloaded".
  Future<void> refresh() async {
    if (state == OfflineState.downloading) return;
    final wasReady = state == OfflineState.ready;
    final ready = await model.isReady();
    if (state == OfflineState.downloading) return;
    if (ready) {
      error = null;
      _set(OfflineState.ready);
    } else if (!model.config.isDownloadable) {
      _set(OfflineState.unavailable);
    } else if (state != OfflineState.failed || wasReady) {
      _set(OfflineState.notDownloaded);
    }
    if (wasReady != ready) onReadyChanged?.call();
  }

  /// The Download button: asks first (about 52 MB).
  void askToDownload() {
    if (state == OfflineState.notDownloaded || state == OfflineState.failed) {
      _set(OfflineState.confirming);
    }
  }

  void declineDownload() {
    if (state == OfflineState.confirming) _set(OfflineState.notDownloaded);
  }

  /// Starts the download. A second call while one is running does nothing.
  Future<void> download() {
    if (_running != null || state == OfflineState.downloading) {
      return _running ?? Future<void>.value();
    }
    if (state != OfflineState.confirming &&
        state != OfflineState.failed &&
        state != OfflineState.notDownloaded) {
      return Future<void>.value();
    }
    return _running = _download().whenComplete(() => _running = null);
  }

  Future<void> _download() async {
    final cancel = _cancel = CancelToken();
    progress = 0;
    error = null;
    _set(OfflineState.downloading);
    try {
      await model.download(
        cancel: cancel,
        onProgress: (received, total) {
          final t = total ?? model.config.totalBytes;
          progress = t <= 0 ? 0 : (received / t).clamp(0.0, 1.0);
          if (!_disposed) notifyListeners();
        },
      );
      _set(OfflineState.ready);
      onReadyChanged?.call();
    } on ModelDownloadCancelled {
      _set(OfflineState.notDownloaded);
    } on ModelDownloadException catch (e) {
      error = e.message;
      _set(OfflineState.failed);
    } catch (_) {
      error = 'The download did not finish';
      _set(OfflineState.failed);
    } finally {
      _cancel = null;
    }
  }

  /// Stops a running download; nothing is kept.
  void cancelDownload() => _cancel?.cancel();

  /// "Remove": closes the model and deletes its files.
  Future<void> remove() async {
    if (state != OfflineState.ready) return;
    final ok = await model.remove();
    onReadyChanged?.call();
    if (ok) {
      error = null;
      _set(OfflineState.notDownloaded);
    } else {
      error = "Couldn't remove all the model files";
      _set(OfflineState.failed);
    }
  }

  /// First step of "Delete my data": stop any download and close the model,
  /// so nothing reappears or stays open while the data is erased.
  Future<void> stopForErase() async {
    _cancel?.cancel();
    await _running;
    await model.close();
  }

  /// Last step of "Delete my data": the model and any partial file go too.
  Future<void> eraseAfterWipe() async {
    final ok = await model.remove();
    onReadyChanged?.call();
    if (ok) {
      error = null;
      _set(
        model.config.isDownloadable
            ? OfflineState.notDownloaded
            : OfflineState.unavailable,
      );
    } else {
      error = "Couldn't remove all the model files";
      _set(OfflineState.failed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
