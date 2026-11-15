import 'package:material_ui/material_ui.dart';

/// Three short screens shown on first launch (and again after "Delete my
/// data", which returns the app to a first launch). Static text only: it does
/// NOT ask for the microphone. The system asks the first time Record is
/// tapped; this just says why first.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called for both "Skip" and "Get started".
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    Icons.hearing,
    'Hear a bird, help the yard',
    'Record a bird\'s sound and EcoYard suggests simple, mostly free ways '
        'to help it, in a yard, on a balcony or in a few pots.',
  ),
  _Page(
    Icons.mic_none,
    'Your microphone, only when you ask',
    'EcoYard asks to use the microphone the first time you tap Record, and '
        'only listens while you record. The short clip is sent online to '
        'identify the bird. EcoYard does not save it on your phone.',
  ),
  _Page(
    Icons.checklist,
    'Your plan stays with you',
    'Your habitat plan and settings are saved on this device only. You can '
        'see them and erase them any time in Settings.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final p in _pages)
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 48),
                          Icon(p.icon, size: 72),
                          const SizedBox(height: 24),
                          Text(
                            p.title,
                            textAlign: TextAlign.center,
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            p.body,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  Semantics(
                    label: 'Page ${i + 1} of ${_pages.length}',
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
