import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_support.dart';
import 'identification.dart';

/// BirdNET running on the GardenEar Hugging Face Space (online fallback).
///
/// Ported from GardenEar's `BirdNETProvider.swift`, with one deliberate
/// change: **no latitude/longitude is sent.** GardenEar appended `?lat=&lon=`
/// whenever it had a location; EcoYard does not send location to servers.
class BirdNetOnlineProvider implements IdentificationProvider {
  BirdNetOnlineProvider({
    required this.client,
    this.baseUrl = 'https://ippili7-gardenear-api.hf.space',
    this.headers = const {},
  });

  final http.Client client;
  final String baseUrl;
  final Map<String, String> headers;

  @override
  String get id => 'birdnet';

  @override
  String get label => 'BirdNET';

  @override
  bool get sendsAudioOffDevice => true;

  @override
  bool get noDetectionIsFinal => true;

  /// The Space has no health route (its root answers 404), so "reachable"
  /// means any HTTP answer below 500. A sleeping Space can take ~20 s to wake;
  /// the chain's probe timeout will report that as unreachable, which is
  /// honest: it would not answer a recording quickly either.
  @override
  Future<bool> isAvailable() async {
    try {
      final res = await client.get(Uri.parse(baseUrl), headers: headers);
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    final body = buildAudioMultipart(clip);

    final http.Response res;
    try {
      res = await client.post(
        Uri.parse('$baseUrl/analyze'),
        headers: {...headers, 'Content-Type': body.contentType},
        body: body.bytes,
      );
    } catch (e) {
      throw mapTransportError(e, label);
    }

    if (res.statusCode == 404) {
      // GardenEar's server uses 404 for "no species detected".
      throw const ProviderException(
          FailureKind.noDetection, 'BirdNET did not hear a bird.');
    }
    if (res.statusCode != 200) throw mapErrorStatus(res.statusCode, label);

    final Object? json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      throw const ProviderException(FailureKind.badResponse,
          'BirdNET sent a response we could not read.');
    }
    if (json is! Map) {
      throw const ProviderException(
          FailureKind.badResponse, 'BirdNET response was not an object.');
    }

    final detections = _detections(json);
    if (detections.isEmpty) {
      throw const ProviderException(
          FailureKind.noDetection, 'BirdNET did not hear a bird.');
    }

    return IdentificationResult(
      providerId: id,
      sentAudioOffDevice: true,
      providerLabel: label,
      detections: detections,
      rawResponse: res.body,
    );
  }

  List<Detection> _detections(Map<dynamic, dynamic> json) {
    final out = <Detection>[];
    final seen = <String>{};

    final all = json['all_detections'];
    if (all is List) {
      for (final item in all) {
        if (item is! Map) continue;
        final species = item['species'];
        if (species is! String || species.trim().isEmpty) continue;
        if (!seen.add(species.toLowerCase())) continue;
        out.add(Detection(
          speciesText: species,
          scientificName: _nonEmpty(item['scientific_name']),
          confidence: asDouble(item['confidence']),
        ));
      }
    }
    if (out.isNotEmpty) return out;

    // The server sometimes returns only a top result.
    final top = json['species'] ?? json['label'];
    if (top is String && top.trim().isNotEmpty && top != 'Unknown') {
      out.add(Detection(
        speciesText: top,
        scientificName: _nonEmpty(json['scientific_name']),
        confidence: asDouble(json['confidence'] ?? json['score']),
      ));
    }
    return out;
  }

  String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
}
