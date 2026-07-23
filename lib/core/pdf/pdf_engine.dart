import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repertorio_bc/models/trazo.dart';
import 'package:share_plus/share_plus.dart';


class PdfEngineState {
  final String? cantoId;
  final bool isLoading;
  final String? localPath;
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
  @override
  PdfEngineState build() {
    return PdfEngineState();
  }

  Future<void> init(String newCantoId) async {
    if (state.cantoId == newCantoId && state.localPath != null) return;
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$newCantoId.pdf');
      final exists = await file.exists();

      // Si el archivo ya existe localmente, cargarlo inmediatamente sin pasar por estado 'loading'
      if (exists) {
        state = PdfEngineState(
          cantoId: newCantoId,
          isLoading: false,
          localPath: file.path,
        );
        return;
      }

      // Si no existe, entrar en modo de carga y esperar descarga
      state = PdfEngineState(cantoId: newCantoId, isLoading: true);

      bool downloaded = false;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (await file.exists()) {
          downloaded = true;
          break;
        }
      }
      if (!downloaded) {
        state = state.copyWith(
          isLoading: false,
          error: 'Partitura no disponible offline',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        localPath: file.path,
      );
    } catch (e) {
      state = PdfEngineState(
        cantoId: newCantoId,
        isLoading: false,
        error: 'Error al cargar partitura: $e',
      );
    }
  }

  Future<void> exportPdf(String nombreCanto) async {
    if (state.localPath != null) {
      // Crear una copia temporal con el nombre correcto para que al compartir aparezca con ese nombre
      final originalFile = File(state.localPath!);
      final safeName = nombreCanto.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File('${originalFile.parent.path}/$safeName.pdf');
      await originalFile.copy(tempFile.path);
      
      final file = XFile(tempFile.path);
      // ignore: deprecated_member_use
      await Share.shareXFiles([file], text: 'Partitura: $nombreCanto');
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
  }

  void addTrazo(int pageNumber, Trazo trazo) {
    final Map<int, List<Trazo>> nuevosTrazos = _deepCopyTrazos(state.trazos);
    if (!nuevosTrazos.containsKey(pageNumber)) {
      nuevosTrazos[pageNumber] = [];
    }
    nuevosTrazos[pageNumber]!.add(trazo);
    
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
    }
  }

  void redo() {
    if (state.historyIndex < state.history.length - 1) {
      final newIndex = state.historyIndex + 1;
      state = state.copyWith(
        trazos: state.history[newIndex],
        historyIndex: newIndex,
      );
    }
  }

  Map<int, List<Trazo>> _deepCopyTrazos(Map<int, List<Trazo>> source) {
    final copy = <int, List<Trazo>>{};
    source.forEach((key, value) {
      copy[key] = List.from(value);
    });
    return copy;
  }
}

final pdfEngineProvider = NotifierProvider<PdfEngineNotifier, PdfEngineState>(PdfEngineNotifier.new);
