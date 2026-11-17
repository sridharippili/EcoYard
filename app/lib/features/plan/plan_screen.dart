import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

import '../birds/bird_details.dart' show costLabel;
import 'plan_controller.dart';
import 'reminder_card.dart';
import 'reminder_controller.dart';

/// My Habitat Plan: the actions the user chose, with progress.
class PlanScreen extends StatelessWidget {
  const PlanScreen({
    super.key,
    required this.controller,
    required this.onShowPlants,
    required this.onIdentify,
    required this.reminders,
  });

  final PlanController controller;
  final ReminderController reminders;

  /// Opens the Birds tab, to identify a bird and build a plan from it.
  final VoidCallback onIdentify;

  /// Opens the Plants tab (for actions that mention plants).
  final VoidCallback onShowPlants;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: tabListPadding(context),
          children: [
            Text(
              'My Habitat Plan',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ..._body(context),
            const SizedBox(height: 8),
            ReminderCard(controller: reminders),
            const SizedBox(height: 16),
            // True for the plan only. Nothing here talks about audio.
            const Text(
              'Your plan is saved on this device only. '
              'Not shared or ranked.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (controller.state) {
      case PlanLoadState.loading:
        return const [Center(child: CircularProgressIndicator())];
      case PlanLoadState.failed:
        return [
          const Text(
            "We couldn't open your saved plan. Your plan has not been "
            'deleted.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: controller.init,
              child: const Text('Try again'),
            ),
          ),
        ];
      case PlanLoadState.ready:
        break;
    }

    final view = controller.view!;
    return [
      if (controller.banner != null)
        _Banner(text: controller.banner!, onClose: controller.dismissBanner),
      if (controller.actionError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            controller.actionError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (view.items.isEmpty) ...[
        const Text(
          'Nothing here yet. Identify a bird, then choose "Add these to my '
          'plan" to start.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: onIdentify,
              icon: const Icon(Icons.mic, size: 18),
              label: const Text('Identify a bird'),
            ),
            OutlinedButton(
              onPressed: onShowPlants,
              child: const Text('Find native plants'),
            ),
          ],
        ),
      ] else ...[
        _ProgressCard(progress: view.progress),
        const SizedBox(height: 8),
        for (final item in view.items)
          _PlanTile(
            item: item,
            controller: controller,
            onShowPlants: onShowPlants,
          ),
      ],
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: ListTile(
      leading: const Icon(Icons.check_circle_outline),
      title: Text(text),
      trailing: IconButton(
        tooltip: 'Dismiss',
        icon: const Icon(Icons.close),
        onPressed: onClose,
      ),
    ),
  );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});
  final PlanProgress progress;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${progress.done} of ${progress.total} done',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.fraction),
        ],
      ),
    ),
  );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.item,
    required this.controller,
    required this.onShowPlants,
  });
  final PlanItem item;
  final PlanController controller;
  final VoidCallback onShowPlants;

  @override
  Widget build(BuildContext context) {
    final done = item.isDone;
    final strike = done ? TextDecoration.lineThrough : null;
    final birds = [
      ...item.birds.map((b) => b.commonName),
      if (item.unknownBirdCount > 0)
        '${item.unknownBirdCount} other ${item.unknownBirdCount == 1 ? 'bird' : 'birds'}',
    ];
    return Card(
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: done,
        onChanged: (v) => controller.setDone(item.entry.actionId, v == true),
        title: Text(item.title, style: TextStyle(decoration: strike)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.body, style: TextStyle(decoration: strike)),
            if (birds.isNotEmpty) Text('For ${birds.join(', ')}'),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(costLabel(item.costJson)),
                if (item.action?.relatedPlantIds.isNotEmpty ?? false)
                  TextButton(
                    onPressed: onShowPlants,
                    child: const Text('See native plants'),
                  ),
                if (item.isRemovedFromContent) ...[
                  const Text('No longer in our advice'),
                  TextButton(
                    onPressed: () => controller.remove(item.entry.actionId),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
