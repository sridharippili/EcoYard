import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'identification.dart';

/// A multipart/form-data request body, built by hand so the exact bytes and
/// headers can be tested without a network.
class MultipartBody {
  const MultipartBody(this.bytes, this.contentType);

  final Uint8List bytes;

  /// Value for the `Content-Type` header, including the boundary.
  final String contentType;
}

/// Packs [clip] as the single form field [field] (the services expect `audio`).
MultipartBody buildAudioMultipart(
  AudioClip clip, {
  String field = 'audio',
  String? boundary,
}) {
  final b = boundary ?? 'ecoyard-${DateTime.now().microsecondsSinceEpoch}';
  final safeName = clip.fileName.replaceAll(RegExp(r'["\r\n]'), '_');

  final out = BytesBuilder(copy: false)
    ..add(utf8.encode('--$b\r\n'
        'Content-Disposition: form-data; name="$field"; filename="$safeName"\r\n'
        'Content-Type: ${clip.mimeType}\r\n\r\n'))
    ..add(clip.bytes)
    ..add(utf8.encode('\r\n--$b--\r\n'));

  return MultipartBody(out.toBytes(), 'multipart/form-data; boundary=$b');
}

/// Turns a transport-level error into a [ProviderException].
ProviderException mapTransportError(Object error, String label) {
  if (error is ProviderException) return error;
  if (error is TimeoutException) {
    return ProviderException(FailureKind.timeout, '$label timed out.');
  }
  if (error is SocketException || error is http.ClientException) {
    return ProviderException(
        FailureKind.unavailable, 'Could not reach $label.');
  }
  return ProviderException(
      FailureKind.badResponse, '$label failed unexpectedly.');
}

/// Maps an HTTP error status to a failure. 502/503/504 mean the service (or
/// the notebook behind it) is down, which is "not responsive" and falls
/// through; anything else is the service rejecting the request.
ProviderException mapErrorStatus(int status, String label) {
  if (status == 502 || status == 503 || status == 504) {
    return ProviderException(
        FailureKind.unavailable, '$label is not available (HTTP $status).');
  }
  return ProviderException(
      FailureKind.rejected, '$label returned an error (HTTP $status).');
}

double? asDouble(Object? v) => v is num ? v.toDouble() : null;
