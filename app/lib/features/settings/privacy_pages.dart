import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/about.dart';
import '../../app/content.dart';

/// Plain-language privacy summary. A draft: the app's owner (and a lawyer)
/// must confirm it before release (docs/STATE.md).
///
/// Wording rules (CLAUDE.md rule 7): never say audio stays on the device, and
/// never say the identification services do not keep it: nobody has audited
/// them. Only say what EcoYard itself does.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, required this.content});
  final AppContent content;

  @override
  Widget build(BuildContext context) {
    Widget h(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        t,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (content.isDraft)
              const Text(
                'Draft summary, not yet reviewed by the app\'s owner.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            h('The short version'),
            const Text(
              'EcoYard has no account and no sign-in. Your habitat plan and '
              'settings are saved on this device. Three things can leave your '
              'phone: the short recording you choose to identify, a rough '
              'area used to fetch the weather (only if you choose one), and '
              'the name of a bird, to look up its photo.',
            ),
            h('What is saved on your device'),
            const Text(
              'Your habitat plan (the actions you added and ticked off, and '
              'which birds they were for) and your settings. You can see '
              'what is saved, copy it, or erase it in Settings.',
            ),
            h('What is sent online'),
            const Text(
              'When you tap Record and stop, the short clip is sent over the '
              'internet to NatureLM and to BirdNET at the same time, so a '
              'quick answer can show first while NatureLM checks it. If one '
              'of them is not available, the other still answers. Like any '
              'internet request, each service can see your network address. '
              'How those services handle the clip is up to them: EcoYard '
              'cannot erase '
              'it for you. EcoYard does not save the clip on your phone.\n\n'
              'If you download the offline model in Settings, a model '
              'on the phone listens to the clip first and nothing is sent anywhere. Only '
              'if the phone model cannot tell is it sent online as above, '
              'and the result says so.',
            ),
            h('Bird photos'),
            const Text(
              'When a result shows a bird we have no photo of, EcoYard asks '
              'Wikipedia and Wikimedia Commons for one. Only the bird\'s name '
              'is sent: not your recording, not your location, and nothing '
              'else about you. Like any web request, Wikimedia can see your '
              'phone\'s network address. Nothing is saved: the photo is shown '
              'and forgotten. Each one is shown with its author and licence. '
              'If there is no connection, a silhouette is shown instead.',
            ),
            h('Location and the weather'),
            const Text(
              'The weather card is off until you choose a place. You can '
              'type a town, or let EcoYard use your approximate location. '
              'Either way it is rounded to about 10 miles before it is '
              'saved or sent, your exact position is never used, and no '
              'history of where you have been is kept. The rounded place '
              'goes to Open-Meteo, the weather service, with nothing that '
              'identifies you. Remove it any time on the weather card.',
            ),
            h('The weekly reminder'),
            const Text(
              'The reminder is off until you turn it on in My Plan, and '
              'only then does your phone ask to allow notifications. It is '
              'made and shown on your phone; nothing is sent to anyone. The '
              'message is the same for everyone and never names your plan. '
              'Turn it off in My Plan, or "Delete my data" removes it.',
            ),
            h('What EcoYard does not do'),
            const Text(
              'It does not ask for your contacts or photos, does not track '
              'where you have been, and does not include advertising or '
              'analytics tools.',
            ),
            h('Erasing your data'),
            const Text(
              '"Delete my data" in Settings erases your plan and settings '
              'from this device and returns EcoYard to its first launch. It '
              'cannot erase a backup you may have made of your phone, or '
              'recordings already sent for identification.',
            ),
            const SizedBox(height: 16),
            Text(
              'EcoYard $appVersion',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Version, where the information comes from, and credits.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.content});
  final AppContent content;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget h(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        t,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('About EcoYard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Version $appVersion'),
            if (content.isDraft)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'The bird, plant and tip information is a draft that has '
                  'not been reviewed yet.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            h('Where the information comes from'),
            for (final s in content.repo.allSources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $s'),
              ),
            h('Bird sound identification'),
            const Text(
              'The NatureLM and BirdNET online services, and BirdNET on your '
              'phone if you download the offline model (K. Lisa Yang Center '
              'for Conservation Bioacoustics, Cornell Lab of Ornithology, and '
              'Chemnitz University of Technology). Results are possible '
              'matches, not certainties.',
            ),
            h('Photos'),
            if (content.photos.isEmpty)
              const Text('No photos yet. Credits will be listed here.')
            else ...[
              Text(
                '${content.photos.all.length} species photos from Wikimedia '
                'Commons, each used under its own licence.',
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PhotoCreditsScreen(content: content),
                    ),
                  ),
                  child: const Text('Photo credits'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Every photo we ship, with its author and licence. Required by the
/// Creative Commons licences the photos are used under.
class PhotoCreditsScreen extends StatelessWidget {
  const PhotoCreditsScreen({super.key, required this.content});
  final AppContent content;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final photos = [...content.photos.all]
      ..sort((a, b) {
        final k = a.kind.compareTo(b.kind);
        return k != 0 ? k : a.id.compareTo(b.id);
      });
    String nameFor(PhotoCredit p) =>
        (p.isBird
            ? content.repo.birdById(p.id)?.commonName
            : content.repo.plantById(p.id)?.commonName) ??
        p.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Photo credits')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Photos come from Wikimedia Commons. Each one is used under '
              'the licence below, and belongs to the person named. Photos of '
              'other birds are found when you identify them and are credited '
              'right under the photo.',
            ),
            const SizedBox(height: 12),
            for (final p in photos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nameFor(p),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text('${p.author} · ${p.licence}'),
                    if (p.sourceUrl.isNotEmpty)
                      Text(p.sourceUrl, style: text.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
