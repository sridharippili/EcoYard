import 'dart:typed_data';

/// Mono audio as floats in -1..1, with its sample rate.
class PcmAudio {
  const PcmAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;

  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);
}

/// Decodes a RIFF/WAVE file (PCM 16-bit or IEEE float 32-bit) into mono
/// floats. Stereo and multi-channel audio is averaged to mono.
///
/// Pure Dart, no plugin. Throws [FormatException] with a plain reason for
/// anything it cannot read, so the offline provider can report it honestly.
PcmAudio decodeWav(Uint8List bytes) {
  if (bytes.length < 12) throw const FormatException('Too short to be a WAV');
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int? format, channels, sampleRate, bits;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      if (size < 16 || body + 16 > bytes.length) {
        throw const FormatException('Broken fmt chunk');
      }
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      if (sampleRate == 0) throw const FormatException('WAV sample rate is 0');
      // WAVE_FORMAT_EXTENSIBLE: the real format is in the sub-format GUID.
      if (format == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
        format = data.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (format == null) {
        throw const FormatException('Audio data before the fmt chunk');
      }
      // A recorder killed mid-write can leave a size larger than the file.
      final available = bytes.length - body;
      final length = size > available ? available : size;
      return PcmAudio(
        _toMono(data, body, length, format, channels!, bits!),
        sampleRate!,
      );
    }
    // Chunks are padded to an even size.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('No audio data in the WAV');
}

Float32List _toMono(
  ByteData data,
  int start,
  int length,
  int format,
  int channels,
  int bits,
) {
  if (channels < 1) throw const FormatException('WAV has no channels');
  final isPcm16 = format == 1 && bits == 16;
  final isFloat32 = format == 3 && bits == 32;
  if (!isPcm16 && !isFloat32) {
    throw FormatException('Unsupported WAV format ($format, $bits-bit)');
  }
  final bytesPerSample = bits ~/ 8;
  final frameBytes = bytesPerSample * channels;
  final frames = length ~/ frameBytes;
  final out = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      final at = start + f * frameBytes + c * bytesPerSample;
      sum += isPcm16
          ? data.getInt16(at, Endian.little) / 32768.0
          : data.getFloat32(at, Endian.little);
    }
    out[f] = (sum / channels).clamp(-1.0, 1.0);
  }
  return out;
}
