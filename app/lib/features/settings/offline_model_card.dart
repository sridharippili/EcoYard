import 'package:material_ui/material_ui.dart';

import 'offline_model_controller.dart';

/// Settings > Offline identification: get or remove the bird model that
/// identifies recordings on the phone.
class OfflineModelCard extends StatelessWidget {
  const OfflineModelCard({super.key, required this.controller});

  final OfflineModelController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final size = controller.sizeLabel;
        final text = Theme.of(context).textTheme;
        final Widget body;
        switch (controller.state) {
          case OfflineState.checking:
            body = const Text('Checking…');
          case OfflineState.unavailable:
            body = const Text(
              'Not available in this version yet. Recordings are identified '
              'online.',
            );
          case OfflineState.notDownloaded:
            body = _Body(
              'Identify birds on your phone, without sending the recording '
              'anywhere. About $size. Wi-Fi recommended. If the phone model '
              'can’t tell, the recording is sent online, and the result '
              'says so.',
              FilledButton.icon(
                onPressed: controller.askToDownload,
                icon: const Icon(Icons.download),
                label: const Text('Download offline model'),
              ),
            );
          case OfflineState.confirming:
            body = _Body(
              'Download about $size now? Wi-Fi is recommended.',
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: controller.download,
                    child: const Text('Download'),
                  ),
                  OutlinedButton(
                    onPressed: controller.declineDownload,
                    child: const Text('Not now'),
                  ),
                ],
              ),
            );
          case OfflineState.downloading:
            final checking = controller.isChecking;
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checking
                      ? 'Checking the model…'
                      : 'Downloading… ${(controller.progress * 100).floor()}%',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: checking ? null : controller.progress,
                ),
                const SizedBox(height: 8),
                if (!checking)
                  OutlinedButton(
                    onPressed: controller.cancelDownload,
                    child: const Text('Cancel'),
                  ),
              ],
            );
          case OfflineState.ready:
            body = _Body(
              'On this phone. Birds are identified here first. If it can’t '
              'tell, the recording is sent online, and the result says so.',
              OutlinedButton(
                onPressed: controller.remove,
                child: const Text('Remove offline model'),
              ),
            );
          case OfflineState.failed:
            body = _Body(
              '${controller.error ?? 'Something went wrong'}. '
              'Nothing was kept.',
              FilledButton(
                onPressed: controller.askToDownload,
                child: const Text('Try again'),
              ),
              isError: true,
            );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body,
                const SizedBox(height: 8),
                Text(
                  'Model: BirdNET, from the K. Lisa Yang Center for '
                  'Conservation Bioacoustics (Cornell Lab of Ornithology) and '
                  'Chemnitz University of Technology.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.message, this.action, {this.isError = false});
  final String message;
  final Widget action;
  final bool isError;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        message,
        style: isError
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      const SizedBox(height: 8),
      action,
    ],
  );
}
