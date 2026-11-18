import 'package:bird_audio/bird_audio.dart' show ExportOutcome;
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../app/filter_menus.dart';
import '../../app/surfaces.dart';
import '../../app/theme.dart';

import '../../app/content.dart';
import '../plants/plant_labels.dart';
import 'offline_model_card.dart';
import 'offline_model_controller.dart';
import 'privacy_pages.dart';
import 'settings_controller.dart';

/// Privacy & Settings: what EcoYard can access, what it stores, and the
/// controls for it.
///
/// Spec 4.5 toggles for location, progress data and research sharing are
/// left out on purpose: each would control nothing today (docs/STATE.md,
/// "Deviations from the spec").
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.offline,
    required this.content,
    required this.onErased,
  });

  final SettingsController controller;
  final OfflineModelController offline;
  final AppContent content;

  /// Called after "Delete my data" succeeded, so the Shell can reset every
  /// screen that holds a copy of the data.
  final Future<void> Function() onErased;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        Widget h(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(
            t,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
        return ListView(
          padding: tabListPadding(context),
          children: [
            Text(
              'Privacy & Settings',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const InfoSurface(
              child: Text(
                'Your privacy matters. You control your data. Everything '
                'EcoYard saves is on this device, and you can see it or '
                'erase it here.',
              ),
            ),
            if (controller.state == SettingsLoadState.failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        "We couldn't read your saved settings, so the "
                        'standard choices are shown. Nothing was deleted.',
                      ),
                    ),
                    TextButton(
                      onPressed: controller.init,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            h('My defaults'),
            const Text(
              'The starting choices in Plants and in bird advice. You can '
              'still change them on each screen.',
            ),
            const SizedBox(height: 6),
            _Defaults(controller: controller),
            h('Offline identification'),
            OfflineModelCard(controller: offline),
            h('Privacy at a glance'),
            const _Fact(
              Icons.mic_none,
              'Microphone',
              'Used only while you record, after you tap Record. You can turn '
                  'it off in the iPhone Settings app, under EcoYard.',
              status: 'Only when recording',
            ),
            ListenableBuilder(
              listenable: offline,
              builder: (context, _) => _Fact(
                Icons.cloud_upload_outlined,
                'Recordings',
                status: offline.state == OfflineState.ready
                    ? 'On phone first'
                    : 'Sent online',
                offline.state == OfflineState.ready
                    ? 'With the offline model on this phone, a recording is '
                          'identified here first and not sent anywhere. Only '
                          'if the phone model can\'t tell is it sent online, to '
                          'NatureLM and BirdNET at the same time, and the '
                          'result says so. EcoYard does not save it on '
                          'your phone. How those services handle it is up to '
                          'them.'
                    : 'A recording is sent online to NatureLM and BirdNET at '
                          'the same time, so a quick answer can show first '
                          'while NatureLM checks it. '
                          'EcoYard does not save it on your phone. How those '
                          'services handle it is up to them. You can download '
                          'the offline model above to identify on your '
                          'phone instead.',
              ),
            ),
            const _Fact(
              Icons.photo_outlined,
              'Bird photos',
              'For a bird we have no photo of, EcoYard asks Wikimedia for one '
                  'and sends only the bird\'s name. Nothing is saved.',
              status: 'Name only',
            ),
            _LocationFact(controller: controller),
            const _Fact(
              Icons.phone_iphone,
              'My plan',
              'Saved on this device only.',
              status: 'This device',
            ),
            h('My data'),
            // One bordered list with dividers. Delete my data is NOT in it:
            // an irreversible action must not look like navigation.
            InteractiveSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _NavRow(
                    icon: Icons.inventory_2_outlined,
                    title: 'Manage my data',
                    subtitle: 'See what is saved, or copy it',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ManageDataScreen(controller: controller),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _NavRow(
                    icon: Icons.policy_outlined,
                    title: 'Privacy policy',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PrivacyPolicyScreen(content: content),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _NavRow(
                    icon: Icons.info_outline,
                    title: 'About EcoYard',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AboutScreen(content: content),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No ads. No analytics in the app. We don\'t sell your data.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (content.isDraft)
              Text(
                'Draft wording, to be confirmed by the app\'s owner before '
                'release.',
                style: text.bodySmall,
              ),
            const SizedBox(height: 40),
            _DeleteButton(
              onPressed: () => confirmAndErase(context, controller, onErased),
            ),
            const SizedBox(height: 8),
            Text(
              'Erases your plan, your settings and the offline model from '
              'this phone.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// What EcoYard currently does with location: it depends on whether the
/// user has chosen a place, so it is read from the settings rather than
/// being a fixed sentence.
class _LocationFact extends StatelessWidget {
  const _LocationFact({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    final place = s.place;
    final String body;
    if (place == null) {
      body =
          'Not used. EcoYard asks only if you tap "Use my area" on the '
          'weather card, and you can type a town instead.';
    } else if (s.useDeviceLocation) {
      body =
          'Your approximate area (${place.label}), rounded to about 10 '
          'miles, is saved on this device and sent to the weather service '
          'to get the forecast. Your exact position is never used or '
          'saved. Change or remove it on the weather card.';
    } else {
      body =
          'You chose ${place.label}. Only that town, rounded to about 10 '
          'miles, is sent to the weather service. Your device location is '
          'not used.';
    }
    return _Fact(
      Icons.place_outlined,
      'Location',
      body,
      status: place == null ? 'Off' : 'On',
    );
  }
}

/// One privacy fact as a bordered row: icon, title, what EcoYard does, and a
/// short status. It has no switch on purpose: each of these is either decided
/// by the iPhone (the microphone) or by an action elsewhere (the weather
/// card, Delete my data), and a switch that controls nothing would mislead.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.title, this.body, {this.status});
  final IconData icon;
  final String title;
  final String body;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InteractiveSurface(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: t.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (status != null)
                        Flexible(
                          child: InfoPill(
                            label: status!,
                            background: t.surfaceInfo,
                            foreground: t.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Defaults extends StatelessWidget {
  const _Defaults({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterMenuRow(
          menus: [
            FilterMenu<SpaceType>(
              key: filterSpaceKey,
              label: 'My space',
              value: s.defaultSpace,
              options: [for (final v in SpaceType.values) (v, spaceLabel(v))],
              onChanged: (v) => controller.saveDefaults(space: v),
            ),
            FilterMenu<SunExposure>(
              key: filterSunKey,
              label: 'Sunlight',
              value: s.defaultSun,
              options: [for (final v in SunExposure.values) (v, sunLabel(v))],
              onChanged: (v) => controller.saveDefaults(sun: v),
            ),
            FilterMenu<BudgetTier>(
              key: filterBudgetKey,
              label: 'Budget',
              value: s.defaultBudget,
              options: const [
                (BudgetTier.low, 'Low cost'),
                (BudgetTier.free, 'Free only'),
                (BudgetTier.any, 'Any'),
              ],
              onChanged: (v) => controller.saveDefaults(budget: v),
            ),
          ],
        ),
        if (controller.saveError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              controller.saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Real counts of what is saved, and a way to copy it.
class ManageDataScreen extends StatefulWidget {
  const ManageDataScreen({super.key, required this.controller});
  final SettingsController controller;

  @override
  State<ManageDataScreen> createState() => _ManageDataScreenState();
}

class _ManageDataScreenState extends State<ManageDataScreen> {
  late Future<DataSummary> _summary = widget.controller.summary();
  String? _copyMessage;

  Future<void> _share(BuildContext context) async {
    // iPad needs to know where to anchor the sheet.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final outcome = await widget.controller.exportFile(origin: origin);
      if (!mounted) return;
      setState(() {
        _copyMessage = switch (outcome) {
          ExportOutcome.shared => 'Your data was handed to the app you chose.',
          ExportOutcome.dismissed => null,
          ExportOutcome.failed =>
            "Couldn't open the share sheet. You can copy your data instead.",
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _copyMessage = "Couldn't read your data to share it.");
    }
  }

  Future<void> _copy() async {
    try {
      final text = await widget.controller.exportText();
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _copyMessage = 'Copied. Paste it into a note to keep it.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _copyMessage = "Couldn't read your data to copy it.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage my data')),
      body: SafeArea(
        child: FutureBuilder<DataSummary>(
          future: _summary,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "We couldn't read what is saved on this device. Nothing "
                      'was deleted.',
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _summary = widget.controller.summary();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!;
            String n(int c, String one, String many) =>
                '$c ${c == 1 ? one : many}';
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Saved on this device',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  n(
                    d.planActions,
                    'action in your plan',
                    'actions in your plan',
                  ),
                ),
                Text(
                  n(d.birdsInPlan, 'bird in your plan', 'birds in your plan'),
                ),
                Text(n(d.settingsStored, 'saved setting', 'saved settings')),
                const SizedBox(height: 12),
                const Text(
                  'EcoYard does not save recordings, and has no location '
                  'history.',
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (ctx) => FilledButton.icon(
                    onPressed: () => _share(ctx),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Save or share my data'),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Makes a file only while you share it, and deletes it '
                  'straight afterwards. Where it goes next depends on the '
                  'app you pick.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy my data'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The copy goes to your clipboard, which other apps on your '
                  'phone may be able to read.',
                  style: TextStyle(fontSize: 12),
                ),
                if (_copyMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_copyMessage!),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Asks once, then erases. Says exactly what was erased, and what was not.
Future<void> confirmAndErase(
  BuildContext context,
  SettingsController controller,
  Future<void> Function() onErased,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete my data?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This erases your plan and your saved settings from this device '
              'and returns EcoYard to its first launch.',
            ),
            const SizedBox(height: 12),
            const Text('It will erase:'),
            const SizedBox(height: 4),
            for (final line in const [
              'Every action in your habitat plan, ticked or not',
              'Your settings: defaults, chosen town and weekly reminder',
              'The offline bird model, if you downloaded it (about 52 MB; '
                  'you can download it again)',
            ])
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $line'),
              ),
            const SizedBox(height: 12),
            const Text(
              'It cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Recordings already sent to NatureLM or BirdNET for '
              'identification are outside the app, so they cannot be erased '
              'from here.',
            ),
          ],
        ),
      ),
      actions: [
        // Cancel is the emphasised choice; the destructive one is plain text.
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: ctx.eco.destructive),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await controller.deleteEverything();
    await onErased();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Your plan and settings were erased from this device.'),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Couldn't erase your data. Please try again."),
      ),
    );
  }
}

/// One row of the Settings list. The list around it is the bordered surface.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: t.accentText),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(color: t.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// A bordered button in the destructive colour: red text, red border, no
/// fill, no chevron. Deliberately not a list row.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final red = context.eco.destructive;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete my data'),
        style: OutlinedButton.styleFrom(
          foregroundColor: red,
          side: BorderSide(color: red, width: 1.5),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );
  }
}
