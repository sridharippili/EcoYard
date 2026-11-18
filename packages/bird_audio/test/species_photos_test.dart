import 'dart:convert';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String lead(String? image,
        {bool disambiguation = false, bool missing = false}) =>
    jsonEncode({
      'query': {
        'pages': [
          {
            'title': 'X',
            if (missing) 'missing': true,
            if (image != null) 'pageimage': image,
            if (disambiguation) 'pageprops': {'disambiguation': ''},
          },
        ],
      },
    });

String commons({
  String licence = 'CC BY-SA 4.0',
  String artist = '<a href="u">Jane Doe</a>',
  String mime = 'image/jpeg',
  String thumb = 'https://upload.wikimedia.org/x/900px-Bird.jpg',
  bool noInfo = false,
}) =>
    jsonEncode({
      'query': {
        'pages': [
          {
            if (!noInfo)
              'imageinfo': [
                {
                  'thumburl': thumb,
                  'mime': mime,
                  'descriptionurl':
                      'https://commons.wikimedia.org/wiki/File:Bird.jpg',
                  'extmetadata': {
                    'LicenseShortName': {'value': licence},
                    'LicenseUrl': {'value': 'https://creativecommons.org/x'},
                    'Artist': {'value': artist},
                  },
                },
              ],
          },
        ],
      },
    });

void main() {
  group('licences', () {
    test('allowed: public domain, CC0, CC BY, CC BY-SA', () {
      for (final l in [
        'CC BY 2.0',
        'CC BY-SA 4.0',
        'CC BY-SA 3.0',
        'CC0',
        'CC0 1.0',
        'Public domain',
        'Public domain (US)',
        'PD',
      ]) {
        expect(licenceAllowed(l), isTrue, reason: l);
      }
    });
    test('refused: non-commercial, no-derivatives, unknown, empty', () {
      for (final l in [
        'CC BY-NC 4.0',
        'CC BY-NC-SA 3.0',
        'CC BY-ND 2.0',
        'CC BY-NC-ND 4.0',
        'All rights reserved',
        'Fair use',
        'GFDL',
        '',
        '   ',
      ]) {
        expect(licenceAllowed(l), isFalse, reason: l);
      }
    });
  });

  group('parsing', () {
    test('lead image: a normal article', () {
      expect(parseLeadImage(lead('Bird.jpg')), 'Bird.jpg');
    });
    test(
        'lead image: none for a missing page, a disambiguation page, no '
        'image or junk', () {
      expect(parseLeadImage(lead(null)), isNull);
      expect(parseLeadImage(lead('Bird.jpg', missing: true)), isNull);
      expect(parseLeadImage(lead('Bird.jpg', disambiguation: true)), isNull);
      expect(parseLeadImage('{}'), isNull);
      expect(parseLeadImage('[]'), isNull);
    });
    test('commons: credit text, HTML stripped, https thumbnail', () {
      final p = parseCommonsPhoto(commons())!;
      expect(p.author, 'Jane Doe');
      expect(p.licence, 'CC BY-SA 4.0');
      expect(p.imageUrl.startsWith('https://'), isTrue);
      expect(
          p.creditLine, 'Photo: Jane Doe · CC BY-SA 4.0 · Wikimedia Commons');
    });
    test(
        'commons: refuses a bad licence, a non-photo type, an http link, '
        'a missing file', () {
      expect(parseCommonsPhoto(commons(licence: 'CC BY-NC 4.0')), isNull);
      expect(parseCommonsPhoto(commons(mime: 'image/svg+xml')), isNull);
      expect(parseCommonsPhoto(commons(mime: 'image/gif')), isNull);
      expect(parseCommonsPhoto(commons(thumb: 'http://x/y.jpg')), isNull);
      expect(parseCommonsPhoto(commons(noInfo: true)), isNull);
    });
    test('a very long author is cut', () {
      final p = parseCommonsPhoto(commons(artist: 'A' * 200))!;
      expect(p.author.length, lessThanOrEqualTo(70));
    });
    test('titles: trimmed, one line, no markup, not huge', () {
      expect(cleanTitle('  Northern   Cardinal '), 'Northern Cardinal');
      expect(cleanTitle(''), isNull);
      expect(cleanTitle('<b>x</b>'), isNull);
      expect(cleanTitle('A' * 81), isNull);
    });
  });

  group('WikimediaPhotos', () {
    late List<Uri> calls;
    late Map<String, String> headersSeen;

    WikimediaPhotos make(
      http.Response Function(Uri) answer, {
      Duration timeout = const Duration(seconds: 2),
    }) {
      calls = [];
      headersSeen = {};
      return WikimediaPhotos(
        timeout: timeout,
        client: MockClient((req) async {
          calls.add(req.url);
          headersSeen = req.headers;
          return answer(req.url);
        }),
      );
    }

    http.Response ok(Uri u, {String file = 'Bird.jpg', String? lic}) {
      if (u.host.contains('wikipedia')) return http.Response(lead(file), 200);
      return http.Response(commons(licence: lic ?? 'CC BY 4.0'), 200);
    }

    test('finds a photo and sends only the species name', () async {
      final s = make(ok);
      final p =
          await s.find(name: 'Mallard', scientificName: 'Anas platyrhynchos');
      expect(p, isNotNull);
      expect(calls.first.queryParameters['titles'], 'Anas platyrhynchos');
      for (final u in calls) {
        final all = u.toString().toLowerCase();
        expect(all.contains('latitude'), isFalse);
        expect(all.contains('longitude'), isFalse);
        expect(all.contains('audio'), isFalse);
        expect(u.scheme, 'https');
      }
      expect(headersSeen['User-Agent'], contains('EcoYard'));
    });

    test(
        'falls back to the common name when the scientific one has no '
        'usable photo', () async {
      final s = make((u) {
        if (u.host.contains('wikipedia')) {
          return http.Response(
            lead(u.queryParameters['titles'] == 'Mallard' ? 'M.jpg' : null),
            200,
          );
        }
        return http.Response(commons(), 200);
      });
      final p = await s.find(name: 'Mallard', scientificName: 'Anas x');
      expect(p, isNotNull);
      expect(
        calls
            .where((u) => u.host.contains('wikipedia'))
            .map((u) => u.queryParameters['titles']),
        ['Anas x', 'Mallard'],
      );
    });

    test('a refused licence means no photo, and it is not asked again',
        () async {
      final s = make((u) => ok(u, lic: 'CC BY-NC 4.0'));
      expect(await s.find(name: 'Mallard'), isNull);
      final n = calls.length;
      expect(await s.find(name: 'Mallard'), isNull);
      expect(calls.length, n);
    });

    test('a found photo is remembered: one request set for repeated asks',
        () async {
      final s = make(ok);
      await s.find(name: 'Mallard');
      final n = calls.length;
      await s.find(name: 'mallard');
      expect(calls.length, n);
    });

    test('two asks at the same time send one set of requests', () async {
      final s = make(ok);
      final a = s.find(name: 'Mallard');
      final b = s.find(name: 'Mallard');
      await Future.wait([a, b]);
      expect(calls.length, 2, reason: 'one Wikipedia and one Commons call');
    });

    test('a failure never throws, is not cached, and the next ask retries',
        () async {
      var fail = true;
      final s = make((u) {
        if (fail) return http.Response('nope', 503);
        return ok(u);
      });
      expect(await s.find(name: 'Mallard'), isNull);
      fail = false;
      expect(await s.find(name: 'Mallard'), isNotNull);
    });

    test('a connection error never throws', () async {
      final s = WikimediaPhotos(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await s.find(name: 'Mallard'), isNull);
    });

    test('a slow server is given up on', () async {
      final s = WikimediaPhotos(
        timeout: const Duration(milliseconds: 50),
        client: MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return http.Response(lead('B.jpg'), 200);
        }),
      );
      expect(await s.find(name: 'Mallard'), isNull);
    });

    test('a blank or absurd name makes no request at all', () async {
      final s = make(ok);
      expect(await s.find(name: '   '), isNull);
      expect(await s.find(name: 'x' * 200), isNull);
      expect(calls, isEmpty);
    });

    test('NoSpeciesPhotos finds nothing', () async {
      expect(await const NoSpeciesPhotos().find(name: 'Mallard'), isNull);
    });
  });
}
