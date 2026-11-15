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
              'settings are saved on this device. EcoYard does not use your '
              'location. The one thing that leaves your phone is the short '
              'recording you choose to identify.',
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
              'internet to NatureLM to identify the bird. If NatureLM is not '
              'available, it is sent to BirdNET instead. Like any internet '
              'request, the service can see your network address. How those '
              'services handle the clip is up to them: EcoYard cannot erase '
              'it for you. EcoYard does not save the clip on your phone.',
            ),
            h('What EcoYard does not do'),
            const Text(
              'It does not use your location, does not ask for your contacts '
              'or photos, and does not include advertising or analytics '
              'tools.',
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
              'The NatureLM and BirdNET online services. Results are '
              'possible matches, not certainties.',
            ),
            h('Photos'),
            const Text('No photos yet. Credits will be listed here.'),
          ],
        ),
      ),
    );
  }
}
