import 'dart:io';

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
  static const _maxConcurrentDownloads = 3;

  bool _isSyncingInternal = false;
  List<Canto>? _pendingSyncList;

  @override
  SyncState build() {
    // Este provider ya contiene exclusivamente sede local + Estatal.
    ref.listen(cantosDeLaSedeProvider, (previous, next) {
      if (next.isNotEmpty) _triggerSync(next);
    });

    final initialList = ref.read(cantosDeLaSedeProvider);
    if (initialList.isNotEmpty) {
      Future.microtask(() => _triggerSync(initialList));
    }

    return SyncState();
  }

  void _triggerSync(List<Canto> cantos) {
    if (_isSyncingInternal) {
      _pendingSyncList = cantos;
      return;
    }
    _isSyncingInternal = true;
    _startBackgroundSync(cantos);
  }

  Future<void> _startBackgroundSync(List<Canto> cantos) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheBox = Hive.box('cache');
    final downloadQueue = <({Canto canto, String tipo})>[];

    for (final canto in cantos) {
      if (canto.archivo.isNotEmpty) {
        final needsPdf = await _necesitaDescargarVersion(
          file: File('${dir.path}/${canto.id}.pdf'),
          versionKey: '${canto.id}_pdf_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );
        if (needsPdf) downloadQueue.add((canto: canto, tipo: 'PDF'));
      }

      if (canto.midiArchivo?.isNotEmpty == true) {
        final needsMidi = await _necesitaDescargarVersion(
          file: File('${dir.path}/${canto.id}.mid'),
          versionKey: '${canto.id}_midi_version',
          cacheBox: cacheBox,
          expectedVersion: canto.version,
        );
        if (needsMidi) downloadQueue.add((canto: canto, tipo: 'MIDI'));
      }
    }

    if (downloadQueue.isEmpty) {
      _finishSync();
      return;
    }

    state = state.copyWith(
      isSyncing: true,
      totalFiles: downloadQueue.length,
      downloadedFiles: 0,
    );

    var downloaded = 0;
    var nextIndex = 0;

    Future<void> worker() async {
      while (state.isSyncing) {
        if (nextIndex >= downloadQueue.length) return;
        final item = downloadQueue[nextIndex++];
        state = state.copyWith(currentItemName: item.canto.nombre);

        try {
          if (item.tipo == 'PDF') {
            await OfflineFiles.ensurePdf(item.canto);
          } else {
            await OfflineFiles.ensureMidi(item.canto);
          }
        } catch (error) {
          debugPrint(
            '[SyncManager] Error al descargar ${item.tipo} '
            'para ${item.canto.nombre}: $error',
          );
        }

        downloaded++;
        state = state.copyWith(downloadedFiles: downloaded);
      }
    }

    final workerCount = downloadQueue.length < _maxConcurrentDownloads
        ? downloadQueue.length
        : _maxConcurrentDownloads;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    state = state.copyWith(
      isSyncing: false,
      currentItemName: 'Sincronización completada',
    );
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
    if (_pendingSyncList == null) return;

    final nextList = _pendingSyncList!;
    _pendingSyncList = null;
    _triggerSync(nextList);
  }
}

final syncManagerProvider =
    NotifierProvider<SyncManagerNotifier, SyncState>(SyncManagerNotifier.new);
