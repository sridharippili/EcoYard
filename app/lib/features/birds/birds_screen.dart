import 'package:material_ui/material_ui.dart';

import '../../app/app_environment.dart';

import 'package:ecoyard_core/ecoyard_core.dart' show AppSettings, PhotoCredit;

import '../../app/content.dart';
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
              photo: BirdDetailsPanel.photoFor(
                widget.content,
                _c.outcome!.result.top,
              ),
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

    return Material(
      color: recording ? Colors.red.shade700 : EcoColors.forest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: identifying ? null : c.toggleRecording,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white24,
                child: identifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        recording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.controller,
    required this.details,
    required this.photo,
  });
  final BirdsController controller;
  final Widget details;
  final PhotoCredit? photo;

  @override
  Widget build(BuildContext context) {
    final o = controller.outcome!;
    final top = o.result.top;
    final others = o.result.detections.skip(1).toList();
    final note = fallbackNote(o);
    final text = Theme.of(context).textTheme;

    return Card(
      color: EcoColors.leaf,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null) ...[
              SpeciesPhoto.hero(credit: photo),
              const SizedBox(height: 12),
            ],
            const Text(
              'POSSIBLE MATCH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              top.speciesText,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (top.scientificName != null)
              Text(
                top.scientificName!,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                ),
              ),
            // Only BirdNET reports a confidence. NatureLM reports none, and
            // we never invent one.
            if (top.confidence != null)
              Text(
                'Confidence ${(top.confidence! * 100).round()}%',
                style: const TextStyle(color: Colors.black54),
              ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Also heard',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              for (final d in others)
                Text(
                  d.speciesText,
                  style: const TextStyle(color: Colors.black87),
                ),
            ],
            if (privacyBadge(o) case final badge?) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.phone_iphone,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
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
            // The card is always light green, so its contents use the light
            // theme even in dark mode (otherwise: pale text on pale green).
            Theme(data: ecoTheme(Brightness.light), child: details),
            const SizedBox(height: 8),
          ],
        ),
      ),
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

    return Card(
      color: EcoColors.clay,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.black87)),
            if (f != null && f.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final p in f.failures)
                Text(
                  '• ${p.message}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EcoColors.sand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.black87)),
          ),
          ?action,
        ],
      ),
    );
  }
}
