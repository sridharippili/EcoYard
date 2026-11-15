/// EcoYard's pure-Dart core: content models, the species resolver and the
/// content validator.
///
/// Must stay free of Flutter, plugins and `dart:io` in `lib/`; the pre-commit
/// hook enforces that. Files in `lib/src` import each other by relative path
/// only, so plain scripts (`scripts/validate_content.dart`) can use them.
library;

export 'src/content_validator.dart';
export 'src/habitat_engine.dart';
export 'src/models.dart';
export 'src/normalize.dart' show normalizeName;
export 'src/plan.dart';
export 'src/reference_repository.dart';
export 'src/species_resolver.dart';
