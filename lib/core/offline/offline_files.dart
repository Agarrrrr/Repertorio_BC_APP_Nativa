import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/security/file_crypto.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/utils/single_flight.dart';
import 'package:repertorio_bc/models/canto.dart';

/// Descarga, descifra y conserva PDF/MIDI para uso sin conexión.
class OfflineFiles {
  OfflineFiles._();

  static final SingleFlight<OfflinePdfAsset> _pdfFlights = SingleFlight();
  static final SingleFlight<File> _midiFlights = SingleFlight();
  static const Duration _retiredGracePeriod = Duration(days: 7);
  static const Duration _temporaryMaxAge = Duration(hours: 24);
  static const String _retiredCacheKey = 'offline_retired_first_seen';

  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 20)
    ..options.receiveTimeout = const Duration(minutes: 2);

  static String resolvePdfUrl(Canto canto) {
    if (canto.archivo.startsWith('http')) return canto.archivo;
    if (_isUnifiedObjectKey(canto.archivo)) {
      return '${SupabaseService.storageUrl}/v1/files/${canto.id}/pdf';
    }
    return '${SupabaseService.storageUrl}/partituras/${canto.archivo}';
  }

  static String resolveMidiUrl(Canto canto) {
    final midi = canto.midiArchivo!;
    if (midi.startsWith('http')) return midi;
    if (_isUnifiedObjectKey(midi)) {
      return '${SupabaseService.storageUrl}/v1/files/${canto.id}/midi';
    }
    return '${SupabaseService.storageUrl}/midi_files/$midi';
  }

  static bool _isUnifiedObjectKey(String value) =>
      value.startsWith('global/') || value.startsWith('local/');

  static Future<Directory> _docsDir() => getApplicationDocumentsDirectory();

  static Future<File> pdfFile(String cantoId) async {
    final dir = await _docsDir();
    return File('${dir.path}/$cantoId.pdf');
  }

  static Future<File> midiFile(String cantoId) async {
    final dir = await _docsDir();
    return File('${dir.path}/$cantoId.mid');
  }

  static Future<bool> pdfIsCurrent(Canto canto) async {
    return _cachedVersionIsCurrent(
      await pdfFile(canto.id),
      '${canto.id}_pdf_version',
      canto.version,
      FileCrypto.isPdf,
    );
  }

  static Future<bool> midiIsCurrent(Canto canto) async {
    return _cachedVersionIsCurrent(
      await midiFile(canto.id),
      '${canto.id}_midi_version',
      canto.version,
      FileCrypto.isMidi,
    );
  }

  static Future<bool> hasUsablePdf(String cantoId) async {
    return _validateCached(await pdfFile(cantoId), FileCrypto.isPdf);
  }

  static Future<File> ensurePdf(Canto canto) async {
    final asset = await ensurePdfForViewing(canto);
    if (asset.file != null) return asset.file!;
    throw FileSystemException(
      'Sin espacio para conservar la partitura en el dispositivo',
      canto.nombre,
    );
  }

  /// Prepara una partitura para el visor. Si el dispositivo no permite
  /// escribir (por ejemplo, almacenamiento lleno), devuelve los bytes y el
  /// visor puede mantenerla en RAM durante la sesión.
  static Future<OfflinePdfAsset> ensurePdfForViewing(Canto canto) async {
    return _pdfFlights.run('pdf:${canto.id}', () => _ensurePdfAsset(canto));
  }

  static Future<OfflinePdfAsset> _ensurePdfAsset(Canto canto) async {
    final file = await pdfFile(canto.id);
    if (await _cachedVersionIsCurrent(
      file,
      '${canto.id}_pdf_version',
      canto.version,
      FileCrypto.isPdf,
    )) {
      return OfflinePdfAsset.file(file);
    }

    final encrypted = await _downloadBytes(resolvePdfUrl(canto));
    final clearBytes = await compute(FileCrypto.decryptIfNeeded, encrypted);
    if (!FileCrypto.isPdf(clearBytes)) {
      throw const FormatException('El archivo descifrado no es un PDF válido');
    }

    try {
      await _writeClearBytes(clearBytes, file);
      try {
        await AppCache.put('${canto.id}_pdf_version', canto.version);
      } catch (error) {
        debugPrint('[OfflineFiles] PDF guardado sin metadatos: $error');
      }
      return OfflinePdfAsset.file(file);
    } on FileSystemException catch (error) {
      debugPrint(
        '[OfflineFiles] Sin espacio para guardar ${canto.nombre}; se usará RAM: $error',
      );
      return OfflinePdfAsset.memory(clearBytes);
    }
  }

  static Future<File> ensureMidi(Canto canto) async {
    return _midiFlights.run(
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
    await _saveVersionBestEffort(metadataKey, canto.version);
    return file;
  }

  static Future<void> _download(
    String url,
    File target,
    bool Function(List<int>) validator,
  ) async {
    final encryptedTmp = File('${target.path}.download');
    try {
      Object? lastError;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          if (await encryptedTmp.exists()) await encryptedTmp.delete();
          var token = SupabaseService.client.auth.currentSession?.accessToken;
          await _dio.download(
            url,
            encryptedTmp.path,
            options: Options(
              headers: {
                if (token != null) 'Authorization': 'Bearer $token',
              },
            ),
          );
          lastError = null;
          break;
        } on DioException catch (error) {
          lastError = error;
          final status = error.response?.statusCode;
          if ((status == 401 || status == 403) && attempt == 1) {
            try {
              await SupabaseService.client.auth.refreshSession();
            } catch (_) {}
          }
          final retryable = status == null ||
              status == 401 ||
              status == 403 ||
              status == 408 ||
              status == 429 ||
              status >= 500;
          if (!retryable || attempt == 3) rethrow;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
      if (lastError != null) throw lastError;
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

  static Future<Uint8List> _downloadBytes(String url) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final token = SupabaseService.client.auth.currentSession?.accessToken;
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          ),
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          throw const FormatException('El servidor devolvió un archivo vacío');
        }
        return Uint8List.fromList(data);
      } on DioException catch (error) {
        lastError = error;
        final status = error.response?.statusCode;
        if ((status == 401 || status == 403) && attempt == 1) {
          try {
            await SupabaseService.client.auth.refreshSession();
          } catch (_) {}
        }
        final retryable = status == null ||
            status == 401 ||
            status == 403 ||
            status == 408 ||
            status == 429 ||
            status >= 500;
        if (!retryable || attempt == 3) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw lastError ?? StateError('No se pudo descargar el archivo');
  }

  static bool isStorageError(Object error) {
    if (error is DioException && error.error != null) {
      return isStorageError(error.error!);
    }
    if (error is! FileSystemException) return false;
    final code = error.osError?.errorCode;
    final message =
        '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    return code == 28 ||
        code == 112 ||
        message.contains('no space') ||
        message.contains('disk full') ||
        message.contains('espacio');
  }

  static Future<bool> _cachedVersionIsCurrent(
    File file,
    String metadataKey,
    int expectedVersion,
    bool Function(List<int>) validator,
  ) async {
    if (!await _validateCached(file, validator)) return false;
    final rawVersion = AppCache.get<dynamic>(metadataKey);
    final cachedVersion = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse(rawVersion?.toString() ?? '');
    if (cachedVersion == expectedVersion) return true;
    if (cachedVersion == null && expectedVersion == 1) {
      await _saveVersionBestEffort(metadataKey, 1);
      return true;
    }
    return false;
  }

  static Future<void> _saveVersionBestEffort(String key, int version) async {
    try {
      await AppCache.put(key, version);
    } catch (error) {
      debugPrint('[OfflineFiles] No se pudo guardar metadato $key: $error');
    }
  }

  static Future<bool> _validateCached(
    File file,
    bool Function(List<int>) validator,
  ) async {
    final backup = File('${file.path}.previous');
    if (!await file.exists() && await backup.exists()) {
      try {
        await backup.rename(file.path);
      } on FileSystemException {
        return false;
      }
    }
    if (!await file.exists()) return false;
    try {
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(4);
      await raf.close();
      if (validator(header)) return true;

      final bytes = await file.readAsBytes();
      await _decryptAndWrite(bytes, file, validator);
      return true;
    } on FormatException {
      try {
        await file.delete();
      } catch (_) {}
      return false;
    } on FileSystemException catch (error) {
      debugPrint('[OfflineFiles] No se pudo validar ${file.path}: $error');
      return false;
    } catch (error) {
      debugPrint(
          '[OfflineFiles] Validación inconclusa de ${file.path}: $error');
      return false;
    }
  }

  /// Retira de forma conservadora archivos que ya no pertenecen al catálogo
  /// autoritativo. Nunca borra en la primera ausencia y recupera escrituras
  /// atómicas interrumpidas antes de hacer limpieza.
  static Future<void> reconcileAuthorized(List<Canto> authorized) async {
    try {
      final directory = await _docsDir();
      await directory.create(recursive: true);
      final now = DateTime.now().toUtc();
      final allowed = authorized.map((canto) => canto.id).toSet();
      final retired = Map<String, dynamic>.from(
        AppCache.get<Map<dynamic, dynamic>>(_retiredCacheKey) ??
            const <String, dynamic>{},
      );

      final entities = await directory.list(followLinks: false).toList();
      for (final entity in entities.whereType<File>()) {
        final path = entity.path;
        if (path.endsWith('.previous')) {
          final target =
              File(path.substring(0, path.length - '.previous'.length));
          if (!await target.exists()) {
            try {
              await entity.rename(target.path);
            } on FileSystemException {
              // Se conserva para intentar recuperar en el próximo arranque.
            }
          } else if (await _isOlderThan(entity, now, _temporaryMaxAge)) {
            await _deleteBestEffort(entity);
          }
          continue;
        }
        if (path.endsWith('.download') || path.endsWith('.clear')) {
          if (await _isOlderThan(entity, now, _temporaryMaxAge)) {
            await _deleteBestEffort(entity);
          }
          continue;
        }
      }

      final idsOnDisk = <String>{};
      final uuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      );
      for (final entity in entities.whereType<File>()) {
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.pdf') && !name.endsWith('.mid')) continue;
        final id = name.substring(0, name.length - 4);
        if (uuid.hasMatch(id)) idsOnDisk.add(id);
      }

      for (final id in idsOnDisk) {
        if (allowed.contains(id)) {
          retired.remove(id);
          continue;
        }
        final firstSeen = DateTime.tryParse(retired[id]?.toString() ?? '');
        if (firstSeen == null) {
          retired[id] = now.toIso8601String();
          continue;
        }
        if (now.difference(firstSeen) < _retiredGracePeriod) continue;

        await _deleteBestEffort(await pdfFile(id));
        await _deleteBestEffort(await midiFile(id));
        await AppCache.delete('${id}_pdf_version');
        await AppCache.delete('${id}_midi_version');
        retired.remove(id);
      }

      retired.removeWhere((id, _) => !idsOnDisk.contains(id));
      await AppCache.put(_retiredCacheKey, retired);
    } catch (error) {
      debugPrint('[OfflineFiles] Limpieza conservadora omitida: $error');
    }
  }

  static Future<bool> _isOlderThan(
    File file,
    DateTime now,
    Duration age,
  ) async {
    try {
      return now.difference((await file.stat()).modified.toUtc()) >= age;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      debugPrint('[OfflineFiles] No se pudo retirar ${file.path}: $error');
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

    await _writeClearBytes(clearBytes, target);
  }

  static Future<void> _writeClearBytes(
    Uint8List clearBytes,
    File target,
  ) async {
    final clearTmp = File('${target.path}.clear');
    final backup = File('${target.path}.previous');
    if (await clearTmp.exists()) await clearTmp.delete();
    await clearTmp.writeAsBytes(clearBytes, flush: true);
    if (await backup.exists()) await backup.delete();
    final hadPrevious = await target.exists();
    if (hadPrevious) await target.rename(backup.path);
    try {
      await clearTmp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }
}

class OfflinePdfAsset {
  final File? file;
  final Uint8List? bytes;

  const OfflinePdfAsset._({this.file, this.bytes});

  factory OfflinePdfAsset.file(File file) => OfflinePdfAsset._(file: file);

  factory OfflinePdfAsset.memory(Uint8List bytes) =>
      OfflinePdfAsset._(bytes: bytes);

  bool get isMemoryOnly => bytes != null;
}
