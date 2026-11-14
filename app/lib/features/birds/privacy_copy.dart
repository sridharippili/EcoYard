import 'package:bird_audio/bird_audio.dart';

/// User-facing privacy wording for an identification result.
///
/// Always derived from the service that actually answered, never a fixed
/// sentence: with a fall-through, audio can reach two servers.
///
/// It deliberately does NOT say "not kept". Nobody has audited whether the
/// Kaggle notebook or the Hugging Face Space stores uploads (PLAN.md §0.1).
/// Add that phrase only after both audits.
String privacyBadge(IdentificationResult r) =>
    'Identified online. Audio was sent to ${r.providerLabel} for analysis.';

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
  _ => providerId,
};
