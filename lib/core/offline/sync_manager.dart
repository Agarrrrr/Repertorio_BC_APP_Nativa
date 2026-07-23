import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/canto.dart';

class SyncState {
  final bool isSyncing;
  final int totalFiles;
  final int downloadedFiles;
  final String currentItemName;

  SyncState({
    this.isSyncing = false,
    this.totalFiles = 0,
    this.downloadedFiles = 0,
    this.currentItemName = '',
  });

  SyncState copyWith({
    bool? isSyncing,
    int? totalFiles,
    int? downloadedFiles,
    String? currentItemName,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      totalFiles: totalFiles ?? this.totalFiles,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      currentItemName: currentItemName ?? this.currentItemName,
    );
  }
  
  double get progress => totalFiles == 0 ? 0 : downloadedFiles / totalFiles;
}

class SyncManagerNotifier extends Notifier<SyncState> {
  bool _isSyncingInternal = false;
  List<Canto>? _pendingSyncList;

  @override
  SyncState build() {
    // Escuchar el provider de cantos filtrados por sede para evitar descargas innecesarias
    ref.listen(cantosDeLaSedeProvider, (previous, next) {
      if (next.isNotEmpty) {
        _triggerSync(next);
      }
    });

    // Sincronización inicial al iniciar la app si ya hay datos cargados (ej. desde caché)
    final initialList = ref.read(cantosDeLaSedeProvider);
    if (initialList.isNotEmpty) {
      Future.microtask(() => _triggerSync(initialList));
    }

    return SyncState();
  }

  void _triggerSync(List<Canto> cantos) {
    if (_isSyncingInternal) {
      // Guardar la lista más reciente para procesarla en cuanto termine la sincronización actual
      _pendingSyncList = cantos;
      return;
    }
    _isSyncingInternal = true;
    _startBackgroundSync(cantos);
  }

  Future<void> _startBackgroundSync(List<Canto> cantos) async {
    int totalMissingFiles = 0;
    final dir = await getApplicationDocumentsDirectory();
    final dio = Dio();
    final cacheBox = Hive.box('cache');
    
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 10);

    // 1. Pre-calcular archivos faltantes o desactualizados
    List<Map<String, dynamic>> downloadQueue = [];
    
    for (var canto in cantos) {
      if (canto.archivo.isNotEmpty) {
        final pdfFile = File('${dir.path}/${canto.id}.pdf');
        final pdfUrl = _resolverUrlPdf(canto.archivo);
        final pdfMetaKey = '${canto.id}_pdf_meta';

        final requiereActualizacion = await _necesitaDescargar(
          dio: dio,
          file: pdfFile,
          url: pdfUrl,
          metaKey: pdfMetaKey,
          cacheBox: cacheBox,
          updatedAt: canto.updatedAt,
        );

        if (requiereActualizacion) {
          downloadQueue.add({
            'nombre': canto.nombre,
            'url': pdfUrl,
            'path': pdfFile.path,
            'tipo': 'PDF',
            'metaKey': pdfMetaKey,
            'updatedAt': canto.updatedAt,
          });
          totalMissingFiles++;
        }
      }
      if (canto.midiArchivo != null && canto.midiArchivo!.isNotEmpty) {
        final midiFile = File('${dir.path}/${canto.id}.mid');
        final midiUrl = _resolverUrlMidi(canto.midiArchivo!);
        final midiMetaKey = '${canto.id}_midi_meta';

        final requiereActualizacion = await _necesitaDescargar(
          dio: dio,
          file: midiFile,
          url: midiUrl,
          metaKey: midiMetaKey,
          cacheBox: cacheBox,
          updatedAt: canto.updatedAt,
        );

        if (requiereActualizacion) {
          downloadQueue.add({
            'nombre': canto.nombre,
            'url': midiUrl,
            'path': midiFile.path,
            'tipo': 'MIDI',
            'metaKey': midiMetaKey,
            'updatedAt': canto.updatedAt,
          });
          totalMissingFiles++;
        }
      }
    }
    
    if (totalMissingFiles == 0) {
      debugPrint('✅ [SyncManager] Repertorio actualizado. No hay archivos nuevos ni modificados que descargar.');
      _finishSync();
      return; // No hacer ruido en la UI
    }

    // 2. Iniciar UI de sincronización solo si hay archivos por descargar/actualizar
    debugPrint('🔄 [SyncManager] Iniciando descarga de $totalMissingFiles archivos (nuevos/actualizados)...');
    state = state.copyWith(isSyncing: true, totalFiles: totalMissingFiles, downloadedFiles: 0);
    
    int downloaded = 0;

    for (var item in downloadQueue) {
      if (!state.isSyncing) break; // Si se canceló
      
      state = state.copyWith(currentItemName: item['nombre']);
      
      try {
        debugPrint('🔄 [SyncManager] Descargando ${item['tipo']} para ${item['nombre']}');
        
        final targetFile = File(item['path']);
        if (await targetFile.exists()) {
          try { await targetFile.delete(); } catch (_) {}
        }

        final response = await dio.download(item['url'], item['path']);
        
        final etag = response.headers.value('etag');
        final lastModified = response.headers.value('last-modified');
        final contentLength = response.headers.value('content-length');

        cacheBox.put(item['metaKey'], {
          'url': item['url'],
          'updated_at': item['updatedAt'],
          'etag': etag,
          'last_modified': lastModified,
          'content_length': contentLength,
        });
      } catch (e) {
        debugPrint('❌ [SyncManager] Error al descargar ${item['tipo']} para ${item['nombre']}: $e');
      }
      
      downloaded++;
      state = state.copyWith(downloadedFiles: downloaded);
      
      // Pequeña pausa para no saturar el hilo principal
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    debugPrint('🔄 [SyncManager] Sincronización finalizada.');
    state = state.copyWith(isSyncing: false, currentItemName: 'Sincronización completada');
    _finishSync();
  }

  Future<bool> _necesitaDescargar({
    required Dio dio,
    required File file,
    required String url,
    required String metaKey,
    required Box cacheBox,
    String? updatedAt,
  }) async {
    if (!await file.exists()) return true;

    final metaRaw = cacheBox.get(metaKey);
    if (metaRaw == null || metaRaw is! Map || metaRaw['url'] != url) return true;
    if (updatedAt != null && metaRaw['updated_at'] != updatedAt) return true;

    try {
      final response = await dio.get(
        url,
        options: Options(
          headers: {'range': 'bytes=0-10'},
          validateStatus: (status) => status != null && status < 400,
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      final etag = response.headers.value('etag');
      final lastModified = response.headers.value('last-modified');
      final contentLength = response.headers.value('content-length') ?? response.headers.value('content-range');

      if (etag != null && etag != metaRaw['etag']) return true;
      if (lastModified != null && lastModified != metaRaw['last_modified']) return true;
      if (contentLength != null && contentLength != metaRaw['content_length']) return true;
    } catch (e) {
      // En caso de estar offline o error de red, mantener el archivo local actual
      return false;
    }

    return false;
  }

  void _finishSync() {
    _isSyncingInternal = false;
    if (_pendingSyncList != null) {
      final nextList = _pendingSyncList!;
      _pendingSyncList = null;
      _triggerSync(nextList);
    }
  }

  String _resolverUrlPdf(String archivo) {
    if (archivo.startsWith('http')) return archivo;
    final baseUrl = SupabaseService.storageUrl;
    if (baseUrl.contains('supabase.co')) {
      return '$baseUrl/storage/v1/object/public/partituras/$archivo';
    }
    final path = archivo.startsWith('partituras/') ? archivo : 'partituras/$archivo';
    return '$baseUrl/$path';
  }

  String _resolverUrlMidi(String archivoMidi) {
    if (archivoMidi.startsWith('http')) return archivoMidi;
    final baseUrl = SupabaseService.storageUrl;
    if (baseUrl.contains('supabase.co')) {
      return '$baseUrl/storage/v1/object/public/midi_files/$archivoMidi';
    }
    final path = archivoMidi.startsWith('midi_files/') ? archivoMidi : 'midi_files/$archivoMidi';
    return '$baseUrl/$path';
  }
}

final syncManagerProvider = NotifierProvider<SyncManagerNotifier, SyncState>(SyncManagerNotifier.new);
