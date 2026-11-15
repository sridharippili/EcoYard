import 'dart:io';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Scores one window of audio with the BirdNET model.
///
/// An interface, so everything around the model (windowing, sigmoid, ranking,
/// the chain) is unit-tested with a fake: the real TFLite library cannot run
/// under `flutter test` on a Mac.
abstract interface class BirdModelRunner {
  /// Samples the model expects per window (BirdNET V2.4: 3 s at 48 kHz).
  int get windowSamples;

  /// Number of classes (BirdNET V2.4: 6,522).
  int get classCount;

  /// Raw model outputs (logits) for one window of exactly [windowSamples].
  Future<Float32List> logitsFor(Float32List window);

  /// Frees the interpreter. Safe to call twice.
  Future<void> close();
}

/// The real runner, backed by `tflite_flutter`.
class TfliteRunner implements BirdModelRunner {
  TfliteRunner._(this._interpreter)
      : windowSamples = _interpreter.getInputTensor(0).shape.last,
        classCount = _interpreter.getOutputTensor(0).shape.last;

  /// Loads the model from a plain file (the downloaded copy, never an asset).
  /// Throws if the file is missing or is not a loadable model.
  static Future<TfliteRunner> load(String modelPath) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw StateError('Model file not found');
    }
    final interpreter = Interpreter.fromFile(file);
    interpreter.allocateTensors();
    return TfliteRunner._(interpreter);
  }

  final Interpreter _interpreter;
  bool _closed = false;

  @override
  final int windowSamples;
  @override
  final int classCount;

  @override
  Future<Float32List> logitsFor(Float32List window) async {
    if (_closed) throw StateError('Runner is closed');
    if (window.length != windowSamples) {
      throw ArgumentError.value(
        window.length,
        'window.length',
        'must be $windowSamples',
      );
    }
    final output = [List<double>.filled(classCount, 0)];
    _interpreter.run([window], output);
    return Float32List.fromList(output[0]);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }
}
