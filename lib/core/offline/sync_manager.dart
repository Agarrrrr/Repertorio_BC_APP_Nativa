import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
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
    final cacheBox = Hive.box('cache');

    // 1. Pre-calcular archivos faltantes o desactualizados
    List<Map<String, dynamic>> downloadQueue = [];

    for (var canto in cantos) {
      if (canto.archivo.isNotEmpty) {
        final pdfFile = File('${dir.path}/${canto.id}.pdf');
        final requiereActualizacion = await _necesitaDescargarVersion(
          file: pdfFile,
          versionKey: '${canto.id}_pdf_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );

        if (requiereActualizacion) {
          downloadQueue.add({
            'canto': canto,
            'nombre': canto.nombre,
            'tipo': 'PDF',
          });
          totalMissingFiles++;
        }
      }
      if (canto.midiArchivo != null && canto.midiArchivo!.isNotEmpty) {
        final midiFile = File('${dir.path}/${canto.id}.mid');
        final requiereActualizacion = await _necesitaDescargarVersion(
          file: midiFile,
          versionKey: '${canto.id}_midi_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );

        if (requiereActualizacion) {
          downloadQueue.add({
            'canto': canto,
            'nombre': canto.nombre,
            'tipo': 'MIDI',
          });
          totalMissingFiles++;
        }
      }
    }

    if (totalMissingFiles == 0) {
      debugPrint(
          '✅ [SyncManager] Repertorio actualizado. No hay archivos nuevos ni modificados que descargar.');
      _finishSync();
      return; // No hacer ruido en la UI
    }

    // 2. Iniciar UI de sincronización solo si hay archivos por descargar/actualizar
    debugPrint(
        '🔄 [SyncManager] Iniciando descarga de $totalMissingFiles archivos (nuevos/actualizados)...');
    state = state.copyWith(
        isSyncing: true, totalFiles: totalMissingFiles, downloadedFiles: 0);

    int downloaded = 0;

    for (var item in downloadQueue) {
      if (!state.isSyncing) break; // Si se canceló

      state = state.copyWith(currentItemName: item['nombre']);

      try {
        debugPrint(
            '🔄 [SyncManager] Descargando ${item['tipo']} para ${item['nombre']}');

        final canto = item['canto'] as Canto;
        if (item['tipo'] == 'PDF') {
          await OfflineFiles.ensurePdf(canto);
        } else {
          await OfflineFiles.ensureMidi(canto);
        }
      } catch (e) {
        debugPrint(
            '❌ [SyncManager] Error al descargar ${item['tipo']} para ${item['nombre']}: $e');
      }

      downloaded++;
      state = state.copyWith(downloadedFiles: downloaded);

      // Pequeña pausa para no saturar el hilo principal
      await Future.delayed(const Duration(milliseconds: 50));
    }

    debugPrint('🔄 [SyncManager] Sincronización finalizada.');
    state = state.copyWith(
        isSyncing: false, currentItemName: 'Sincronización completada');
    _finishSync();
  }

  Future<bool> _necesitaDescargarVersion({
    required File file,
    required String versionKey,
    required Box cacheBox,
    required int expectedVersion,
  }) async {
    if (!await file.exists()) return true;

    final cachedVersion = cacheBox.get(versionKey) as int?;
    if (cachedVersion == expectedVersion) return false;
    if (cachedVersion == null && expectedVersion == 1) {
      await cacheBox.put(versionKey, 1);
      return false;
    }
    return true;
  }

  void _finishSync() {
    _isSyncingInternal = false;
    if (_pendingSyncList != null) {
      final nextList = _pendingSyncList!;
      _pendingSyncList = null;
      _triggerSync(nextList);
    }
  }
}

final syncManagerProvider =
    NotifierProvider<SyncManagerNotifier, SyncState>(SyncManagerNotifier.new);
