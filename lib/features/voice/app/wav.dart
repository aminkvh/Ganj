import 'dart:convert';
import 'dart:typed_data';

/// The 44-byte header of a 16-bit PCM mono WAV whose samples take [dataLen] bytes.
Uint8List pcm16WavHeader(int dataLen, int sampleRate) {
  final out = Uint8List(44);
  final bd = ByteData.sublistView(out);
  out.setRange(0, 4, ascii.encode('RIFF'));
  bd.setUint32(4, 36 + dataLen, Endian.little);
  out.setRange(8, 12, ascii.encode('WAVE'));
  out.setRange(12, 16, ascii.encode('fmt '));
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 1, Endian.little); // mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  out.setRange(36, 40, ascii.encode('data'));
  bd.setUint32(40, dataLen, Endian.little);
  return out;
}

/// 16-bit PCM mono WAV: a 44-byte header followed by the samples (little-endian).
Uint8List pcm16Wav(Int16List pcm, int sampleRate) {
  final dataLen = pcm.length * 2;
  final out = Uint8List(44 + dataLen)..setRange(0, 44, pcm16WavHeader(dataLen, sampleRate));
  final bd = ByteData.sublistView(out);
  for (var i = 0; i < pcm.length; i++) {
    bd.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return out;
}
