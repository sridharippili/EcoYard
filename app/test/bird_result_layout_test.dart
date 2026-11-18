import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/bird_icon.dart';
import 'package:ecoyard/app/surfaces.dart';
import 'package:ecoyard/app/theme.dart';
import 'package:ecoyard/features/birds/bird_details.dart';
import 'package:ecoyard/features/plants/species_photo.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'contrast.dart';
import 'edge_cases_test.dart' show identify;
import 'fakes.dart';

void main() {
  group('hero photo', () {
    testWidgets('a bird with a photo shows it at the top, on the page', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardinal');
      expect(find.byType(SpeciesPhoto), findsWidgets);
      final photo = tester.getTopLeft(find.byType(SpeciesPhoto).first).dy;
      final name = tester.getTopLeft(find.text('Northern Cardinal').first).dy;
      expect(photo, lessThan(name));
      // Not inside the tinted finding card.
      expect(
        find.ancestor(
          of: find.byType(SpeciesPhoto).first,
          matching: find.byType(InfoSurface),
        ),
        findsNothing,
      );
    });

    testWidgets('a sound with no species photo shows a bird silhouette of the '
        'same shape, never a gap', (tester) async {
      await identify(tester, 'Eurasian Teal');
      expect(find.byType(SpeciesPhoto), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(SpeciesPhoto).first,
          matching: find.byType(BirdIcon),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SpeciesPhoto).first,
          matching: find.byIcon(Icons.eco),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(SpeciesPhoto).first).height,
        greaterThan(150),
      );
    });
  });

  group('the finding', () {
    testWidgets('keeps the provider line, the confidence band and the '
        'scientific name in italic', (tester) async {
      await identify(
        tester,
        'Northern Cardinal',
        scientific: 'Cardinalis cardinalis',
      );
      expect(find.textContaining('POSSIBLE MATCH · '), findsOneWidget);
      expect(find.textContaining('online'), findsWidgets);
      final sci = tester.widget<Text>(find.text('Cardinalis cardinalis'));
      expect(sci.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('Try again and Done are real buttons', (tester) async {
      await identify(tester, 'Northern Cardinal');
      expect(
        find.ancestor(
          of: find.text('Try again'),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Done'),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no dead audio control: nothing offers to play a call', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardinal');
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('an unresolved sound keeps its honest message', (tester) async {
      await identify(tester, 'Eurasian Teal');
      expect(find.textContaining("We don't have advice for"), findsOneWidget);
    });
  });

  group('the advice', () {
    testWidgets('Food, Shelter, Water are separate bordered rows with an icon '
        'chip, not inside a tinted card', (tester) async {
      await identify(tester, 'Northern Cardinal');
      for (final label in ['Food', 'Shelter', 'Water']) {
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(InteractiveSurface),
          ),
          findsOneWidget,
          reason: label,
        );
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(InfoSurface),
          ),
          findsNothing,
          reason: '$label must not sit inside a tinted card',
        );
      }
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      expect(find.byIcon(Icons.park_outlined), findsOneWidget);
      expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
    });

    testWidgets('the need rows are not pressable', (tester) async {
      await identify(tester, 'Northern Cardinal');
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Food'),
            matching: find.byType(InteractiveSurface),
          ),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('Simple actions is one tinted card holding the ticks', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardinal');
      final card = find.ancestor(
        of: find.byType(Checkbox).first,
        matching: find.byType(InfoSurface),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(Checkbox)),
        findsAtLeastNWidgets(2),
      );
    });

    testWidgets('"Add N to my plan" is the full-width primary button right '
        'under the Simple actions card', (tester) async {
      await identify(tester, 'Northern Cardinal');
      final add = find.ancestor(
        of: find.textContaining('to my plan'),
        matching: find.byType(PrimaryAction),
      );
      expect(add, findsOneWidget);
      final card = find.ancestor(
        of: find.byType(Checkbox).first,
        matching: find.byType(InfoSurface),
      );
      final gap = tester.getTopLeft(add).dy - tester.getBottomLeft(card).dy;
      expect(gap, inInclusiveRange(0, 40), reason: 'directly under the card');
      final plants = tester
          .getTopLeft(find.textContaining('Native plants for'))
          .dy;
      expect(tester.getTopLeft(add).dy, lessThan(plants));
      expect(tester.getSize(add).width, greaterThan(300));
    });
  });

  group('need icon chips are readable in both themes', () {
    for (final b in Brightness.values) {
      for (final n in Need.values) {
        test('$n, $b', () {
          final (bg, fg) = needChipColors(n, b);
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(3.0));
          final page = b == Brightness.dark
              ? EcoTokens.dark.surfaceRaised
              : EcoTokens.light.surfaceRaised;
          expect(contrastRatio(bg, page), greaterThanOrEqualTo(1.1));
        });
      }
    }
  });

  group('slow identification', () {
    testWidgets('says nothing for a quick answer, and explains the wait once '
        'it passes a few seconds', (tester) async {
      final slow = Completer<IdentificationResult>();
      await pumpApp(tester, fakeEnv(providers: [SlowProvider(slow.future)]));
      await tester.tap(find.text('Birds').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to record'));
      await tester.pump();
      await tester.tap(find.textContaining('Recording'));
      await tester.pump();
      expect(find.text('Identifying…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Still working'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Still working'), findsOneWidget);
      slow.complete(
        IdentificationResult(
          providerId: 'slow',
          providerLabel: 'Slow',
          sentAudioOffDevice: true,
          detections: [Detection(speciesText: 'Northern Cardinal')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Still working'), findsNothing);
    });
  });

  group('quick answer notes', () {
    Future<(Completer<IdentificationResult>, Completer<IdentificationResult>)>
    start(WidgetTester tester) async {
      final nature = Completer<IdentificationResult>();
      final birdnet = Completer<IdentificationResult>();
      await pumpApp(
        tester,
        fakeEnv(
          providers: [_Ctl('naturelm', nature), _Ctl('birdnet', birdnet)],
        ),
      );
      await tester.tap(find.text('Birds').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to record'));
      await tester.pump();
      await tester.tap(find.textContaining('Recording'));
      await tester.pump();
      return (nature, birdnet);
    }

    IdentificationResult named(String id, String label, String species) =>
        IdentificationResult(
          providerId: id,
          providerLabel: label,
          sentAudioOffDevice: true,
          detections: [Detection(speciesText: species)],
        );

    testWidgets('shows the quick answer at once with a "checking" line, then '
        '"Confirmed by NatureLM"', (tester) async {
      final (nature, birdnet) = await start(tester);
      birdnet.complete(named('birdnet', 'BirdNET', 'Northern Cardinal'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Northern Cardinal'), findsWidgets);
      expect(
        find.textContaining('Quick answer. Checking with NatureLM'),
        findsOneWidget,
      );
      nature.complete(named('naturelm', 'NatureLM', 'Northern Cardinal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checking with NatureLM'), findsNothing);
      expect(find.text('Confirmed by NatureLM.'), findsOneWidget);
    });

    testWidgets('says plainly when NatureLM changed the answer', (
      tester,
    ) async {
      final (nature, birdnet) = await start(tester);
      birdnet.complete(named('birdnet', 'BirdNET', 'Northern Cardinal'));
      await tester.pump();
      await tester.pump();
      nature.complete(named('naturelm', 'NatureLM', 'Blue Jay'));
      await tester.pumpAndSettle();
      expect(find.text('Blue Jay'), findsWidgets);
      expect(
        find.text(
          'NatureLM updated this answer. The quick answer had been '
          'Northern Cardinal.',
        ),
        findsOneWidget,
      );
    });
  });
}

class _Ctl implements IdentificationProvider {
  _Ctl(this.id, this.c);
  @override
  final String id;
  final Completer<IdentificationResult> c;
  @override
  String get label => id;
  @override
  bool get sendsAudioOffDevice => true;
  @override
  bool get noDetectionIsFinal => true;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<IdentificationResult> identify(AudioClip clip) => c.future;
}

class SlowProvider implements IdentificationProvider {
  SlowProvider(this.future);
  final Future<IdentificationResult> future;
  @override
  String get id => 'slow';
  @override
  String get label => 'Slow';
  @override
  bool get sendsAudioOffDevice => true;
  @override
  bool get noDetectionIsFinal => true;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<IdentificationResult> identify(AudioClip clip) => future;
}
