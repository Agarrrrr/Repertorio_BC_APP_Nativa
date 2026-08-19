import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/pdf/pdf_engine.dart';
import 'package:repertorio_bc/models/trazo.dart';

class AnnotationLayer extends ConsumerStatefulWidget {
  final String cantoId;
  final int pageNumber;
  final Size pageSize;

  const AnnotationLayer({
    super.key,
    required this.cantoId,
    required this.pageNumber,
    required this.pageSize,
  });

  @override
  ConsumerState<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends ConsumerState<AnnotationLayer> {
  Trazo? _currentTrazo;
  Offset? _textTapPosition;
  Offset? _eraserPreviewPosition;
  int? _selectedTextIndex;
  PointNormalized? _selectedTextPosition;
  double? _selectedTextSize;
  int _activePointers = 0;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event, PdfEngineState state) {
    _activePointers++;
    if (!state.isDrawingMode) return;
    if (_activePointers > 1) {
      setState(() => _currentTrazo = null);
      return;
    }

    if (state.currentTool == ToolType.text) {
      setState(() {
        _textTapPosition = event.localPosition;
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        _textFocusNode.requestFocus();
      });
      return;
    }

    final normalizedPoint = PointNormalized(
      event.localPosition.dx / widget.pageSize.width,
      event.localPosition.dy / widget.pageSize.height,
    );

    setState(() {
      _currentTrazo = Trazo(
        tool: state.currentTool,
        color: state.currentColor,
        size: state.currentTool == ToolType.eraser ? state.eraserSize : state.currentSize,
        points: [normalizedPoint],
      );
      if (state.currentTool == ToolType.eraser) {
        _eraserPreviewPosition = event.localPosition;
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent event, PdfEngineState state) {
    if (!state.isDrawingMode || _currentTrazo == null || state.currentTool == ToolType.text) return;
    if (_activePointers > 1) return;

    final normalizedPoint = PointNormalized(
      event.localPosition.dx / widget.pageSize.width,
      event.localPosition.dy / widget.pageSize.height,
    );

    setState(() {
      _currentTrazo!.points.add(normalizedPoint);
      if (state.currentTool == ToolType.eraser) {
        _eraserPreviewPosition = event.localPosition;
      }
    });
  }

  void _handlePointerUp(PointerUpEvent event, PdfEngineState state) {
    _activePointers--;
    if (_activePointers < 0) _activePointers = 0;
    
    if (!state.isDrawingMode || _currentTrazo == null || state.currentTool == ToolType.text) return;

    ref.read(pdfEngineProvider.notifier).addTrazo(widget.pageNumber, _currentTrazo!);
    setState(() {
      _currentTrazo = null;
      _eraserPreviewPosition = null;
    });
  }
  
  void _handlePointerCancel(PointerCancelEvent event, PdfEngineState state) {
    _activePointers--;
    if (_activePointers < 0) _activePointers = 0;
    setState(() {
      _currentTrazo = null;
      _eraserPreviewPosition = null;
    });
  }

  void _selectText(int index) {
    final text = (ref.read(pdfEngineProvider).trazos[widget.pageNumber] ?? [])[index];
    if (text.pos == null) return;
    setState(() {
      _selectedTextIndex = index;
      _selectedTextPosition = PointNormalized(text.pos!.x, text.pos!.y);
      _selectedTextSize = text.size;
    });
  }

  void _moveSelectedText(Offset delta) {
    final selected = _selectedTextPosition;
    if (selected == null) return;
    setState(() {
      _selectedTextPosition = PointNormalized(
        (selected.x + delta.dx / widget.pageSize.width).clamp(0.0, 1.0),
        (selected.y + delta.dy / widget.pageSize.height).clamp(0.0, 1.0),
      );
    });
  }

  void _resizeSelectedText(double deltaY) {
    setState(() {
      _selectedTextSize = ((_selectedTextSize ?? 3.0) + deltaY / 10).clamp(1.0, 15.0).toDouble();
    });
  }

  void _commitSelectedTextEdit() {
    final index = _selectedTextIndex;
    final position = _selectedTextPosition;
    final size = _selectedTextSize;
    if (index == null || position == null || size == null) return;
    final trazos = ref.read(pdfEngineProvider).trazos[widget.pageNumber];
    if (trazos == null || index >= trazos.length) return;
    ref.read(pdfEngineProvider.notifier).updateTrazo(
      widget.pageNumber, index, trazos[index].copyWith(pos: position, size: size));
  }

  void _deleteSelectedText(int index) {
    ref.read(pdfEngineProvider.notifier).deleteTrazo(widget.pageNumber, index);
    setState(() {
      _selectedTextIndex = null;
      _selectedTextPosition = null;
      _selectedTextSize = null;
    });
  }

  Widget _buildTextSelectionBox(int index, Trazo trazo, PdfEngineState state) {
    final position = index == _selectedTextIndex && _selectedTextPosition != null
        ? _selectedTextPosition! : trazo.pos!;
    final displayTrazo = index == _selectedTextIndex && _selectedTextSize != null
        ? trazo.copyWith(size: _selectedTextSize) : trazo;
    final painter = TextPainter(
      text: TextSpan(text: displayTrazo.texto ?? '', style: TextStyle(
        color: displayTrazo.color, fontSize: displayTrazo.size * 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    return Positioned(
      left: position.x * widget.pageSize.width,
      top: position.y * widget.pageSize.height - painter.height - 6,
      width: painter.width + 16,
      height: painter.height + 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectText(index),
        onPanStart: (_) => _selectText(index),
        onPanUpdate: (details) => _moveSelectedText(details.delta),
        onPanEnd: (_) => _commitSelectedTextEdit(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: state.currentColor.withValues(alpha: 0.9), width: index == _selectedTextIndex ? 1.5 : 1),
            borderRadius: BorderRadius.circular(3), color: Colors.white.withValues(alpha: 0.06)),
          child: Stack(clipBehavior: Clip.none, children: [
            Align(alignment: Alignment.centerLeft, child: Text(displayTrazo.texto ?? '', style: TextStyle(
              color: displayTrazo.color, fontSize: displayTrazo.size * 10, fontWeight: FontWeight.bold))),
            if (index == _selectedTextIndex) ...[
              Positioned(right: -10, top: -11, child: GestureDetector(
                onTap: () => _deleteSelectedText(index),
                child: Container(width: 20, height: 20, decoration: BoxDecoration(color: state.currentColor, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
              Positioned(right: -5, bottom: -5, child: GestureDetector(
                onPanStart: (_) => _selectText(index),
                onPanUpdate: (details) => _resizeSelectedText(details.delta.dy),
                onPanEnd: (_) => _commitSelectedTextEdit(),
                child: Container(width: 10, height: 10, decoration: BoxDecoration(color: state.currentColor, borderRadius: BorderRadius.circular(2))))),
            ],
          ]),
        ),
      ),
    );
  }

  void _commitTextAnnotation(PdfEngineState state) {
    if (_textTapPosition == null || _textController.text.trim().isEmpty) {
      setState(() => _textTapPosition = null);
      _textController.clear();
      return;
    }

    final normalizedPoint = PointNormalized(
      _textTapPosition!.dx / widget.pageSize.width,
      _textTapPosition!.dy / widget.pageSize.height,
    );

    final trazo = Trazo(
      tool: ToolType.text,
      color: state.currentColor,
      size: state.currentSize,
      texto: _textController.text.trim(),
      pos: normalizedPoint,
    );

    ref.read(pdfEngineProvider.notifier).addTrazo(widget.pageNumber, trazo);
    
    setState(() => _textTapPosition = null);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfEngineProvider);
    final savedTrazos = state.trazos[widget.pageNumber] ?? [];

    final trazosToDraw = List<Trazo>.from(savedTrazos);
    if (_currentTrazo != null) trazosToDraw.add(_currentTrazo!);

    return Stack(
      children: [
        // Detector de gestos para dibujar mediante Listener (permite pasar eventos al PDF)
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => _handlePointerDown(event, state),
          onPointerMove: (event) => _handlePointerMove(event, state),
          onPointerUp: (event) => _handlePointerUp(event, state),
          onPointerCancel: (event) => _handlePointerCancel(event, state),
          // IgnorePointer si no estamos en modo dibujo, permite que pdfrx haga scroll
          child: IgnorePointer(
            ignoring: !state.isDrawingMode,
            child: Container(
              color: Colors.transparent, // Necesario para atrapar gestos
              width: widget.pageSize.width,
              height: widget.pageSize.height,
              child: CustomPaint(
                painter: _AnnotationPainter(trazosToDraw,
                  eraserPreviewPosition: _eraserPreviewPosition,
                  eraserPreviewSize: state.eraserSize,
                  showTextInOverlay: state.isDrawingMode && state.currentTool == ToolType.text),
              ),
            ),
          ),
        ),
        if (state.isDrawingMode && state.currentTool == ToolType.text)
          for (var i = 0; i < savedTrazos.length; i++)
            if (savedTrazos[i].tool == ToolType.text && savedTrazos[i].texto != null && savedTrazos[i].pos != null)
              _buildTextSelectionBox(i, savedTrazos[i], state),

        // Widget flotante para texto nativo (Sin modales!)
        if (_textTapPosition != null)
          Positioned(
            left: _textTapPosition!.dx,
            top: _textTapPosition!.dy - (state.currentSize * 10), // Ajuste visual
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(minWidth: 150),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  border: Border.all(color: Colors.grey, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  style: TextStyle(
                    color: state.currentColor,
                    fontSize: state.currentSize * 10,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  ),
                  onSubmitted: (_) => _commitTextAnnotation(state),
                  onTapOutside: (_) => _commitTextAnnotation(state),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<Trazo> trazos;
  final Offset? eraserPreviewPosition;
  final double eraserPreviewSize;
  final bool showTextInOverlay;

  _AnnotationPainter(this.trazos, {
    this.eraserPreviewPosition,
    this.eraserPreviewSize = 20,
    this.showTextInOverlay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Aislar la capa para que el BlendMode.clear del borrador no perfore toda la pantalla
    canvas.saveLayer(Offset.zero & size, Paint());

    for (var trazo in trazos) {
      if (trazo.oculto) continue;

      if (trazo.tool == ToolType.text && trazo.texto != null && trazo.pos != null) {
        if (showTextInOverlay) continue;
        final textPainter = TextPainter(
          text: TextSpan(
            text: trazo.texto,
            style: TextStyle(
              color: trazo.color,
              fontSize: trazo.size * 10, // Escalar el tamaño base
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        final dx = trazo.pos!.x * size.width;
        // Ajuste baseline
        final dy = (trazo.pos!.y * size.height) - textPainter.height; 
        textPainter.paint(canvas, Offset(dx, dy));
        continue;
      }

      if (trazo.points.length < 2) {
        if (trazo.tool == ToolType.eraser && trazo.points.isNotEmpty) {
          final point = trazo.points.first;
          canvas.drawCircle(Offset(point.x * size.width, point.y * size.height), trazo.size / 2,
            Paint()..blendMode = BlendMode.clear);
        }
        continue;
      }

      final paint = Paint()
        ..color = trazo.color
        ..strokeWidth = trazo.tool == ToolType.eraser ? 20.0 : trazo.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = trazo.tool == ToolType.eraser ? BlendMode.clear : BlendMode.srcOver;

      final path = Path();
      path.moveTo(trazo.points.first.x * size.width, trazo.points.first.y * size.height);
      for (int i = 1; i < trazo.points.length; i++) {
        path.lineTo(trazo.points[i].x * size.width, trazo.points[i].y * size.height);
      }
      
      canvas.drawPath(path, paint);
    }

    if (eraserPreviewPosition != null) {
      final previewPaint = Paint()..color = Colors.black.withValues(alpha: 0.22);
      final outlinePaint = Paint()..color = Colors.black.withValues(alpha: 0.72)..style = PaintingStyle.stroke..strokeWidth = 1.2;
      canvas.drawCircle(eraserPreviewPosition!, eraserPreviewSize / 2, previewPaint);
      canvas.drawCircle(eraserPreviewPosition!, eraserPreviewSize / 2, outlinePaint);
    }
    
    // Restaurar la capa
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
