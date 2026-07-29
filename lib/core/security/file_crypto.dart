import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Compatibilidad con PDF y MIDI cifrados por el catálogo LLDM.
///
/// Formato v1: IV de 12 bytes + ciphertext + tag GCM de 16 bytes.
class FileCrypto {
  FileCrypto._();

  static const _rawKey = 'repertorio-coral-lldm-key-2026';
  static const _pdfHeader = [0x25, 0x50, 0x44, 0x46];
  static const _midiHeader = [0x4D, 0x54, 0x68, 0x64];

  static bool isPdf(List<int> bytes) => _hasHeader(bytes, _pdfHeader);
  static bool isMidi(List<int> bytes) => _hasHeader(bytes, _midiHeader);

  static Uint8List decryptIfNeeded(Uint8List bytes) {
    if (isPdf(bytes) || isMidi(bytes)) return bytes;
    if (bytes.length < 28) {
      throw const FormatException('Archivo cifrado incompleto');
    }

    final key = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(_rawKey)),
    );
    final iv = Uint8List.sublistView(bytes, 0, 12);
    final encryptedWithTag = Uint8List.sublistView(bytes, 12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );
    return cipher.process(encryptedWithTag);
  }

  static bool _hasHeader(List<int> bytes, List<int> header) {
    if (bytes.length < header.length) return false;
    for (var index = 0; index < header.length; index++) {
      if (bytes[index] != header[index]) return false;
    }
    return true;
  }
}
