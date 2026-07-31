import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/security/file_crypto.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/canto.dart';

/// Descarga, descifra y conserva PDF/MIDI para uso sin conexión.
class OfflineFiles {
  OfflineFiles._();

  static final Map<String, Future<File>> _inFlight = {};

  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 10)
    ..options.receiveTimeout = const Duration(seconds: 60);

  static String resolvePdfUrl(Canto canto) {
    if (canto.archivo.startsWith('http')) return canto.archivo;
    if (_isUnifiedObjectKey(canto.archivo)) {
      return '${SupabaseService.storageUrl}/v1/files/${_assetOwnerId(canto, canto.archivo)}/pdf';
    }
    return '${SupabaseService.storageUrl}/partituras/${canto.archivo}';
  }

  static String resolveMidiUrl(Canto canto) {
    final midi = canto.midiArchivo!;
    if (midi.startsWith('http')) return midi;
    if (_isUnifiedObjectKey(midi)) {
      return '${SupabaseService.storageUrl}/v1/files/${_assetOwnerId(canto, midi)}/midi';
    }
    return '${SupabaseService.storageUrl}/midi_files/$midi';
  }

  static bool _isUnifiedObjectKey(String value) =>
      value.startsWith('global/') || value.startsWith('local/');

  static String _assetOwnerId(Canto canto, String objectKey) {
    if (objectKey.startsWith('global/') &&
        canto.derivadoDe != null &&
        canto.derivadoDe!.isNotEmpty) {
      return canto.derivadoDe!;
    }
    return canto.id;
  }

  static Future<Directory> _docsDir() => getApplicationDocumentsDirectory();

  static Future<File> pdfFile(String cantoId) async {
    final dir = await _docsDir();
    return File('${dir.path}/$cantoId.pdf');
  }

  static Future<File> midiFile(String cantoId) async {
    final dir = await _docsDir();
    return File('${dir.path}/$cantoId.mid');
  }

  static Future<File> ensurePdf(Canto canto) async {
    return _singleFlight(
      'pdf:${canto.id}',
      () => _ensurePdf(canto),
    );
  }

  static Future<File> _ensurePdf(Canto canto) async {
    final file = await pdfFile(canto.id);
    final metadataKey = '${canto.id}_pdf_version';
    if (await _cachedVersionIsCurrent(
      file,
      metadataKey,
      canto.version,
      FileCrypto.isPdf,
    )) {
      return file;
    }

    await _download(resolvePdfUrl(canto), file, FileCrypto.isPdf);
    await Hive.box('cache').put(metadataKey, canto.version);
    return file;
  }

  static Future<File> ensureMidi(Canto canto) async {
    return _singleFlight(
      'midi:${canto.id}',
      () => _ensureMidi(canto),
    );
  }

  static Future<File> _ensureMidi(Canto canto) async {
    final file = await midiFile(canto.id);
    final metadataKey = '${canto.id}_midi_version';
    if (await _cachedVersionIsCurrent(
      file,
      metadataKey,
      canto.version,
      FileCrypto.isMidi,
    )) {
      return file;
    }

    await _download(resolveMidiUrl(canto), file, FileCrypto.isMidi);
    await Hive.box('cache').put(metadataKey, canto.version);
    return file;
  }

  static Future<File> _singleFlight(
    String key,
    Future<File> Function() operation,
  ) {
    final active = _inFlight[key];
    if (active != null) return active;

    final future = operation();
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key)).ignore();
    return future;
  }

  static Future<void> _download(
    String url,
    File target,
    bool Function(List<int>) validator,
  ) async {
    final encryptedTmp = File('${target.path}.download');
    try {
      if (await encryptedTmp.exists()) await encryptedTmp.delete();
      final token = SupabaseService.client.auth.currentSession?.accessToken;
      await _dio.download(
        url,
        encryptedTmp.path,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      await _decryptAndWrite(
        await encryptedTmp.readAsBytes(),
        target,
        validator,
      );
    } catch (error) {
      debugPrint('[OfflineFiles] Error descargando $url: $error');
      rethrow;
    } finally {
      try {
        if (await encryptedTmp.exists()) await encryptedTmp.delete();
      } catch (_) {}
    }
  }

  static Future<bool> _cachedVersionIsCurrent(
    File file,
    String metadataKey,
    int expectedVersion,
    bool Function(List<int>) validator,
  ) async {
    if (!await _validateCached(file, validator)) return false;
    final box = Hive.box('cache');
    final cachedVersion = box.get(metadataKey) as int?;
    if (cachedVersion == expectedVersion) return true;
    if (cachedVersion == null && expectedVersion == 1) {
      await box.put(metadataKey, 1);
      return true;
    }
    return false;
  }

  static Future<bool> _validateCached(
    File file,
    bool Function(List<int>) validator,
  ) async {
    if (!await file.exists()) return false;
    try {
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(4);
      await raf.close();
      if (validator(header)) return true;

      final bytes = await file.readAsBytes();
      await _decryptAndWrite(bytes, file, validator);
      return true;
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return false;
    }
  }

  static Future<void> _decryptAndWrite(
    Uint8List source,
    File target,
    bool Function(List<int>) validator,
  ) async {
    final clearBytes = await compute(FileCrypto.decryptIfNeeded, source);
    if (!validator(clearBytes)) {
      throw const FormatException('El archivo descifrado no es válido');
    }

    final clearTmp = File('${target.path}.clear');
    if (await clearTmp.exists()) await clearTmp.delete();
    await clearTmp.writeAsBytes(clearBytes, flush: true);
    if (await target.exists()) await target.delete();
    await clearTmp.rename(target.path);
  }
}
