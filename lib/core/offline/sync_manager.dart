import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/models/canto.dart';

class SyncState {
  final bool isSyncing;
  final int totalFiles;
  final int downloadedFiles;
  final int failedFiles;
  final Set<String> failedCantoIds;
  final String currentItemName;

  const SyncState({
    this.isSyncing = false,
    this.totalFiles = 0,
    this.downloadedFiles = 0,
    this.failedFiles = 0,
    this.failedCantoIds = const {},
    this.currentItemName = '',
  });

  SyncState copyWith({
    bool? isSyncing,
    int? totalFiles,
    int? downloadedFiles,
    int? failedFiles,
    Set<String>? failedCantoIds,
    String? currentItemName,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      totalFiles: totalFiles ?? this.totalFiles,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      failedFiles: failedFiles ?? this.failedFiles,
      failedCantoIds: failedCantoIds ?? this.failedCantoIds,
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
    final dir = await getApplicationDocumentsDirectory();
    final cacheBox = Hive.box('cache');

    await _removeUnassignedFiles(cantos, dir, cacheBox);
    if (generation != _generation) return;

    final checkFutures = cantos.map((canto) async {
      final items = <({Canto canto, String tipo})>[];
      if (canto.archivo.isNotEmpty) {
        final needsPdf = await _needsDownload(
          file: File('${dir.path}/${canto.id}.pdf'),
          versionKey: '${canto.id}_pdf_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );
        if (needsPdf) items.add((canto: canto, tipo: 'PDF'));
      }

      if (canto.midiArchivo?.isNotEmpty == true) {
        final needsMidi = await _needsDownload(
          file: File('${dir.path}/${canto.id}.mid'),
          versionKey: '${canto.id}_midi_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );
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
    var failedFiles = 0;
    final failedCantoIds = <String>{};

    // Descarga paralela controlada (máximo 3 transferencias simultáneas)
    const maxConcurrency = 3;
    var index = 0;

    Future<void> worker() async {
      while (index < downloadQueue.length) {
        if (generation != _generation) return;
        final currentIndex = index++;
        final item = downloadQueue[currentIndex];

        try {
          if (item.tipo == 'PDF') {
            await OfflineFiles.ensurePdf(item.canto);
          } else {
            await OfflineFiles.ensureMidi(item.canto);
          }
        } catch (error) {
          failedFiles++;
          failedCantoIds.add(item.canto.id);
          debugPrint(
            '[SyncManager] Falta ${item.tipo} de ${item.canto.nombre}: $error',
          );
        }

        processed++;
        if (generation == _generation) {
          state = state.copyWith(
            downloadedFiles: processed,
            failedFiles: failedFiles,
            failedCantoIds: Set.unmodifiable(failedCantoIds),
            currentItemName: item.canto.nombre,
          );
        }
      }
    }

    final workers = List.generate(
      math.min(maxConcurrency, downloadQueue.length),
      (_) => worker(),
    );
    await Future.wait(workers);

    if (generation != _generation) return;

    state = state.copyWith(
      isSyncing: false,
      currentItemName: failedFiles == 0
          ? 'Repertorio asignado disponible offline'
          : 'Faltan $failedFiles archivos',
    );
  }

  Future<void> _removeUnassignedFiles(
    List<Canto> cantos,
    Directory dir,
    Box cacheBox,
  ) async {
    final expectedTypes = <String, Set<String>>{
      for (final canto in cantos)
        canto.id: {
          if (canto.archivo.isNotEmpty) 'pdf',
          if (canto.midiArchivo?.isNotEmpty == true) 'midi',
        },
    };
    final versionKeyPattern = RegExp(r'^(.+)_(pdf|midi)_version$');

    for (final rawKey in cacheBox.keys.toList(growable: false)) {
      if (rawKey is! String) continue;
      final match = versionKeyPattern.firstMatch(rawKey);
      if (match == null) continue;

      final cantoId = match.group(1)!;
      final type = match.group(2)!;
      if (expectedTypes[cantoId]?.contains(type) == true) continue;

      final extension = type == 'pdf' ? 'pdf' : 'mid';
      final file = File('${dir.path}/$cantoId.$extension');
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[SyncManager] No se pudo retirar ${file.path}: $error');
      }
      await cacheBox.delete(rawKey);
    }
  }

  Future<bool> _needsDownload({
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
    if (_pendingSyncList == null) return;

    final nextList = _pendingSyncList!;
    _pendingSyncList = null;
    _triggerSync(nextList);
  }
}

final syncManagerProvider =
    NotifierProvider<SyncManagerNotifier, SyncState>(SyncManagerNotifier.new);
