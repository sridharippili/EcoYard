import 'dart:convert';

/// One photo we ship, with the licence and author it must be shown with.
class PhotoCredit {
  const PhotoCredit({
    required this.id,
    required this.kind,
    required this.asset,
    required this.author,
    required this.licence,
    required this.licenceUrl,
    required this.sourceUrl,
    this.width,
    this.height,
  });

  /// The bird or plant id this photo belongs to.
  final String id;

  /// `bird` or `plant`.
  final String kind;

  /// Asset path inside the app, e.g. `assets/photos/bird-norcar.jpg`.
  final String asset;

  final String author;
  final String licence;
  final String licenceUrl;

  /// The Wikimedia page the photo came from.
  final String sourceUrl;

  /// Pixel size of the shipped file, when known.
  final int? width;
  final int? height;

  /// Width divided by height, or null when the size is unknown.
  double? get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  bool get isBird => kind == 'bird';
}

/// The photos we ship, looked up by species. Parsed from
/// `content/photo_credits.json`, so the credits can never drift from the
/// files: a photo with no credit is not shown.
class PhotoCredits {
  PhotoCredits(List<PhotoCredit> all)
      : _byKey = {for (final p in all) '${p.kind}:${p.id}': p},
        all = List.unmodifiable(all);

  factory PhotoCredits.fromJson(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('photo_credits.json must be an object');
    }
    final list = root['photos'];
    if (list is! List) {
      throw const FormatException('photo_credits.json needs a "photos" list');
    }
    return PhotoCredits([
      for (final row in list)
        if (row is Map<String, dynamic>)
          PhotoCredit(
            id: _text(row, 'id'),
            kind: _text(row, 'kind'),
            asset: _text(row, 'asset'),
            author: _text(row, 'author'),
            licence: _text(row, 'licence'),
            licenceUrl: row['licenceUrl'] as String? ?? '',
            sourceUrl: row['sourceUrl'] as String? ?? '',
            width: (row['width'] as num?)?.toInt(),
            height: (row['height'] as num?)?.toInt(),
          ),
    ]);
  }

  /// No photos at all: the screens then show their placeholder.
  factory PhotoCredits.empty() => PhotoCredits(const []);

  final Map<String, PhotoCredit> _byKey;
  final List<PhotoCredit> all;

  PhotoCredit? forBird(String birdId) => _byKey['bird:$birdId'];
  PhotoCredit? forPlant(String plantId) => _byKey['plant:$plantId'];

  bool get isEmpty => all.isEmpty;

  static String _text(Map<String, dynamic> row, String key) {
    final v = row[key];
    if (v is! String || v.trim().isEmpty) {
      throw FormatException('photo_credits.json: "$key" must be text');
    }
    return v;
  }
}
