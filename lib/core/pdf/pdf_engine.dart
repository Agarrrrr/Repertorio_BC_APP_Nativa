import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/pdf/annotation_sync_service.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/core/offline/sync_manager.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:repertorio_bc/models/trazo.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class PdfEngineState {
  final String? cantoId;
  final bool isLoading;
  final String? localPath;
  final Uint8List? memoryBytes;
  final String? error;

  // Herramientas de dibujo
  final bool isDrawingMode;
  final ToolType currentTool;
  final Color currentColor;
  final double currentSize;
  final double eraserSize;

  // Trazos por número de página (1-indexed)
  final Map<int, List<Trazo>> trazos;

  // Historial para Deshacer/Rehacer
  final List<Map<int, List<Trazo>>> history;
  final int historyIndex;

  PdfEngineState({
    this.cantoId,
    this.isLoading = true,
    this.localPath,
    this.memoryBytes,
    this.error,
    this.isDrawingMode = false,
    this.currentTool = ToolType.pencil,
    this.currentColor = Colors.black,
    this.currentSize = 3.0,
    this.eraserSize = 20.0,
    this.trazos = const {},
    this.history = const [],
    this.historyIndex = -1,
  });

  PdfEngineState copyWith({
    String? cantoId,
    bool? isLoading,
    String? localPath,
    Uint8List? memoryBytes,
    String? error,
    bool? isDrawingMode,
    ToolType? currentTool,
    Color? currentColor,
    double? currentSize,
    double? eraserSize,
    Map<int, List<Trazo>>? trazos,
    List<Map<int, List<Trazo>>>? history,
    int? historyIndex,
  }) {
    return PdfEngineState(
      cantoId: cantoId ?? this.cantoId,
      isLoading: isLoading ?? this.isLoading,
      localPath: localPath ?? this.localPath,
      memoryBytes: memoryBytes ?? this.memoryBytes,
      error: error,
      isDrawingMode: isDrawingMode ?? this.isDrawingMode,
      currentTool: currentTool ?? this.currentTool,
      currentColor: currentColor ?? this.currentColor,
      currentSize: currentSize ?? this.currentSize,
      eraserSize: eraserSize ?? this.eraserSize,
      trazos: trazos ?? this.trazos,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }
}

class PdfEngineNotifier extends Notifier<PdfEngineState> {
  int _initGeneration = 0;
  int _annotationMutation = 0;
  Timer? _annotationSyncTimer;
  Future<void> _localAnnotationWrites = Future<void>.value();

  @override
  PdfEngineState build() {
    ref.onDispose(() => _annotationSyncTimer?.cancel());
    return PdfEngineState();
  }

  /// Descarta inmediatamente el documento anterior cuando el visor cambia de canto.
  /// La carga del nuevo PDF ocurre después, pero nunca se muestra el anterior.
  void resetForCantoChange() {
    _initGeneration++;
    _annotationSyncTimer?.cancel();
    state = PdfEngineState();
  }

  Future<void> init(Canto canto) async {
    if (state.cantoId == canto.id &&
        (state.isLoading ||
            state.localPath != null ||
            state.memoryBytes != null)) {
      return;
    }

    final generation = ++_initGeneration;
    final perfil = ref.read(perfilProvider).value;
    if (perfil != null && canto.corosVinculados.isNotEmpty) {
      final hasAccess = canto.corosVinculados.contains(perfil.coroId) ||
          canto.corosVinculados.contains('estatal');
      if (!hasAccess) {
        state = PdfEngineState(
          cantoId: canto.id,
          isLoading: false,
          error:
              'No tienes acceso a esta partitura o tu membresía ha sido modificada.',
        );
        return;
      }
    }

    try {
      state = PdfEngineState(cantoId: canto.id, isLoading: true);
      final asset = await OfflineFiles.ensurePdfForViewing(canto);
      if (generation != _initGeneration) return;
      final userId = SupabaseService.client.auth.currentUser?.id;
      var annotations = const AnnotationDocument();
      if (userId != null) {
        annotations = await AnnotationSyncService.loadAndMerge(
          userId: userId,
          cantoId: canto.id,
        );
      }
      if (generation != _initGeneration) return;
      ref.read(syncManagerProvider.notifier).markPdfAvailable(canto.id);

      final initialTrazos = _deepCopyTrazos(annotations.pages);
      state = state.copyWith(
        isLoading: false,
        localPath: asset.file?.path,
        memoryBytes: asset.bytes,
        trazos: initialTrazos,
        history: [initialTrazos],
        historyIndex: 0,
      );
    } catch (e) {
      if (generation != _initGeneration) return;
      state = PdfEngineState(
        cantoId: canto.id,
        isLoading: false,
        error:
            'No se pudo descargar la partitura. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  Future<void> exportPdf(
    String nombreCanto, {
    Rect? sharePositionOrigin,
  }) async {
    if (state.localPath != null || state.memoryBytes != null) {
      // Crear una copia temporal con el nombre correcto para que al compartir aparezca con ese nombre
      final originalFile =
          state.localPath == null ? null : File(state.localPath!);
      final safeName = nombreCanto.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$safeName.pdf');
      try {
        if (originalFile != null) {
          await originalFile.copy(tempFile.path);
        } else {
          await tempFile.writeAsBytes(state.memoryBytes!, flush: true);
        }

        final file = XFile(tempFile.path, mimeType: 'application/pdf');
        await Share.shareXFiles(
          [file],
          sharePositionOrigin: sharePositionOrigin,
        );
      } catch (e) {
        debugPrint('[PdfEngine] Error al exportar/compartir PDF: $e');
        rethrow;
      }
    } else {
      throw StateError('La partitura todavía no está lista para compartirse.');
    }
  }

  void setDrawingMode(bool isDrawing) {
    state = state.copyWith(isDrawingMode: isDrawing);
  }

  void setTool(ToolType tool) {
    state = state.copyWith(currentTool: tool);
  }

  void setCurrentColor(Color color) {
    state = state.copyWith(currentColor: color);
  }

  void setCurrentSize(double size) {
    if (state.currentTool == ToolType.eraser) {
      state = state.copyWith(eraserSize: size);
    } else {
      state = state.copyWith(currentSize: size);
    }
  }

  void _pushHistory(Map<int, List<Trazo>> nuevosTrazos) {
    // Si estamos en medio del historial, borrar el futuro (redo se pierde)
    List<Map<int, List<Trazo>>> newHistory = List.from(state.history);
    if (state.historyIndex < newHistory.length - 1) {
      newHistory = newHistory.sublist(0, state.historyIndex + 1);
    }

    // Si es el primer trazo, guardar el estado inicial vacío
    if (newHistory.isEmpty && state.trazos.isEmpty) {
      newHistory.add({});
    } else if (newHistory.isEmpty) {
      newHistory.add(state.trazos);
    }

    newHistory.add(nuevosTrazos);
    state = state.copyWith(
      trazos: nuevosTrazos,
      history: newHistory,
      historyIndex: newHistory.length - 1,
    );
    _annotationMutation++;
    _cacheAnnotationsLocally();
    _scheduleCloudSync();
  }

  void addTrazo(int pageNumber, Trazo trazo) {
    final Map<int, List<Trazo>> nuevosTrazos = _deepCopyTrazos(state.trazos);
    if (!nuevosTrazos.containsKey(pageNumber)) {
      nuevosTrazos[pageNumber] = [];
    }
    nuevosTrazos[pageNumber]!.add(trazo);

    _pushHistory(nuevosTrazos);
  }

  void updateTrazo(int pageNumber, int index, Trazo trazo) {
    final nuevosTrazos = _deepCopyTrazos(state.trazos);
    final pageTrazos = nuevosTrazos[pageNumber];
    if (pageTrazos == null || index < 0 || index >= pageTrazos.length) return;
    pageTrazos[index] = trazo.copyWith(
      modifiedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    _pushHistory(nuevosTrazos);
  }

  void deleteTrazo(int pageNumber, int index) {
    final nuevosTrazos = _deepCopyTrazos(state.trazos);
    final pageTrazos = nuevosTrazos[pageNumber];
    if (pageTrazos == null || index < 0 || index >= pageTrazos.length) return;
    pageTrazos.removeAt(index);
    _pushHistory(nuevosTrazos);
  }

  void clearAll(int pageNumber) {
    final Map<int, List<Trazo>> nuevosTrazos = _deepCopyTrazos(state.trazos);
    nuevosTrazos[pageNumber] = [];
    _pushHistory(nuevosTrazos);
  }

  void clearAllGlobal() {
    _pushHistory({});
  }

  void undo() {
    if (state.historyIndex > 0) {
      final newIndex = state.historyIndex - 1;
      state = state.copyWith(
        trazos: state.history[newIndex],
        historyIndex: newIndex,
      );
      _annotationMutation++;
      _cacheAnnotationsLocally();
      _scheduleCloudSync();
    }
  }

  void redo() {
    if (state.historyIndex < state.history.length - 1) {
      final newIndex = state.historyIndex + 1;
      state = state.copyWith(
        trazos: state.history[newIndex],
        historyIndex: newIndex,
      );
      _annotationMutation++;
      _cacheAnnotationsLocally();
      _scheduleCloudSync();
    }
  }

  /// Libera el PDF temporal usado cuando no hubo espacio para guardarlo.
  void releaseTransientBytes() {
    if (state.memoryBytes == null) return;
    state = PdfEngineState(
      cantoId: state.cantoId,
      isLoading: false,
      isDrawingMode: state.isDrawingMode,
      currentTool: state.currentTool,
      currentColor: state.currentColor,
      currentSize: state.currentSize,
      eraserSize: state.eraserSize,
      trazos: state.trazos,
      history: state.history,
      historyIndex: state.historyIndex,
    );
  }

  Map<int, List<Trazo>> _deepCopyTrazos(Map<int, List<Trazo>> source) {
    final copy = <int, List<Trazo>>{};
    source.forEach((key, value) {
      copy[key] = value.map((trazo) => trazo.copyWith()).toList();
    });
    return copy;
  }

  void _cacheAnnotationsLocally() {
    final cantoId = state.cantoId;
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (cantoId == null || userId == null) return;
    final snapshot = _deepCopyTrazos(state.trazos);
    _localAnnotationWrites = _localAnnotationWrites.then((_) async {
      await AnnotationSyncService.cacheLocal(
        userId: userId,
        cantoId: cantoId,
        pages: snapshot,
      );
    }).catchError((Object error) {
      debugPrint(
          '[AnnotationSync] No se pudo actualizar la caché local: $error');
    });
  }

  void _scheduleCloudSync() {
    _annotationSyncTimer?.cancel();
    final cantoId = state.cantoId;
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (cantoId == null || userId == null) return;
    final mutation = _annotationMutation;
    _annotationSyncTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_syncAnnotations(userId, cantoId, mutation));
    });
  }

  Future<void> _syncAnnotations(
    String userId,
    String cantoId,
    int mutation,
  ) async {
    await _localAnnotationWrites;
    final merged = await AnnotationSyncService.syncCached(
      userId: userId,
      cantoId: cantoId,
    );
    if (state.cantoId != cantoId || mutation != _annotationMutation) return;
    state = state.copyWith(trazos: _deepCopyTrazos(merged.pages));
  }
}

final pdfEngineProvider =
    NotifierProvider<PdfEngineNotifier, PdfEngineState>(PdfEngineNotifier.new);
