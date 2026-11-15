import 'package:bird_audio/bird_audio.dart';

/// User-facing privacy wording for one identification.
/// Takes the whole outcome, never just the result: the claim depends on
/// every provider that was tried, not on who finally answered.
///
/// It deliberately does NOT say the services do not keep the audio. Nobody
/// has audited the Kaggle notebook or the Hugging Face Space (PLAN.md 0.1).
String privacyBadge(ChainOutcome o) {
  if (!o.audioLeftDevice) {
    // Only when the on-device model answered and nothing was uploaded first.
    return 'Identified on this phone. The recording was not sent anywhere.';
  }
  return 'Identified online. Audio was sent to ${o.result.providerLabel} '
      'for analysis.';
}

/// Explains a fall-through, or null when the first provider answered.
String? fallbackNote(ChainOutcome o) {
  final tried = o.failuresBefore;
  if (tried.isEmpty) return null;
  final names = tried.map((f) => _label(f.providerId)).toSet().join(' and ');
  final verb = tried.every((f) => f.skipped)
      ? 'was not available'
      : 'did not answer';
  return '$names $verb, so ${o.result.providerLabel} answered.';
}

String _label(String providerId) => switch (providerId) {
  'naturelm' => 'NatureLM',
  'birdnet' => 'BirdNET',
  'birdnet-local' => 'the model on this phone',
  _ => providerId,
};
