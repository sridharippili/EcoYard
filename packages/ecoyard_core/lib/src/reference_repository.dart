/// Loads and queries the bundled content. Takes JSON text in; does no file
/// or asset I/O, so the same code runs in the app, in tests and in scripts.
library;

import 'dart:convert';

import 'models.dart';

/// The raw text of each bundled content file.
class ContentFiles {
  const ContentFiles({
    required this.birds,
    required this.plants,
    required this.birdPlant,
    required this.actions,
    required this.tips,
    required this.aliases,
  });

  final String birds;
  final String plants;
  final String birdPlant;
  final String actions;
  final String tips;
  final String aliases;
}

/// Per-file header fields.
class FileMeta {
  const FileMeta({
    required this.file,
    required this.schemaVersion,
    required this.reviewStatus,
    required this.region,
    this.reviewedBy,
    this.reviewedOn,
  });

  final String file;
  final int schemaVersion;
  final ReviewStatus reviewStatus;
  final String region;

  /// Who checked the content, and when (YYYY-MM-DD). Required once the status
  /// is `reviewed`, so nobody can flip the flag without leaving a name.
  final String? reviewedBy;
  final String? reviewedOn;
}

class ReferenceRepository {
  ReferenceRepository._({
    required this.birds,
    required this.plants,
    required this.links,
    required this.actions,
    required this.tips,
    required this.aliases,
    required this.meta,
  })  : _birdsById = {for (final b in birds) b.id: b},
        _plantsById = {for (final p in plants) p.id: p},
        _actionsById = {for (final a in actions) a.id: a};

  /// The schema version this code understands, for every file.
  static const int supportedSchemaVersion = 1;

  /// Parses all six files. Throws [ContentFormatException] on the first
  /// malformed file or unsupported `schemaVersion`.
  factory ReferenceRepository.fromJson(ContentFiles f) {
    final birdsRoot = _root('birds.json', f.birds);
    final plantsRoot = _root('plants.json', f.plants);
    final linksRoot = _root('bird_plant.json', f.birdPlant);
    final actionsRoot = _root('actions.json', f.actions);
    final tipsRoot = _root('tips.json', f.tips);
    final aliasRoot = _root('taxonomy_aliases.json', f.aliases);

    return ReferenceRepository._(
      birds: _list('birds.json', birdsRoot, 'birds', _bird),
      plants: _list('plants.json', plantsRoot, 'plants', _plant),
      links: _list('bird_plant.json', linksRoot, 'links', _link),
      actions: _list('actions.json', actionsRoot, 'actions', _action),
      tips: _list('tips.json', tipsRoot, 'tips', _tip),
      aliases: _aliasTable('taxonomy_aliases.json', aliasRoot),
      meta: {
        'birds.json': _meta('birds.json', birdsRoot),
        'plants.json': _meta('plants.json', plantsRoot),
        'bird_plant.json': _meta('bird_plant.json', linksRoot),
        'actions.json': _meta('actions.json', actionsRoot),
        'tips.json': _meta('tips.json', tipsRoot),
        'taxonomy_aliases.json': _meta('taxonomy_aliases.json', aliasRoot),
      },
    );
  }

  final List<Bird> birds;
  final List<Plant> plants;
  final List<BirdPlantLink> links;
  final List<HabitatAction> actions;
  final List<Tip> tips;
  final AliasTable aliases;
  final Map<String, FileMeta> meta;

  final Map<String, Bird> _birdsById;
  final Map<String, Plant> _plantsById;
  final Map<String, HabitatAction> _actionsById;

  /// The region every file covers (the validator checks they agree).
  String get region => meta['birds.json']!.region;

  Bird? birdById(String id) => _birdsById[id];
  Plant? plantById(String id) => _plantsById[id];
  HabitatAction? actionById(String id) => _actionsById[id];

  /// Links for a bird, strongest first (then by plant id, for a stable order).
  List<BirdPlantLink> linksForBird(String birdId) =>
      links.where((l) => l.birdId == birdId).toList()
        ..sort((a, b) {
          final w = b.weight.compareTo(a.weight);
          return w != 0 ? w : a.plantId.compareTo(b.plantId);
        });

  /// Links for a plant, strongest first.
  List<BirdPlantLink> linksForPlant(String plantId) =>
      links.where((l) => l.plantId == plantId).toList()
        ..sort((a, b) {
          final w = b.weight.compareTo(a.weight);
          return w != 0 ? w : a.birdId.compareTo(b.birdId);
        });

  /// The tip for [month] (1-12), or null when none is written.
  Tip? tipForMonth(int month) {
    for (final t in tips) {
      if (t.months.contains(month)) return t;
    }
    return null;
  }

  /// `draft` if any file is still a draft, otherwise `reviewed`.
  ReviewStatus get reviewStatus => meta.values.any(
        (m) => m.reviewStatus == ReviewStatus.draft,
      )
          ? ReviewStatus.draft
          : ReviewStatus.reviewed;
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _root(String file, String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw ContentFormatException(file, 'not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ContentFormatException(file, 'top level must be an object');
  }
  final v = decoded['schemaVersion'];
  if (v != ReferenceRepository.supportedSchemaVersion) {
    throw ContentFormatException(
      file,
      'schemaVersion is $v, this app understands '
      '${ReferenceRepository.supportedSchemaVersion}',
    );
  }
  return decoded;
}

FileMeta _meta(String file, Map<String, dynamic> root) => FileMeta(
      file: file,
      schemaVersion: root['schemaVersion'] as int,
      reviewStatus: _enum(ReviewStatus.values, (e) => e.json,
          root['reviewStatus'], file, 'reviewStatus'),
      region: _string(root, 'region', file, 'file'),
      reviewedBy: _optString(root, 'reviewedBy'),
      reviewedOn: _optString(root, 'reviewedOn'),
    );

List<T> _list<T>(
  String file,
  Map<String, dynamic> root,
  String key,
  T Function(String file, Map<String, dynamic> row) parse,
) {
  final raw = root[key];
  if (raw is! List) {
    throw ContentFormatException(file, '"$key" must be a list');
  }
  final out = <T>[];
  for (var i = 0; i < raw.length; i++) {
    final row = raw[i];
    if (row is! Map<String, dynamic>) {
      throw ContentFormatException(file, '$key[$i] must be an object');
    }
    out.add(parse(file, row));
  }
  return out;
}

String _string(Map<String, dynamic> m, String key, String file, String where) {
  final v = m[key];
  if (v is! String || v.trim().isEmpty) {
    throw ContentFormatException(file, '$where: "$key" must be non-empty text');
  }
  return v;
}

String? _optString(Map<String, dynamic> m, String key) {
  final v = m[key];
  return v is String && v.trim().isNotEmpty ? v : null;
}

int _int(Map<String, dynamic> m, String key, String file, String where) {
  final v = m[key];
  if (v is! int) {
    throw ContentFormatException(file, '$where: "$key" must be a whole number');
  }
  return v;
}

List<String> _strings(
    Map<String, dynamic> m, String key, String file, String where) {
  final v = m[key];
  if (v is! List || v.any((e) => e is! String)) {
    throw ContentFormatException(file, '$where: "$key" must be a list of text');
  }
  return v.cast<String>();
}

List<int> _ints(Map<String, dynamic> m, String key, String file, String where) {
  final v = m[key];
  if (v is! List || v.any((e) => e is! int)) {
    throw ContentFormatException(
        file, '$where: "$key" must be a list of whole numbers');
  }
  return v.cast<int>();
}

T _enum<T>(List<T> values, String Function(T) json, Object? v, String file,
    String where) {
  for (final e in values) {
    if (json(e) == v) return e;
  }
  throw ContentFormatException(
    file,
    '$where: "$v" is not one of ${values.map(json).join(', ')}',
  );
}

List<T> _enumList<T>(List<T> values, String Function(T) json,
    Map<String, dynamic> m, String key, String file, String where) {
  final raw = m[key];
  if (raw is! List) {
    throw ContentFormatException(file, '$where: "$key" must be a list');
  }
  return [for (final e in raw) _enum(values, json, e, file, '$where.$key')];
}

Bird _bird(String file, Map<String, dynamic> m) {
  final id = _string(m, 'id', file, 'bird');
  final needs = m['supportNeeds'];
  if (needs is! List) {
    throw ContentFormatException(file, '$id: "supportNeeds" must be a list');
  }
  return Bird(
    id: id,
    scientificName: _string(m, 'scientificName', file, id),
    commonName: _string(m, 'commonName', file, id),
    supportNeeds: [
      for (final n in needs)
        if (n is Map<String, dynamic>)
          SupportNeed(
            need:
                _enum(Need.values, (e) => e.json, n['need'], file, '$id.need'),
            why: _string(n, 'why', file, id),
          )
        else
          throw ContentFormatException(file, '$id: bad supportNeeds entry'),
    ],
  );
}

Plant _plant(String file, Map<String, dynamic> m) {
  final id = _string(m, 'id', file, 'plant');
  final photoRaw = m['photo'];
  if (photoRaw is! Map<String, dynamic>) {
    throw ContentFormatException(file, '$id: "photo" must be an object');
  }
  final bloom = m['bloom'];
  if (bloom is! Map<String, dynamic>) {
    throw ContentFormatException(file, '$id: "bloom" must be an object');
  }
  final height = _ints(m, 'heightFt', file, id);
  if (height.length != 2) {
    throw ContentFormatException(file, '$id: "heightFt" must be [min, max]');
  }
  return Plant(
    id: id,
    commonName: _string(m, 'commonName', file, id),
    scientificName: _string(m, 'scientificName', file, id),
    plantType: _enum(
        PlantType.values, (e) => e.json, m['plantType'], file, '$id.plantType'),
    nativity: _enum(
        Nativity.values, (e) => e.json, m['nativity'], file, '$id.nativity'),
    sun: _enumList(SunExposure.values, (e) => e.json, m, 'sun', file, id),
    water:
        _enum(WaterNeed.values, (e) => e.json, m['water'], file, '$id.water'),
    heightFtMin: height[0],
    heightFtMax: height[1],
    bloomStartMonth: _int(bloom, 'startMonth', file, '$id.bloom'),
    bloomEndMonth: _int(bloom, 'endMonth', file, '$id.bloom'),
    benefits:
        _enumList(PlantBenefit.values, (e) => e.json, m, 'benefits', file, id),
    spaces: _enumList(SpaceType.values, (e) => e.json, m, 'spaces', file, id),
    costTier: _enum(
        CostTier.values, (e) => e.json, m['costTier'], file, '$id.costTier'),
    photo: PlantPhoto(
      status: _enum(PhotoStatus.values, (e) => e.json, photoRaw['status'], file,
          '$id.photo.status'),
      asset: _optString(photoRaw, 'asset'),
      attribution: _optString(photoRaw, 'attribution'),
    ),
    note: _optString(m, 'note'),
  );
}

BirdPlantLink _link(String file, Map<String, dynamic> m) {
  final where = '${m['birdId']}/${m['plantId']}';
  return BirdPlantLink(
    birdId: _string(m, 'birdId', file, where),
    plantId: _string(m, 'plantId', file, where),
    weight: _int(m, 'weight', file, where),
    needs: _enumList(Need.values, (e) => e.json, m, 'needs', file, where),
    reason: _string(m, 'reason', file, where),
  );
}

HabitatAction _action(String file, Map<String, dynamic> m) {
  final id = _string(m, 'id', file, 'action');
  return HabitatAction(
    id: id,
    title: _string(m, 'title', file, id),
    body: _string(m, 'body', file, id),
    costTier: _enum(
        CostTier.values, (e) => e.json, m['costTier'], file, '$id.costTier'),
    months: _ints(m, 'months', file, id),
    spaces: _enumList(SpaceType.values, (e) => e.json, m, 'spaces', file, id),
    needs: _enumList(Need.values, (e) => e.json, m, 'needs', file, id),
    relatedPlantIds: _strings(m, 'relatedPlantIds', file, id),
    priority: _int(m, 'priority', file, id),
    forBirdIds: m.containsKey('forBirdIds')
        ? _strings(m, 'forBirdIds', file, id)
        : const [],
    featuredForBirdIds: m.containsKey('featuredForBirdIds')
        ? _strings(m, 'featuredForBirdIds', file, id)
        : const [],
  );
}

Tip _tip(String file, Map<String, dynamic> m) {
  final id = _string(m, 'id', file, 'tip');
  return Tip(
    id: id,
    months: _ints(m, 'months', file, id),
    text: _string(m, 'text', file, id),
    relatedActionIds: _strings(m, 'relatedActionIds', file, id),
  );
}

AliasTable _aliasTable(String file, Map<String, dynamic> root) {
  final raw = root['aliases'];
  if (raw is! List) {
    throw ContentFormatException(file, '"aliases" must be a list');
  }
  final aliases = <String, List<String>>{};
  for (final row in raw) {
    if (row is! Map<String, dynamic>) {
      throw ContentFormatException(file, 'alias entries must be objects');
    }
    final id = _string(row, 'taxonId', file, 'alias');
    aliases.putIfAbsent(id, () => []).addAll(_strings(row, 'names', file, id));
  }
  return AliasTable(
    aliases: aliases,
    notABird: _strings(root, 'notABird', file, 'file'),
    noSpeciesPhrases: _strings(root, 'noSpeciesPhrases', file, 'file'),
  );
}
