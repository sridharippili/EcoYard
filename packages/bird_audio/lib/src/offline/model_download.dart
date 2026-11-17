import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// One file the offline model needs: where to get it and exactly what it must
/// be. Values come from `content/offline_model.json`, never from Dart.
class ModelFileSpec {
  const ModelFileSpec({
    required this.name,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  /// File name on disk. Includes the model version, so an app build never
  /// trusts a replaced older file.
  final String name;
  final String url;
  final int bytes;

  /// 64 hex characters.
  final String sha256;
}

/// Why a download did not finish.
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => 'ModelDownloadException: $message';
}

/// The download was cancelled; nothing is left on disk.
class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
}

/// Lets the caller stop a running download.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef ProgressCallback = void Function(int received, int? total);

/// Stores the offline model files in one folder and downloads them safely.
///
/// - Streams to `<name>.part`, never holding the file in memory.
/// - https only, including after redirects.
/// - Verifies size and SHA-256 once, then renames atomically. Later launches
///   check size only ([isReady]).
/// - A failed, cancelled or interrupted download never leaves a usable file:
///   only the final, verified name is ever treated as the model.
class ModelStore {
  ModelStore({required this.dir, http.Client? client})
      : _client = client ?? http.Client();

  final Directory dir;
  final http.Client _client;

  static const String partSuffix = '.part';

  File fileFor(ModelFileSpec spec) => File('${dir.path}/${spec.name}');
  File _part(ModelFileSpec spec) => File('${dir.path}/${spec.name}$partSuffix');

  /// True when every file exists with exactly the expected size.
  Future<bool> isReady(List<ModelFileSpec> specs) async {
    try {
      for (final s in specs) {
        final f = fileFor(s);
        if (!await f.exists() || await f.length() != s.bytes) return false;
      }
      return specs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Downloads one file. Throws [ModelDownloadException] on any failure and
  /// [ModelDownloadCancelled] on cancel; both leave no `.part` behind.
  Future<void> download(
    ModelFileSpec spec, {
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final uri = Uri.tryParse(spec.url);
    if (uri == null || uri.scheme != 'https') {
      throw const ModelDownloadException('The download address is not https');
    }
    await dir.create(recursive: true);
    final part = _part(spec);
    if (await part.exists()) await part.delete();

    IOSink? sink;
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5;
      final http.StreamedResponse response;
      try {
        response = await _client.send(request);
      } on SocketException {
        throw const ModelDownloadException('No internet connection');
      } on http.ClientException catch (e) {
        throw ModelDownloadException('Could not connect: ${e.message}');
      }
      if (response.statusCode != 200) {
        throw ModelDownloadException(
          'The server answered ${response.statusCode}',
        );
      }
      final finalUrl = response.request?.url;
      if (finalUrl != null && finalUrl.scheme != 'https') {
        throw const ModelDownloadException('The download was redirected away '
            'from https');
      }
      // When the server compresses the transfer, Content-Length is the
      // compressed size while the client hands us the decompressed bytes, so
      // it says nothing about the file. The byte count and checksum still do.
      final encoding = response.headers['content-encoding']?.toLowerCase();
      final compressed = encoding != null && encoding != 'identity';
      final length = compressed ? null : response.contentLength;
      if (length != null && length != spec.bytes) {
        throw ModelDownloadException(
          'The file is $length bytes, expected ${spec.bytes}',
        );
      }

      sink = part.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      onProgress?.call(0, length ?? spec.bytes);
      await for (final chunk in response.stream) {
        if (cancel?.isCancelled ?? false) throw const ModelDownloadCancelled();
        received += chunk.length;
        if (received > spec.bytes) {
          throw ModelDownloadException(
            'The download is larger than the expected ${spec.bytes} bytes',
          );
        }
        sink.add(chunk);
        hasher.add(chunk);
        onProgress?.call(received, length ?? spec.bytes);
      }
      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;

      if (cancel?.isCancelled ?? false) throw const ModelDownloadCancelled();
      if (received != spec.bytes) {
        throw ModelDownloadException(
          'The download stopped at $received of ${spec.bytes} bytes',
        );
      }
      final got = digestSink.digest.toString();
      if (got != spec.sha256.toLowerCase()) {
        throw const ModelDownloadException(
          'The file did not match its checksum, so it was discarded',
        );
      }
      // Same folder, so the rename is atomic: the final name never holds a
      // partial or unverified file.
      await part.rename(fileFor(spec).path);
    } on ModelDownloadException {
      await _discard(sink, part);
      rethrow;
    } on ModelDownloadCancelled {
      await _discard(sink, part);
      rethrow;
    } on FileSystemException catch (e) {
      await _discard(sink, part);
      throw ModelDownloadException(
        'Could not save the file (${e.osError?.message ?? e.message})',
      );
    } on http.ClientException catch (e) {
      await _discard(sink, part);
      throw ModelDownloadException('The connection dropped: ${e.message}');
    } on SocketException {
      await _discard(sink, part);
      throw const ModelDownloadException('The connection dropped');
    } catch (e) {
      await _discard(sink, part);
      throw ModelDownloadException('Unexpected download error: $e');
    }
  }

  Future<void> _discard(IOSink? sink, File part) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  /// Deletes every model file and any partial download. Never throws; returns
  /// whether everything listed is gone.
  Future<bool> removeAll(List<ModelFileSpec> specs) async {
    var ok = true;
    for (final s in specs) {
      for (final f in [fileFor(s), _part(s)]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {
          ok = false;
        }
      }
    }
    return ok;
  }

  /// Removes `.part` files left by a crash or kill. Never throws; returns how
  /// many it removed.
  Future<int> sweepPartials() async {
    var n = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is File && e.path.endsWith(partSuffix)) {
          try {
            await e.delete();
            n++;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return n;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}
