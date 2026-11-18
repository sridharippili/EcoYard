import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A photo of a species taken from Wikimedia Commons, with the credit its
/// licence requires.
class RemotePhoto {
  const RemotePhoto({
    required this.imageUrl,
    required this.author,
    required this.licence,
    required this.pageUrl,
    this.licenceUrl = '',
  });

  /// A ~900 px version on upload.wikimedia.org.
  final String imageUrl;
  final String author;

  /// e.g. "CC BY-SA 4.0".
  final String licence;
  final String licenceUrl;

  /// The Commons page for the file.
  final String pageUrl;

  /// The line shown under the photo.
  String get creditLine {
    final who = author.isEmpty ? 'Unknown author' : author;
    return 'Photo: $who · $licence · Wikimedia Commons';
  }
}

/// Finds a photo for a species by name. An interface, so screens and tests
/// never touch the network.
abstract interface class SpeciesPhotoLookup {
  /// A credited photo, or null when there is none (or no connection).
  /// Never throws.
  Future<RemotePhoto?> find({required String name, String? scientificName});
}

/// Looks nothing up. Used when photos are switched off.
class NoSpeciesPhotos implements SpeciesPhotoLookup {
  const NoSpeciesPhotos();
  @override
  Future<RemotePhoto?> find(
          {required String name, String? scientificName}) async =>
      null;
}

/// The Wikipedia lead image of the species' article, with its licence and
/// author from Commons.
///
/// What leaves the phone: the species name (never the recording, the
/// location or anything about the user), in a request that Wikimedia sees
/// with the phone's network address like any other web request.
///
/// Only public domain, CC0, CC BY and CC BY-SA images are used. Anything else,
/// anything without a clear licence, and anything that is not a JPEG or PNG
/// photo is skipped, and the screen shows its silhouette instead.
class WikimediaPhotos implements SpeciesPhotoLookup {
  WikimediaPhotos({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.wikipedia = 'https://en.wikipedia.org/w/api.php',
    this.commons = 'https://commons.wikimedia.org/w/api.php',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final String wikipedia;
  final String commons;

  static const _headers = {
    'User-Agent': 'EcoYard/0.1 (bird habitat app; Wikimedia API)',
    'Accept': 'application/json',
  };

  /// Answers already known this session (including "there is none").
  final Map<String, RemotePhoto?> _known = {};

  /// Requests already running, so two screens asking at once send one.
  final Map<String, Future<RemotePhoto?>> _running = {};

  @override
  Future<RemotePhoto?> find({
    required String name,
    String? scientificName,
  }) {
    final names = [
      if (scientificName != null && cleanTitle(scientificName) != null)
        cleanTitle(scientificName)!,
      if (cleanTitle(name) != null) cleanTitle(name)!,
    ];
    if (names.isEmpty) return Future.value(null);
    final key = names.first.toLowerCase();
    if (_known.containsKey(key)) return Future.value(_known[key]);
    return _running[key] ??= _lookup(names, key).whenComplete(() {
      // A block body: returning the removed future would make this wait on
      // itself for ever.
      _running.remove(key);
    });
  }

  Future<RemotePhoto?> _lookup(List<String> names, String key) async {
    try {
      for (final title in names) {
        final file = await _leadImage(title);
        if (file == null) continue;
        final photo = await _commonsPhoto(file);
        if (photo != null) {
          _known[key] = photo;
          return photo;
        }
      }
      // A definite "no usable photo": do not ask again this session.
      _known[key] = null;
      return null;
    } catch (_) {
      // No connection, a timeout or an odd answer: show the silhouette and
      // let the next result try again.
      return null;
    }
  }

  Future<String?> _leadImage(String title) async {
    final uri = Uri.parse(wikipedia).replace(
      queryParameters: {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'prop': 'pageimages|pageprops',
        'piprop': 'name',
        'ppprop': 'disambiguation',
        'titles': title,
        'redirects': '1',
      },
    );
    final res = await _client.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode != 200) throw StateError('wikipedia ${res.statusCode}');
    return parseLeadImage(res.body);
  }

  Future<RemotePhoto?> _commonsPhoto(String file) async {
    final uri = Uri.parse(commons).replace(
      queryParameters: {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata|mime',
        'iiurlwidth': '900',
        'titles': 'File:$file',
      },
    );
    final res = await _client.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode != 200) throw StateError('commons ${res.statusCode}');
    return parseCommonsPhoto(res.body);
  }
}

/// A search title that is safe to send: trimmed, one line, not absurdly long.
/// Null when nothing usable is left.
String? cleanTitle(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t.length > 80) return null;
  if (RegExp(r'[<>{}\[\]|#]').hasMatch(t)) return null;
  return t;
}

/// The lead image file name from a Wikipedia `pageimages` answer, or null
/// (no article, no image, or a disambiguation page).
String? parseLeadImage(String body) {
  final data = jsonDecode(body);
  if (data is! Map) return null;
  final pages = (data['query'] as Map?)?['pages'];
  if (pages is! List || pages.isEmpty) return null;
  final page = pages.first;
  if (page is! Map || page['missing'] == true) return null;
  final props = page['pageprops'];
  if (props is Map && props.containsKey('disambiguation')) return null;
  final image = page['pageimage'];
  return image is String && image.isNotEmpty ? image : null;
}

/// A credited photo from a Commons `imageinfo` answer, or null when the file
/// is not an allowed photo.
RemotePhoto? parseCommonsPhoto(String body) {
  final data = jsonDecode(body);
  if (data is! Map) return null;
  final pages = (data['query'] as Map?)?['pages'];
  if (pages is! List || pages.isEmpty) return null;
  final page = pages.first;
  if (page is! Map) return null;
  final infos = page['imageinfo'];
  if (infos is! List || infos.isEmpty || infos.first is! Map) return null;
  final info = infos.first as Map;
  final mime = '${info['mime'] ?? ''}';
  if (mime != 'image/jpeg' && mime != 'image/png') return null;
  final thumb = info['thumburl'];
  if (thumb is! String || !thumb.startsWith('https://')) return null;
  final meta = info['extmetadata'];
  String field(String key) {
    if (meta is! Map) return '';
    final v = meta[key];
    return v is Map ? stripHtml('${v['value'] ?? ''}') : '';
  }

  final licence = field('LicenseShortName');
  if (!licenceAllowed(licence)) return null;
  var author = field('Artist');
  if (author.length > 70) author = '${author.substring(0, 67)}…';
  return RemotePhoto(
    imageUrl: thumb,
    author: author,
    licence: licence,
    licenceUrl: field('LicenseUrl'),
    pageUrl: '${info['descriptionurl'] ?? ''}',
  );
}

/// Public domain, CC0, CC BY and CC BY-SA only. Non-commercial, no-derivatives
/// and anything we cannot recognise are refused.
bool licenceAllowed(String licence) {
  final low = licence.toLowerCase().trim();
  if (low.isEmpty) return false;
  final words = low.split(RegExp(r'[\s-]+'));
  if (words.contains('nc') ||
      words.contains('nd') ||
      low.contains('non-commercial')) {
    return false;
  }
  return low == 'cc0' ||
      low.startsWith('cc0 ') ||
      low.startsWith('public domain') ||
      low == 'pd' ||
      low.startsWith('pd ') ||
      low.startsWith('cc by') ||
      low.startsWith('cc-by');
}

/// The visible text of an HTML fragment (Commons returns HTML in `Artist`).
String stripHtml(String html) {
  final noTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return noTags
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
