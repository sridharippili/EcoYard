import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A fake client that streams [body] in chunks, with hooks for the awkward
/// cases: a wrong Content-Length, no Content-Length, a redirect, a mid-stream
/// drop, and a pause so a test can cancel.
class FakeClient extends http.BaseClient {
  FakeClient({
    required this.body,
    this.status = 200,
    this.contentLength,
    this.omitContentLength = false,
    this.chunkSize = 16,
    this.failAfterBytes,
    this.finalUrl,
    this.onChunk,
    this.throwOnSend,
    this.headers = const {},
  });

  final List<int> body;
  final int status;
  final int? contentLength;
  final bool omitContentLength;
  final int chunkSize;
  final int? failAfterBytes;
  final Uri? finalUrl;
  final FutureOr<void> Function(int sent)? onChunk;
  final Object? throwOnSend;
  final Map<String, String> headers;

  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    if (throwOnSend != null) throw throwOnSend!;
    final controller = StreamController<List<int>>();
    unawaited(() async {
      var sent = 0;
      try {
        for (var i = 0; i < body.length; i += chunkSize) {
          final end = (i + chunkSize).clamp(0, body.length);
          if (failAfterBytes != null && sent >= failAfterBytes!) {
            controller.addError(http.ClientException('connection reset'));
            await controller.close();
            return;
          }
          controller.add(body.sublist(i, end));
          sent = end;
          await onChunk?.call(sent);
          await Future<void>.delayed(Duration.zero);
        }
        await controller.close();
      } catch (e) {
        controller.addError(e);
        await controller.close();
      }
    }());
    return http.StreamedResponse(
      controller.stream,
      status,
      contentLength: omitContentLength ? null : (contentLength ?? body.length),
      request: http.Request('GET', finalUrl ?? request.url),
      headers: headers,
    );
  }
}

void main() {
  late Directory dir;
  final payload = Uint8List.fromList(
    List.generate(1000, (i) => (i * 7) % 256),
  );
  final goodHash = sha256.convert(payload).toString();

  ModelFileSpec spec({
    String name = 'model-v1.tflite',
    String url = 'https://example.test/model',
    int? bytes,
    String? hash,
  }) =>
      ModelFileSpec(
        name: name,
        url: url,
        bytes: bytes ?? payload.length,
        sha256: hash ?? goodHash,
      );

  setUp(() => dir = Directory.systemTemp.createTempSync('ecoyard_model_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ModelStore store(FakeClient c) => ModelStore(dir: dir, client: c);
  File out([String name = 'model-v1.tflite']) => File('${dir.path}/$name');
  File part([String name = 'model-v1.tflite']) =>
      File('${dir.path}/$name${ModelStore.partSuffix}');

  group('a good download', () {
    test('writes the verified file, reports progress, leaves no .part',
        () async {
      final progress = <int>[];
      await store(FakeClient(body: payload)).download(
        spec(),
        onProgress: (received, total) {
          expect(total, payload.length);
          progress.add(received);
        },
      );
      expect(out().readAsBytesSync(), payload);
      expect(part().existsSync(), isFalse);
      expect(progress.first, 0);
      expect(progress.last, payload.length);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('works when the server sends no Content-Length', () async {
      await store(FakeClient(body: payload, omitContentLength: true))
          .download(spec());
      expect(out().existsSync(), isTrue);
    });

    test('follows a redirect to another https address', () async {
      await store(
        FakeClient(body: payload, finalUrl: Uri.parse('https://cdn.test/x')),
      ).download(spec());
      expect(out().existsSync(), isTrue);
    });

    test('a second download replaces the file (new version)', () async {
      final s = store(FakeClient(body: payload));
      await s.download(spec());
      await s.download(spec());
      expect(out().lengthSync(), payload.length);
    });
  });

  group('refusals', () {
    Future<void> expectFails(
      FakeClient client,
      ModelFileSpec s, {
      required Matcher message,
    }) async {
      await expectLater(
        store(client).download(s),
        throwsA(isA<ModelDownloadException>()
            .having((e) => e.message, 'message', message)),
      );
      expect(out(s.name).existsSync(), isFalse, reason: 'no final file');
      expect(part(s.name).existsSync(), isFalse, reason: 'no .part left');
    }

    test('a wrong checksum is discarded', () async {
      await expectFails(
        FakeClient(body: payload),
        spec(hash: 'a' * 64),
        message: contains('checksum'),
      );
    });

    test(
        'a Content-Length that disagrees with the content is refused before '
        'downloading', () async {
      final client = FakeClient(body: payload, contentLength: 999999);
      await expectFails(client, spec(), message: contains('999999 bytes'));
    });

    test(
        'a compressed transfer: Content-Length is the compressed size, the '
        'saved bytes are the full file, and it is accepted', () async {
      // Seen for real on raw.githubusercontent.com: the labels file arrives
      // gzip-compressed (76,902 bytes on the wire) and is decompressed by the
      // HTTP client to the exact 259,740 bytes we expect.
      final client = FakeClient(
        body: payload,
        contentLength: 321,
        headers: const {'content-encoding': 'gzip'},
      );
      await store(client).download(spec());
      expect(out().readAsBytesSync(), payload);
    });

    test('a body longer than expected is stopped mid-stream', () async {
      final big = Uint8List.fromList([...payload, ...payload]);
      await expectFails(
        FakeClient(body: big, omitContentLength: true),
        spec(),
        message: contains('larger than'),
      );
    });

    test('a short body is refused', () async {
      final short = Uint8List.sublistView(payload, 0, 500);
      await expectFails(
        FakeClient(body: short, omitContentLength: true),
        spec(),
        message: contains('stopped at 500'),
      );
    });

    test('a non-200 status is refused', () async {
      await expectFails(
        FakeClient(body: const [], status: 404),
        spec(),
        message: contains('404'),
      );
    });

    test('a dropped connection is refused', () async {
      await expectFails(
        FakeClient(body: payload, failAfterBytes: 200, omitContentLength: true),
        spec(),
        message: contains('connection'),
      );
    });

    test('no internet is said plainly', () async {
      await expectFails(
        FakeClient(
          body: const [],
          throwOnSend: const SocketException('nope'),
        ),
        spec(),
        message: contains('No internet'),
      );
    });

    test('http (not https) is refused without connecting', () async {
      final client = FakeClient(body: payload);
      await expectLater(
        store(client).download(spec(url: 'http://example.test/model')),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(client.sends, 0);
    });

    test('a redirect away from https is refused', () async {
      await expectFails(
        FakeClient(body: payload, finalUrl: Uri.parse('http://cdn.test/x')),
        spec(),
        message: contains('redirected'),
      );
    });

    test('a leftover .part from a crash is replaced, not appended to',
        () async {
      part().writeAsBytesSync(List.filled(50, 9));
      await store(FakeClient(body: payload)).download(spec());
      expect(out().readAsBytesSync(), payload);
    });
  });

  group('cancel', () {
    test('stops the download and leaves nothing behind', () async {
      final cancel = CancelToken();
      final client = FakeClient(
        body: payload,
        chunkSize: 100,
        onChunk: (sent) {
          if (sent >= 300) cancel.cancel();
        },
      );
      await expectLater(
        store(client).download(spec(), cancel: cancel),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(out().existsSync(), isFalse);
      expect(part().existsSync(), isFalse);
    });

    test(
        'cancel stops the download early: it does not read the whole file '
        'first', () async {
      final cancel = CancelToken();
      var lastReceived = 0;
      // Cancel from the reader's own progress, so this does not depend on
      // how far ahead the fake server has run.
      await expectLater(
        store(FakeClient(body: payload, chunkSize: 100)).download(
          spec(),
          cancel: cancel,
          onProgress: (received, _) {
            lastReceived = received;
            if (received >= 200) cancel.cancel();
          },
        ),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(lastReceived, lessThan(payload.length),
          reason: 'the reader must stop, not finish the file');
      expect(out().existsSync(), isFalse);
      expect(part().existsSync(), isFalse);
    });

    test('cancelling before it starts downloads nothing', () async {
      final cancel = CancelToken()..cancel();
      await expectLater(
        store(FakeClient(body: payload)).download(spec(), cancel: cancel),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(out().existsSync(), isFalse);
    });

    test('a cancel after the last byte still leaves no half file', () async {
      final cancel = CancelToken();
      final client = FakeClient(
        body: payload,
        chunkSize: payload.length,
        onChunk: (_) => cancel.cancel(),
      );
      await expectLater(
        store(client).download(spec(), cancel: cancel),
        throwsA(anything),
      );
      expect(part().existsSync(), isFalse);
    });
  });

  group('isReady', () {
    test('false before, true after, false again after removal', () async {
      final s = store(FakeClient(body: payload));
      expect(await s.isReady([spec()]), isFalse);
      await s.download(spec());
      expect(await s.isReady([spec()]), isTrue);
      expect(await s.removeAll([spec()]), isTrue);
      expect(await s.isReady([spec()]), isFalse);
    });

    test('a file of the wrong size (purged or replaced) is not ready',
        () async {
      out().writeAsBytesSync(List.filled(10, 1));
      expect(await store(FakeClient(body: payload)).isReady([spec()]), isFalse);
    });

    test('every file must be there', () async {
      final s = store(FakeClient(body: payload));
      await s.download(spec());
      final labels = spec(name: 'labels-v1.txt');
      expect(await s.isReady([spec(), labels]), isFalse);
    });

    test('an empty list is not "ready"', () async {
      expect(await store(FakeClient(body: payload)).isReady([]), isFalse);
    });

    test('a missing folder is not ready and does not throw', () async {
      dir.deleteSync(recursive: true);
      expect(await store(FakeClient(body: payload)).isReady([spec()]), isFalse);
    });
  });

  group('cleanup', () {
    test('removeAll deletes the file and any .part', () async {
      out().writeAsBytesSync([1]);
      part().writeAsBytesSync([1]);
      expect(
          await store(FakeClient(body: payload)).removeAll([spec()]), isTrue);
      expect(dir.listSync(), isEmpty);
    });

    test('removing what is not there is fine', () async {
      expect(
          await store(FakeClient(body: payload)).removeAll([spec()]), isTrue);
    });

    test('sweepPartials removes only .part files', () async {
      part().writeAsBytesSync([1]);
      File('${dir.path}/other.part').writeAsBytesSync([1]);
      out().writeAsBytesSync([1]);
      File('${dir.path}/keep.txt').writeAsBytesSync([1]);
      final n = await store(FakeClient(body: payload)).sweepPartials();
      expect(n, 2);
      expect(out().existsSync(), isTrue);
      expect(File('${dir.path}/keep.txt').existsSync(), isTrue);
    });

    test('sweeping an empty or missing folder is 0, never an error', () async {
      expect(await store(FakeClient(body: payload)).sweepPartials(), 0);
      dir.deleteSync(recursive: true);
      expect(await store(FakeClient(body: payload)).sweepPartials(), 0);
    });
  });

  test('the checksum really is of the bytes (control)', () async {
    final other = Uint8List.fromList(utf8.encode('something else'));
    expect(sha256.convert(other).toString(), isNot(goodHash));
  });
}
