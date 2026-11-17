import 'package:bird_audio/bird_audio.dart' show ExportOutcome;
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

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
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Your privacy matters. You control your data. Everything '
                  'EcoYard saves is on this device, and you can see it or '
                  'erase it here.',
                ),
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
            ),
            ListenableBuilder(
              listenable: offline,
              builder: (context, _) => _Fact(
                Icons.cloud_upload_outlined,
                'Recordings',
                offline.state == OfflineState.ready
                    ? 'With the offline model on this phone, a recording is '
                          'identified here first and not sent anywhere. Only '
                          'if the phone model can\'t tell is it sent online, to '
                          'NatureLM (or BirdNET if NatureLM is not available), '
                          'and the result says so. EcoYard does not save it on '
                          'your phone. How those services handle it is up to '
                          'them.'
                    : 'A recording is sent online to NatureLM (or to BirdNET '
                          'if NatureLM is not available) to identify the bird. '
                          'EcoYard does not save it on your phone. How those '
                          'services handle it is up to them. You can download '
                          'the offline model above to identify on your '
                          'phone instead.',
              ),
            ),
            _LocationFact(controller: controller),
            const _Fact(
              Icons.phone_iphone,
              'My plan',
              'Saved on this device only.',
            ),
            h('My data'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Manage my data'),
              subtitle: const Text('See what is saved, or copy it'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ManageDataScreen(controller: controller),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Delete my data'),
              subtitle: const Text('Erase my plan and settings'),
              onTap: () => confirmAndErase(context, controller, onErased),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PrivacyPolicyScreen(content: content),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('About EcoYard'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AboutScreen(content: content),
                ),
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
    return _Fact(Icons.place_outlined, 'Location', body);
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Defaults extends StatelessWidget {
  const _Defaults({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    Widget row<T>(
      String label,
      List<(T, String)> options,
      T value,
      Future<bool> Function(T) save,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: Text(label),
          ),
          for (final (v, t) in options)
            ChoiceChip(
              label: Text(t),
              selected: v == value,
              showCheckmark: true,
              onSelected: (_) => save(v),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row<SpaceType>(
          'My space',
          [for (final v in SpaceType.values) (v, spaceLabel(v))],
          s.defaultSpace,
          (v) => controller.saveDefaults(space: v),
        ),
        row<SunExposure>(
          'Sunlight',
          [for (final v in SunExposure.values) (v, sunLabel(v))],
          s.defaultSun,
          (v) => controller.saveDefaults(sun: v),
        ),
        row<BudgetTier>(
          'Budget',
          const [
            (BudgetTier.low, 'Low cost'),
            (BudgetTier.free, 'Free only'),
            (BudgetTier.any, 'Any'),
          ],
          s.defaultBudget,
          (v) => controller.saveDefaults(budget: v),
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
      content: const Text(
        'This erases your plan and your saved settings from this device and '
        'returns EcoYard to its first launch. If you downloaded the offline '
        'model, it is removed too. It cannot be undone.\n\n'
        'Recordings already sent to NatureLM or BirdNET for identification '
        'are outside the app, so they cannot be erased from here.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
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
