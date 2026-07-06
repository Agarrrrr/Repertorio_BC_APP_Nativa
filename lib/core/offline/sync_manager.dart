import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';

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
  @override
  SyncState build() {
    // Escuchar el provider de cantos filtrados por sede para evitar descargas innecesarias
    ref.listen(cantosDeLaSedeProvider, (previous, next) {
      if (next.isNotEmpty) {
        if (!state.isSyncing) {
          _startBackgroundSync(next);
        }
      }
    });
    return SyncState();
  }

  Future<void> _startBackgroundSync(List cantos) async {
    int totalMissingFiles = 0;
    final dir = await getApplicationDocumentsDirectory();
    final dio = Dio();
    
    // 1. Pre-calcular archivos faltantes
    List<Map<String, dynamic>> downloadQueue = [];
    
    for (var canto in cantos) {
      if (canto.archivo != null && canto.archivo!.isNotEmpty) {
        final pdfFile = File('${dir.path}/${canto.id}.pdf');
        if (!await pdfFile.exists()) {
          downloadQueue.add({
            'nombre': canto.nombre,
            'url': _resolverUrlPdf(canto.archivo!),
            'path': pdfFile.path,
            'tipo': 'PDF'
          });
          totalMissingFiles++;
        }
      }
      if (canto.midiArchivo != null && canto.midiArchivo!.isNotEmpty) {
        final midiFile = File('${dir.path}/${canto.id}.mid');
        if (!await midiFile.exists()) {
          downloadQueue.add({
            'nombre': canto.nombre,
            'url': _resolverUrlMidi(canto.midiArchivo!),
            'path': midiFile.path,
            'tipo': 'MIDI'
          });
          totalMissingFiles++;
        }
      }
    }
    
    if (totalMissingFiles == 0) {
      debugPrint('✅ [SyncManager] Repertorio actualizado. No hay archivos nuevos que descargar.');
      return; // No hacer ruido en la UI
    }

    // 2. Iniciar UI de sincronización solo si hay archivos por descargar
    debugPrint('🔄 [SyncManager] Iniciando descarga de $totalMissingFiles archivos faltantes...');
    state = state.copyWith(isSyncing: true, totalFiles: totalMissingFiles, downloadedFiles: 0);
    
    int downloaded = 0;
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 10);

    for (var item in downloadQueue) {
      if (!state.isSyncing) break; // Si se canceló
      
      state = state.copyWith(currentItemName: item['nombre']);
      
      try {
        debugPrint('🔄 [SyncManager] Descargando ${item['tipo']} para ${item['nombre']}');
        await dio.download(item['url'], item['path']);
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
