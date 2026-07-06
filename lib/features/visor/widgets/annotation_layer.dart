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
    });
  }

  void _handlePointerUp(PointerUpEvent event, PdfEngineState state) {
    _activePointers--;
    if (_activePointers < 0) _activePointers = 0;
    
    if (!state.isDrawingMode || _currentTrazo == null || state.currentTool == ToolType.text) return;

    ref.read(pdfEngineProvider.notifier).addTrazo(widget.pageNumber, _currentTrazo!);
    setState(() {
      _currentTrazo = null;
    });
  }
  
  void _handlePointerCancel(PointerCancelEvent event, PdfEngineState state) {
    _activePointers--;
    if (_activePointers < 0) _activePointers = 0;
    setState(() => _currentTrazo = null);
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
                painter: _AnnotationPainter(trazosToDraw),
              ),
            ),
          ),
        ),

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

  _AnnotationPainter(this.trazos);

  @override
  void paint(Canvas canvas, Size size) {
    // Aislar la capa para que el BlendMode.clear del borrador no perfore toda la pantalla
    canvas.saveLayer(Offset.zero & size, Paint());

    for (var trazo in trazos) {
      if (trazo.oculto) continue;

      if (trazo.tool == ToolType.text && trazo.texto != null && trazo.pos != null) {
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

      if (trazo.points.length < 2) continue;

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
    
    // Restaurar la capa
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
