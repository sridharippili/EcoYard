import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'identification.dart';

/// Records a short clip. Behind an interface so screens can be tested
/// without a microphone.
abstract interface class ClipRecorder {
  /// Asks for (or confirms) microphone permission.
  Future<bool> hasPermission();

  Future<void> start();

  /// Stops and returns the audio. The temp file is deleted before this
  /// returns; the bytes live only in memory from here on.
  Future<AudioClip> stop();

  /// Stops and throws the audio away.
  Future<void> cancel();

  Future<void> dispose();
}

/// [ClipRecorder] backed by the `record` package: AAC in an `.m4a` file,
/// the format both services accept, unless [useWav] says the offline model
/// is ready, in which case it records 48 kHz mono WAV, which is what the
/// model reads. Asked once, when a recording starts.
class RecordPackageRecorder implements ClipRecorder {
  RecordPackageRecorder({this.useWav}) : _recorder = AudioRecorder();

  final Future<bool> Function()? useWav;
  final AudioRecorder _recorder;
  String? _path;
  bool _wav = false;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    var wav = false;
    try {
      wav = await useWav?.call() ?? false;
    } catch (_) {}
    _wav = wav;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ecoyard_${DateTime.now().microsecondsSinceEpoch}.'
        '${wav ? 'wav' : 'm4a'}';
    _path = path;
    await _recorder.start(
      wav
          ? const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 48000,
              numChannels: 1,
            )
          : const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );
  }

  @override
  Future<AudioClip> stop() async {
    final stopped = await _recorder.stop();
    final path = stopped ?? _path;
    _path = null;
    if (path == null) {
      throw StateError('Recorder produced no file.');
    }
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('Recording was empty.');
      return _wav
          ? AudioClip(
              bytes: bytes,
              fileName: 'recording.wav',
              mimeType: 'audio/wav',
            )
          : AudioClip(bytes: bytes, fileName: 'recording.m4a');
    } finally {
      await _deleteQuietly(file);
    }
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (path != null) await _deleteQuietly(File(path));
  }

  @override
  Future<void> dispose() => _recorder.dispose();

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
