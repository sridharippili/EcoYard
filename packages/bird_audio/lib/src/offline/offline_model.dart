import 'dart:async';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:path_provider/path_provider.dart';

import '../identification.dart';
import 'birdnet_pipeline.dart';
import 'local_provider.dart';
import 'model_download.dart';
import 'model_runner.dart';

/// The offline model as the app sees it: is it on the phone, get it, remove
/// it, and the provider that uses it. An interface so screens and tests never
/// touch the file system, the network or the model library.
abstract interface class OfflineModel {
  OfflineModelConfig get config;

  /// The provider to put first in the chain. Always safe to include: while
  /// the model is not on the phone it is skipped.
  IdentificationProvider get provider;

  /// Both files are present with exactly the expected size. Cheap.
  Future<bool> isReady();

  /// Downloads both files, checks them, and test-opens the model. Throws
  /// [ModelDownloadException] or [ModelDownloadCancelled]; on any failure
  /// nothing usable and nothing partial is left behind.
  Future<void> download({ProgressCallback? onProgress, CancelToken? cancel});

  /// Closes the model and deletes every model file and partial download.
  /// Never throws; false if something could not be deleted.
  Future<bool> remove();

  /// Closes the model without deleting anything.
  Future<void> close();

  /// Deletes partial downloads a crash left behind. Never throws.
  Future<void> sweepPartials();
}

/// The real one: files in the app's cache folder (not backed up to iCloud),
/// run with TensorFlow Lite.
class OfflineModelHost implements OfflineModel {
  OfflineModelHost({
    required this.config,
    Future<Directory> Function()? cacheDir,
    ModelStore? store,
    Future<BirdModelRunner> Function(String path)? loadRunner,
  })  : _cacheDir = cacheDir ?? getApplicationCacheDirectory,
        _store = store,
        _loadRunner = loadRunner ?? TfliteRunner.load {
    provider = BirdNetLocalProvider(
      loadRunner: () async {
        final spec = _spec('model');
        return _loadRunner((await _storeFor()).fileFor(spec).path);
      },
      loadLabels: () async {
        final spec = _spec('labels');
        final text = await (await _storeFor()).fileFor(spec).readAsString();
        return parseBirdNetLabels(text);
      },
      settings: BirdNetSettings(
        sampleRate: config.sampleRate,
        minTailSeconds: config.minTailSeconds,
        topN: config.topN,
        scoreFloor: config.scoreFloor,
      ),
      isModelReady: isReady,
    );
  }

  @override
  final OfflineModelConfig config;

  @override
  late final BirdNetLocalProvider provider;

  final Future<Directory> Function() _cacheDir;
  final Future<BirdModelRunner> Function(String path) _loadRunner;
  ModelStore? _store;

  Future<ModelStore> _storeFor() async => _store ??=
      ModelStore(dir: Directory('${(await _cacheDir()).path}/offline_model'));

  ModelFileSpec _spec(String role) {
    final f = config.fileFor(role);
    if (f == null) throw StateError('No $role file in the configuration');
    return ModelFileSpec(
        name: f.name, url: f.url, bytes: f.bytes, sha256: f.sha256);
  }

  List<ModelFileSpec> get _specs => [
        for (final f in config.files)
          ModelFileSpec(
              name: f.name, url: f.url, bytes: f.bytes, sha256: f.sha256),
      ];

  @override
  Future<bool> isReady() async {
    try {
      if (config.files.isEmpty) return false;
      return await (await _storeFor()).isReady(_specs);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> download({
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    if (!config.isDownloadable) {
      throw const ModelDownloadException(
          'The offline model is not available yet');
    }
    final store = await _storeFor();
    final total = config.totalBytes;
    var done = 0;
    try {
      for (final spec in _specs) {
        await store.download(
          spec,
          cancel: cancel,
          onProgress: (received, _) => onProgress?.call(done + received, total),
        );
        done += spec.bytes;
      }
      // The files are the right size and checksum; make sure the model also
      // opens, so "ready" never means "downloaded but unusable".
      try {
        final runner = await _loadRunner(store.fileFor(_spec('model')).path);
        await runner.close();
      } catch (_) {
        throw const ModelDownloadException(
            'The model file could not be opened, so it was removed');
      }
    } catch (_) {
      await store.removeAll(_specs);
      rethrow;
    }
  }

  @override
  Future<bool> remove() async {
    await provider.close();
    try {
      return await (await _storeFor()).removeAll(_specs);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() => provider.close();

  @override
  Future<void> sweepPartials() async {
    try {
      await (await _storeFor()).sweepPartials();
    } catch (_) {}
  }
}
