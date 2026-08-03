import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/models/canto.dart';

class SyncState {
  final bool isSyncing;
  final int totalFiles;
  final int downloadedFiles;
  final int failedFiles;
  final Set<String> failedCantoIds;
  final Set<String> failedPdfCantoIds;
  final Set<String> failedMidiCantoIds;
  final bool storageUnavailable;
  final String currentItemName;

  const SyncState({
    this.isSyncing = false,
    this.totalFiles = 0,
    this.downloadedFiles = 0,
    this.failedFiles = 0,
    this.failedCantoIds = const {},
    this.failedPdfCantoIds = const {},
    this.failedMidiCantoIds = const {},
    this.storageUnavailable = false,
    this.currentItemName = '',
  });

  SyncState copyWith({
    bool? isSyncing,
    int? totalFiles,
    int? downloadedFiles,
    int? failedFiles,
    Set<String>? failedCantoIds,
    Set<String>? failedPdfCantoIds,
    Set<String>? failedMidiCantoIds,
    bool? storageUnavailable,
    String? currentItemName,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      totalFiles: totalFiles ?? this.totalFiles,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      failedFiles: failedFiles ?? this.failedFiles,
      failedCantoIds: failedCantoIds ?? this.failedCantoIds,
      failedPdfCantoIds: failedPdfCantoIds ?? this.failedPdfCantoIds,
      failedMidiCantoIds: failedMidiCantoIds ?? this.failedMidiCantoIds,
      storageUnavailable: storageUnavailable ?? this.storageUnavailable,
      currentItemName: currentItemName ?? this.currentItemName,
    );
  }

  double get progress => totalFiles == 0 ? 0 : downloadedFiles / totalFiles;
}

class SyncManagerNotifier extends Notifier<SyncState> {
  bool _isSyncingInternal = false;
  List<Canto>? _pendingSyncList;
  int _generation = 0;

  @override
  SyncState build() {
    ref.listen(cantosOfflineStateProvider, (previous, next) {
      if (next.hasValue) _triggerSync(next.value!);
    });

    final initial = ref.read(cantosOfflineStateProvider);
    if (initial.hasValue) {
      Future.microtask(() => _triggerSync(initial.value!));
    }

    return const SyncState();
  }

  void _triggerSync(List<Canto> cantos) {
    if (_isSyncingInternal) {
      _generation++;
      _pendingSyncList = cantos;
      return;
    }

    _isSyncingInternal = true;
    final generation = ++_generation;
    _runSync(cantos, generation);
  }

  /// Revalida el catálogo y vuelve a intentar archivos faltantes o dañados.
  void repairNow(List<Canto> cantos) => _triggerSync(cantos);

  Future<void> _runSync(List<Canto> cantos, int generation) async {
    try {
      await _startBackgroundSync(cantos, generation);
    } catch (error) {
      debugPrint('[SyncManager] Error preparando el modo offline: $error');
      if (generation == _generation) {
        state = state.copyWith(
          isSyncing: false,
          failedFiles: state.failedFiles + 1,
          currentItemName: 'No se pudo preparar el repertorio offline',
        );
      }
    } finally {
      _finishSync();
    }
  }

  Future<void> _startBackgroundSync(
    List<Canto> cantos,
    int generation,
  ) async {
    final checkFutures = cantos.map((canto) async {
      final items = <({Canto canto, String tipo})>[];
      if (canto.archivo.isNotEmpty) {
        final needsPdf = !await OfflineFiles.pdfIsCurrent(canto);
        if (needsPdf) items.add((canto: canto, tipo: 'PDF'));
      }

      if (canto.midiArchivo?.isNotEmpty == true) {
        final needsMidi = !await OfflineFiles.midiIsCurrent(canto);
        if (needsMidi) items.add((canto: canto, tipo: 'MIDI'));
      }
      return items;
    });

    final results = await Future.wait(checkFutures);
    if (generation != _generation) return;

    final downloadQueue = <({Canto canto, String tipo})>[];
    for (final list in results) {
      downloadQueue.addAll(list);
    }

    if (downloadQueue.isEmpty) {
      state = const SyncState(
        currentItemName: 'Repertorio asignado disponible offline',
      );
      return;
    }

    state = SyncState(
      isSyncing: true,
      totalFiles: downloadQueue.length,
    );

    var processed = 0;
    var storageUnavailable = false;
    final failedPdfIds = <String>{};
    final failedMidiIds = <String>{};

    // Una transferencia a la vez: evita saturar dispositivos y conexiones
    // lentas, y permite que cada archivo aproveche todo el ancho de banda.
    for (final item in downloadQueue) {
      if (generation != _generation) return;
      try {
        if (item.tipo == 'PDF') {
          await OfflineFiles.ensurePdf(item.canto);
        } else {
          await OfflineFiles.ensureMidi(item.canto);
        }
      } catch (error) {
        if (OfflineFiles.isStorageError(error)) {
          storageUnavailable = true;
          debugPrint(
            '[SyncManager] Almacenamiento lleno; se detiene la precarga.',
          );
          break;
        }
        if (item.tipo == 'PDF') {
          // Si una actualización falla pero hay una copia anterior válida, se
          // conserva disponible y se reintenta en la siguiente sincronización.
          if (!await OfflineFiles.hasUsablePdf(item.canto.id)) {
            failedPdfIds.add(item.canto.id);
          }
        } else {
          failedMidiIds.add(item.canto.id);
        }
        debugPrint(
          '[SyncManager] Falta ${item.tipo} de ${item.canto.nombre}: $error',
        );
      }

      processed++;
      if (generation == _generation) {
        final failedIds = <String>{...failedPdfIds, ...failedMidiIds};
        state = state.copyWith(
          downloadedFiles: processed,
          failedFiles: failedIds.length,
          failedCantoIds: Set.unmodifiable(failedIds),
          failedPdfCantoIds: Set.unmodifiable(failedPdfIds),
          failedMidiCantoIds: Set.unmodifiable(failedMidiIds),
          storageUnavailable: storageUnavailable,
          currentItemName: item.canto.nombre,
        );
      }
    }

    if (generation != _generation) return;

    state = state.copyWith(
      isSyncing: false,
      storageUnavailable: storageUnavailable,
      currentItemName: storageUnavailable
          ? 'Sin espacio: las partituras se abrirán en línea'
          : state.failedFiles == 0
              ? 'Repertorio asignado disponible offline'
              : '${state.failedFiles} cantos requieren atención',
    );
  }

  void markPdfAvailable(String cantoId) {
    _clearFailure(cantoId, pdf: true);
  }

  void markMidiAvailable(String cantoId) {
    _clearFailure(cantoId, pdf: false);
  }

  void markMidiUnavailable(String cantoId) {
    final midi = {...state.failedMidiCantoIds, cantoId};
    final all = <String>{...state.failedPdfCantoIds, ...midi};
    state = state.copyWith(
      failedFiles: all.length,
      failedCantoIds: Set.unmodifiable(all),
      failedMidiCantoIds: Set.unmodifiable(midi),
    );
  }

  void _clearFailure(String cantoId, {required bool pdf}) {
    final pdfIds = {...state.failedPdfCantoIds};
    final midiIds = {...state.failedMidiCantoIds};
    (pdf ? pdfIds : midiIds).remove(cantoId);
    final all = <String>{...pdfIds, ...midiIds};
    state = state.copyWith(
      failedFiles: all.length,
      failedCantoIds: Set.unmodifiable(all),
      failedPdfCantoIds: Set.unmodifiable(pdfIds),
      failedMidiCantoIds: Set.unmodifiable(midiIds),
      currentItemName: all.isEmpty
          ? 'Repertorio asignado disponible offline'
          : state.currentItemName,
    );
  }

  void _finishSync() {
    _isSyncingInternal = false;
    if (_pendingSyncList == null) return;

    final nextList = _pendingSyncList!;
    _pendingSyncList = null;
    _triggerSync(nextList);
  }
}

final syncManagerProvider =
    NotifierProvider<SyncManagerNotifier, SyncState>(SyncManagerNotifier.new);
