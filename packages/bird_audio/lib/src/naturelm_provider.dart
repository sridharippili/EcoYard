import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_support.dart';
import 'identification.dart';
import 'naturelm_parser.dart';

/// NatureLM-audio, reached through the GardenEar router.
///
/// Ported from GardenEar's `NatureLMProvider.swift`. Unlike the Swift, this
/// reports `confidence: null` (the model gives none; GardenEar invented 1.0),
/// keeps multiple time windows separate, and treats an empty answer as
/// "heard nothing" rather than a successful identification of "".
class NatureLmProvider implements IdentificationProvider {
  NatureLmProvider({
    required this.client,
    this.routerBase = 'https://gardenear-router.onrender.com',
    this.query =
        'What is the common name of the bird species in this audio? Answer:',
    this.headers = const {},
  });

  final http.Client client;
  final String routerBase;
  final String query;

  /// Extra headers, e.g. an access token once the router's scheme is known.
  final Map<String, String> headers;

  @override
  String get id => 'naturelm';

  @override
  String get label => 'NatureLM';

  @override
  bool get sendsAudioOffDevice => true;

  @override
  bool get noDetectionIsFinal => true;

  /// The router is up AND at least one backend (the Kaggle notebook) is
  /// registered. `active_providers: []` means "not running".
  @override
  Future<bool> isAvailable() async {
    try {
      final res = await client.get(
        Uri.parse('$routerBase/health'),
        headers: headers,
      );
      if (res.statusCode != 200) return false;
      final json = jsonDecode(res.body);
      if (json is! Map) return false;
      final providers = json['active_providers'];
      return providers is List && providers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    final body = buildAudioMultipart(clip);
    final uri = Uri.parse('$routerBase/identify')
        .replace(queryParameters: {'query': query});

    final http.Response res;
    try {
      res = await client.post(
        uri,
        headers: {...headers, 'Content-Type': body.contentType},
        body: body.bytes,
      );
    } catch (e) {
      throw mapTransportError(e, label);
    }

    if (res.statusCode != 200) throw mapErrorStatus(res.statusCode, label);

    final Object? json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      throw const ProviderException(FailureKind.badResponse,
          'NatureLM sent a response we could not read.');
    }
    if (json is! Map || json['result'] is! String) {
      throw const ProviderException(
          FailureKind.badResponse, 'NatureLM response had no result.');
    }

    final detections = parseNatureLmResult(json['result'] as String);
    if (detections.isEmpty) {
      throw const ProviderException(
          FailureKind.noDetection, 'NatureLM did not hear a bird.');
    }

    return IdentificationResult(
      providerId: id,
      sentAudioOffDevice: true,
      providerLabel: label,
      detections: detections,
      rawResponse: res.body,
    );
  }
}
