import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/app_environment.dart';

import 'package:bird_audio/bird_audio.dart'
    show Detection, RemotePhoto, SpeciesPhotoLookup;
import 'package:ecoyard_core/ecoyard_core.dart'
    show AppSettings, MatchConfidence, PhotoCredit, SpeciesMatch;

import '../../app/content.dart';
import '../../app/surfaces.dart';
import '../../app/theme.dart';
import '../plan/plan_controller.dart';
import '../plants/species_photo.dart';
import 'bird_details.dart';
import 'birds_controller.dart';
import 'privacy_copy.dart';

class BirdsScreen extends StatefulWidget {
  const BirdsScreen({
    super.key,
    required this.env,
    required this.content,
    required this.plan,
    required this.settings,
    required this.onOpenPlan,
  });

  final AppEnvironment env;
  final AppContent content;
  final PlanController plan;

  /// The user's starting choices for the advice (read when a result appears).
  final AppSettings Function() settings;

  /// Switches to the My Plan tab.
  final VoidCallback onOpenPlan;

  @override
  State<BirdsScreen> createState() => _BirdsScreenState();
}

class _BirdsScreenState extends State<BirdsScreen> {
  late final BirdsController _c = BirdsController(
    recorder: widget.env.newRecorder(),
    chain: widget.env.chain,
  );

  SpeciesMatch _matchFor(Detection d) => widget.content.resolver.resolve(
    rawName: d.speciesText,
    scientificName: d.scientificName,
    confidence: d.confidence,
  );

  @override
  void initState() {
    super.initState();
    _c.checkHealth();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => ListView(
        padding: tabListPadding(context),
        children: [
          Text(
            'Identify a Bird',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Record up to 10 seconds of the sound, then tap again '
            'to finish early.',
          ),
          const SizedBox(height: 12),
          _HealthNote(controller: _c),
          const SizedBox(height: 12),
          _RecordButton(controller: _c),
          if (_c.phase == BirdsPhase.identifying) const _SlowHint(),
          if (_c.micDenied) ...[
            const SizedBox(height: 12),
            const _Notice(
              icon: Icons.mic_off,
              text:
                  'Microphone access is off. Turn it on in Settings to '
                  'identify birds by sound.',
            ),
          ],
          const SizedBox(height: 16),
          switch (_c.phase) {
            BirdsPhase.result => _ResultCard(
              controller: _c,
              match: _matchFor(_c.outcome!.result.top),
              photo: BirdDetailsPanel.photoFor(
                widget.content,
                _c.outcome!.result.top,
              ),
              lookup: widget.env.photoLookup,
              photoImage: widget.env.photoImage,
              details: BirdDetailsPanel(
                // A new answer is a new panel, so choices and ticks reset.
                key: ObjectKey(_c.outcome),
                detection: _c.outcome!.result.top,
                content: widget.content,
                plan: widget.plan,
                settings: widget.settings(),
                now: widget.env.now,
                onOpenPlan: () {
                  _c.dismiss();
                  widget.onOpenPlan();
                },
              ),
            ),
            BirdsPhase.failed => _FailureCard(controller: _c),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _HealthNote extends StatelessWidget {
  const _HealthNote({required this.controller});
  final BirdsController controller;

  @override
  Widget build(BuildContext context) {
    final h = controller.health;
    if (h == null) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Checking identification services…'),
        ],
      );
    }
    if (!h.anyAvailable) {
      return _Notice(
        icon: Icons.cloud_off,
        text:
            'The identification services look unreachable right now. '
            'You can still try.',
        action: TextButton(
          onPressed: () => controller.checkHealth(force: true),
          child: const Text('Check again'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.controller});
  final BirdsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final recording = c.phase == BirdsPhase.recording;
    final identifying = c.phase == BirdsPhase.identifying;

    final label = identifying
        ? 'Identifying…'
        : recording
        ? 'Recording ${c.elapsedSeconds}s of ${c.maxRecording.inSeconds}s. '
              'Tap to stop'
        : 'Tap to record';

    final t = context.eco;
    // The screen's primary action: filled accent (the destructive colour
    // while recording, since the next tap stops it).
    return Material(
      color: recording ? t.destructive : t.accent,
      borderRadius: BorderRadius.circular(surfaceRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(surfaceRadius),
        onTap: identifying ? null : c.toggleRecording,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: t.accentOn.withValues(alpha: 0.20),
                child: identifying
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accentOn,
                        ),
                      )
                    : Icon(
                        recording ? Icons.stop : Icons.mic,
                        color: t.accentOn,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: t.accentOn,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The words for how much to trust a match, from BOTH the provider's score
/// and how the name was matched (a fuzzy match at 0.9 is never "high").
String confidenceLabel(MatchConfidence c) => switch (c) {
  MatchConfidence.high => 'HIGH CONFIDENCE',
  MatchConfidence.medium => 'MEDIUM CONFIDENCE',
  MatchConfidence.low => 'LOW CONFIDENCE',
};

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.controller,
    required this.details,
    required this.photo,
    required this.match,
    required this.lookup,
    required this.photoImage,
  });
  final BirdsController controller;
  final Widget details;
  final PhotoCredit? photo;
  final SpeciesPhotoLookup lookup;
  final ImageProvider Function(String url) photoImage;

  /// What the species resolver made of the top answer.
  final SpeciesMatch match;

  @override
  Widget build(BuildContext context) {
    final o = controller.outcome!;
    final top = o.result.top;
    final others = o.result.detections.skip(1).toList();
    final note = fallbackNote(o);
    final text = Theme.of(context).textTheme;

    final t = context.eco;
    // Two levels only, both straight on the page: the finding is one
    // information surface, and the advice below it sits on the page itself
    // (its own rows are bordered, so nothing is nested in a tinted card).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The photo sits on the page at the top. With no credited photo it is
        // a bird silhouette of the same shape, never an empty gap.
        _HeroPhoto(
          // A new answer is a new photo, so the lookup runs again.
          key: ValueKey('${top.speciesText}|${top.scientificName}'),
          bundled: photo,
          lookup: lookup,
          image: photoImage,
          // Only a real bird we have no bundled photo for, and not a guess so
          // unsure that no advice is shown either.
          name: match.isResolved ? match.commonName! : top.speciesText,
          scientificName: match.scientificName ?? top.scientificName,
          enabled:
              photo == null &&
              match.isBird &&
              (match.isResolved ||
                  match.providerConfidence == null ||
                  match.providerConfidence! >= 0.4),
        ),
        const SizedBox(height: 12),
        InfoSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POSSIBLE MATCH · ${confidenceLabel(match.confidence)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // The species we resolved to, so a mis-heard "cardinal" shows
                // as what it was matched to; the provider's own words when it
                // is a species we have no content for.
                match.isResolved ? match.commonName! : top.speciesText,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              // From the resolved species when we have it: NatureLM gives no
              // scientific name, and "Cardinal" alone is ambiguous.
              if ((match.scientificName ?? top.scientificName) case final sci?
                  when sci.isNotEmpty)
                Text(
                  sci,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: t.textSecondary,
                  ),
                ),
              // Only BirdNET reports a confidence. NatureLM reports none, and
              // we never invent one.
              if (top.confidence != null)
                Text(
                  'Confidence ${(top.confidence! * 100).round()}%',
                  style: TextStyle(color: t.textSecondary),
                ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Also heard',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                for (final d in others)
                  Text(d.speciesText, style: TextStyle(color: t.textPrimary)),
              ],
              if (o.audioLeftDevice) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: t.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${o.result.providerLabel} · online',
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              // The quick answer is shown first; this says what is happening to
              // it, and afterwards what the better service decided.
              if (controller.refining) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Quick answer. Checking with NatureLM for a better '
                        'match…',
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ] else if (controller.replacedAnswer != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${controller.replacedBy} updated this answer. The quick '
                  'answer had been ${controller.replacedAnswer}.',
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ] else if (controller.confirmedBy != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Confirmed by ${controller.confirmedBy}.',
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
              if (privacyBadge(o) case final badge?) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.phone_iphone, size: 16, color: t.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        badge,
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (controller.canRetry) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: controller.retry,
                        child: const Text('Try again'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: controller.dismiss,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        details,
      ],
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.controller});
  final BirdsController controller;

  @override
  Widget build(BuildContext context) {
    final f = controller.failure;
    final String title;
    final String body;
    if (controller.localError != null) {
      title = 'Something went wrong';
      body = controller.localError!;
    } else if (f != null && f.heardNothing) {
      title = 'No bird heard';
      body = 'Try again closer to the sound, with less background noise.';
    } else if (f != null && f.looksOffline) {
      title = 'Could not reach the identification services';
      body =
          'Check your connection and try again. Identification needs '
          'internet in this version.';
    } else {
      title = 'Identification failed';
      body =
          'The services answered with errors. Please try again in a '
          'moment.';
    }

    final t = context.eco;
    return InfoSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: t.textPrimary)),
          if (f != null && f.failures.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in f.failures)
              Text(
                '• ${p.message}',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (controller.canRetry)
                TextButton(
                  onPressed: controller.retry,
                  child: const Text('Try again'),
                ),
              TextButton(
                onPressed: controller.dismiss,
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return InfoSurface(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: t.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: t.textPrimary)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Shown only when identifying takes more than a few seconds (the online
/// model can take about 20, longer the first time). An answer from the model
/// on the phone arrives before this appears.
class _SlowHint extends StatefulWidget {
  const _SlowHint();

  @override
  State<_SlowHint> createState() => _SlowHintState();
}

class _SlowHintState extends State<_SlowHint> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Still working. The online service can take up to 30 seconds, '
        'and longer the first time.',
        style: TextStyle(fontSize: 12, color: context.eco.textSecondary),
      ),
    );
  }
}

/// The picture at the top of a result: our own photo when we have one, else a
/// photo found on Wikimedia Commons (with the credit its licence requires),
/// else a silhouette. Never an empty gap.
class _HeroPhoto extends StatefulWidget {
  const _HeroPhoto({
    super.key,
    required this.bundled,
    required this.lookup,
    required this.image,
    required this.name,
    required this.scientificName,
    required this.enabled,
  });

  final PhotoCredit? bundled;
  final SpeciesPhotoLookup lookup;
  final ImageProvider Function(String url) image;
  final String name;
  final String? scientificName;
  final bool enabled;

  @override
  State<_HeroPhoto> createState() => _HeroPhotoState();
}

class _HeroPhotoState extends State<_HeroPhoto> {
  Future<RemotePhoto?>? _found;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _found = widget.lookup.find(
        name: widget.name,
        scientificName: widget.scientificName,
      );
    }
  }

  Widget _placeholder() => SpeciesPhoto.hero(
    credit: widget.bundled,
    radius: surfaceRadius,
    birdPlaceholder: true,
  );

  @override
  Widget build(BuildContext context) {
    final found = _found;
    if (widget.bundled != null || found == null) return _placeholder();
    return FutureBuilder<RemotePhoto?>(
      future: found,
      builder: (context, snap) {
        final photo = snap.data;
        if (photo == null) return _placeholder();
        return _RemoteHero(photo: photo, image: widget.image(photo.imageUrl));
      },
    );
  }
}

/// A found photo at the top of a result, with its credit underneath. If the
/// image itself cannot be loaded it falls back to the silhouette, and then
/// shows no credit for a photo that is not there.
class _RemoteHero extends StatefulWidget {
  const _RemoteHero({required this.photo, required this.image});
  final RemotePhoto photo;
  final ImageProvider image;

  @override
  State<_RemoteHero> createState() => _RemoteHeroState();
}

class _RemoteHeroState extends State<_RemoteHero> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    Widget silhouette() => SpeciesPhoto.hero(
      credit: null,
      radius: surfaceRadius,
      birdPlaceholder: true,
    );
    if (_failed) return silhouette();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(surfaceRadius),
          child: AspectRatio(
            aspectRatio: 1.5,
            child: Image(
              image: widget.image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : silhouette(),
              errorBuilder: (context, error, stack) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_failed) setState(() => _failed = true);
                });
                return silhouette();
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            widget.photo.creditLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}
