import 'dart:typed_data';

/// A recorded clip, held in memory so providers need no file access.
class AudioClip {
  const AudioClip({
    required this.bytes,
    this.fileName = 'recording.m4a',
    this.mimeType = 'audio/m4a',
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// One species a provider reported hearing.
class Detection {
  const Detection({
    required this.speciesText,
    this.scientificName,
    this.confidence,
  });

  /// Exactly what the provider said. Not yet resolved to a taxon (Phase 2).
  final String speciesText;
  final String? scientificName;

  /// 0..1 when the provider reports one. NatureLM does not.
  final double? confidence;

  @override
  String toString() => 'Detection($speciesText, $scientificName, $confidence)';
}

/// What a provider answered.
class IdentificationResult {
  const IdentificationResult({
    required this.providerId,
    required this.providerLabel,
    required this.detections,
    this.rawResponse,
  }) : assert(detections.length > 0);

  /// Stable id, e.g. `naturelm`. Drives the privacy badge.
  final String providerId;

  /// Human label, e.g. `NatureLM`.
  final String providerLabel;

  /// Best guess first. Never empty.
  final List<Detection> detections;

  /// Raw body for debugging. Never shown to users, never persisted.
  final String? rawResponse;

  Detection get top => detections.first;
}

enum FailureKind {
  /// Could not connect, DNS failure, offline, or service reports it is down.
  unavailable,
  timeout,

  /// The service answered with an error status.
  rejected,

  /// The service answered but heard no bird.
  noDetection,

  /// The service answered with something we could not read.
  badResponse,
}

/// Thrown by a provider. The chain catches it and moves on.
class ProviderException implements Exception {
  const ProviderException(this.kind, this.message);

  final FailureKind kind;
  final String message;

  @override
  String toString() => 'ProviderException(${kind.name}: $message)';
}

/// A recorded reason one provider did not produce an answer.
class ProviderFailure {
  const ProviderFailure({
    required this.providerId,
    required this.kind,
    required this.message,
    this.skipped = false,
  });

  final String providerId;
  final FailureKind kind;
  final String message;

  /// True when the chain did not even try, because a fresh health check failed.
  final bool skipped;

  @override
  String toString() =>
      'ProviderFailure($providerId, ${kind.name}, skipped: $skipped, $message)';
}

/// Thrown by the chain when every provider failed.
class NoProviderAnsweredException implements Exception {
  const NoProviderAnsweredException(this.failures);

  final List<ProviderFailure> failures;

  /// True when nobody could be reached at all (as opposed to "reached but
  /// heard no bird"). The UI uses this to say "check your connection".
  bool get looksOffline =>
      failures.isNotEmpty &&
      failures.every((f) =>
          f.kind == FailureKind.unavailable || f.kind == FailureKind.timeout);

  /// True when a service answered and said it heard no bird. The UI says
  /// "No bird heard. Try again closer to the sound", not "service failed".
  bool get heardNothing =>
      failures.any((f) => f.kind == FailureKind.noDetection);

  @override
  String toString() => 'NoProviderAnsweredException($failures)';
}

/// An identification service.
abstract interface class IdentificationProvider {
  String get id;
  String get label;

  /// Cheap reachability check. Must not throw; return false on any problem.
  Future<bool> isAvailable();

  /// Identify [clip] or throw [ProviderException].
  Future<IdentificationResult> identify(AudioClip clip);
}
