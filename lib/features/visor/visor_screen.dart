import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math'; // For layoutPages max()
import 'package:repertorio_bc/core/pdf/pdf_engine.dart';
import 'package:repertorio_bc/models/trazo.dart';
import 'package:repertorio_bc/features/visor/widgets/annotation_layer.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:repertorio_bc/core/midi/midi_engine.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';


const List<double> _kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

class VisorScreen extends ConsumerStatefulWidget {
  final String cantoId;
  const VisorScreen({super.key, required this.cantoId});

  @override
  ConsumerState<VisorScreen> createState() => _VisorScreenState();
}

class _VisorScreenState extends ConsumerState<VisorScreen> {
  bool _showTopBar = true;
  bool _showTools = false;
  bool _showMidi = false;
  bool _showDrawingPalette = false;

  final MidiEngine _midi = MidiEngine();
  bool _hasMidi = false;
  
  final PdfViewerController _pdfController = PdfViewerController();
  Orientation? _lastOrientation;
  double _minScaleLimit = 0.1;

  @override
  void initState() {
    super.initState();
    _initMidi();
  }

  void _initMidi() async {
    final cantos = ref.read(cantosBaseProvider).value ?? [];
    final canto = cantos.firstWhere(
      (c) => c.id == widget.cantoId,
      orElse: () => Canto(id: '', nombre: 'Partitura', archivo: '', temas: [], corosVinculados: []),
    );

    debugPrint('🎵 [MidiEngine] Inicializando para el canto: ${canto.nombre}');
    debugPrint('🎵 [MidiEngine] midiArchivo del canto: "${canto.midiArchivo}"');
    
    if (canto.midiArchivo == null || canto.midiArchivo!.isEmpty) {
      debugPrint('🎵 [MidiEngine] Este canto no tiene archivo MIDI asignado.');
      return;
    }

    setState(() {
      _hasMidi = true;
    });

    final dir = await getApplicationDocumentsDirectory();
    final localMidi = File('${dir.path}/${canto.id}.mid');
    debugPrint('🎵 [NativeMidiEngine] Ruta esperada para el archivo MIDI: ${localMidi.path}');
    
    if (await localMidi.exists()) {
      debugPrint('🎵 [NativeMidiEngine] ¡El archivo MIDI existe localmente! Cargándolo...');
      _midi.loadMidi(localMidi.path, canto.nombre);
    } else {
      debugPrint('🎵 [NativeMidiEngine] El archivo MIDI NO existe localmente. Esperando descarga...');
      _esperarDescargaMidi(localMidi.path, canto.nombre);
    }
  }

  Future<void> _esperarDescargaMidi(String path, String nombre) async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final fileExists = await File(path).exists();
      debugPrint('🎵 [NativeMidiEngine] Intento ${i + 1}/20: ¿Existe el archivo MIDI? $fileExists');
      if (fileExists) {
        debugPrint('🎵 [NativeMidiEngine] ¡El archivo MIDI se ha descargado y detectado! Cargándolo...');
        _midi.loadMidi(path, nombre);
        return;
      }
    }
    debugPrint('🎵 [MidiEngine] Agotado el tiempo de espera (20s) y el archivo MIDI no apareció.');
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  void _toggleTopBar() {
    final state = ref.read(pdfEngineProvider);
    if (state.isDrawingMode || _showMidi) return;
    setState(() {
      _showTopBar = !_showTopBar;
    });
  }

  void _toggleTools() {
    setState(() {
      _showTools = !_showTools;
      if (!_showTools) {
        _showDrawingPalette = false;
        ref.read(pdfEngineProvider.notifier).setDrawingMode(false);
      }
    });
  }

  void _toggleMidi() {
    setState(() {
      _showMidi = !_showMidi;
    });
  }

  Future<void> _enviarSenalVivo(Canto canto, String coroId) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transmitiendo "${canto.nombre}" a la sede...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      await SupabaseService.client.from('avisos').insert({
        'coro_id': coroId,
        'tipo': 'VIVO',
        'mensaje': canto.nombre,
        'metadata': {'id_canto': canto.id}
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al transmitir: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }


  void _ajustarZoomAlAncho() {
    if (_pdfController.isReady) {
      final matrix = _pdfController.calcMatrixFitWidthForPage(pageNumber: _pdfController.pageNumber ?? 1);
      if (matrix != null) {
        _pdfController.value = matrix;
      }
    }
  }

  void _calcularLimiteEscala(PdfDocument document) {
    if (document.pages.isNotEmpty) {
      final firstPageWidth = document.pages.first.width;
      final viewWidth = MediaQuery.of(context).size.width;
      setState(() {
        _minScaleLimit = (viewWidth / firstPageWidth);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfEngineProvider);
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeProvider);
    final accentColor = ref.watch(accentColorProvider);
    final isCarousel = ref.watch(pdfNavModeProvider);
    final cantos = ref.watch(cantosBaseProvider).value ?? [];
    final canto = cantos.firstWhere(
      (c) => c.id == widget.cantoId,
      orElse: () => Canto(id: '', nombre: 'Partitura', archivo: '', temas: [], corosVinculados: []),
    );

    final perfil = ref.watch(perfilProvider).value;
    final isDirector = perfil != null && ['director', 'director_estatal', 'superadmin', 'subdirector'].contains(perfil.rol);

    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != null && _lastOrientation != orientation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pdfController.isReady && _pdfController.pages.isNotEmpty) {
          final firstPageWidth = _pdfController.pages.first.width;
          final viewWidth = MediaQuery.of(context).size.width;
          setState(() {
            _minScaleLimit = (viewWidth / firstPageWidth);
          });
          _ajustarZoomAlAncho();
        }
      });
    }
    _lastOrientation = orientation;

    // Evaluamos el brillo del sistema directamente, ya que el modo "Sepia" ahora delega en el SO el cambio a oscuro (Quiet)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSepiaProfile = themeMode == AppThemeMode.sepia || themeMode == AppThemeMode.quiet;

    // Filtro para modo oscuro (Quiet) que mapea el fondo blanco a gris oscuro y notas a claro
    const quietFilter = ColorFilter.matrix([
      -0.65098,  0.0,       0.0,       0.0, 226.0,
       0.0,     -0.66275,   0.0,       0.0, 232.0,
       0.0,      0.0,      -0.68235,   0.0, 240.0,
       0.0,      0.0,       0.0,       1.0,   0.0,
    ]);

    // Filtro original en negativo (para tema oscuro normal)
    const invertFilter = ColorFilter.matrix([
      -1.0,  0.0,  0.0, 0.0, 255.0,
       0.0, -1.0,  0.0, 0.0, 255.0,
       0.0,  0.0, -1.0, 0.0, 255.0,
       0.0,  0.0,  0.0, 1.0,   0.0,
    ]);

    // Filtro sepia para la partitura en modo sepia (blanco -> #F4ECD8, negro -> #5b4636)
    const sepiaFilter = ColorFilter.matrix([
      0.60000, 0.0,     0.0,     0.0, 91.0,
      0.0,     0.65098, 0.0,     0.0, 70.0,
      0.0,     0.0,     0.63529, 0.0, 54.0,
      0.0,     0.0,     0.0,     1.0, 0.0,
    ]);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [

            Column(
              children: [
                // ── Top Bar ─────────────────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  height: _showTopBar ? 60 : 0,
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                  ),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                            onPressed: () => context.pop(),
                          ),
                          Expanded(
                            child: Text(
                              canto.nombre,
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_hasMidi)
                            _TopBarBtn(
                              icon: Icons.piano_rounded,
                              isActive: _showMidi,
                              activeColor: accentColor,
                              onTap: _toggleMidi,
                              tooltip: 'Reproductor MIDI',
                            ),
                          if (isDirector && perfil.coroId.isNotEmpty)
                            _TopBarBtn(
                              icon: Icons.cell_tower_rounded,
                              isActive: false,
                              onTap: () => _enviarSenalVivo(canto, perfil.coroId),
                              tooltip: 'Transmitir en VIVO al coro',
                            ),
                          if (!Platform.isIOS)
                            _TopBarBtn(
                              icon: Icons.ios_share_rounded,
                              isActive: false,
                              onTap: () => ref.read(pdfEngineProvider.notifier).exportPdf(canto.nombre),
                              tooltip: 'Exportar PDF',
                            ),
                          _TopBarBtn(
                            icon: _showTools ? Icons.edit_off_rounded : Icons.edit_rounded,
                            isActive: _showTools,
                            onTap: _toggleTools,
                            tooltip: 'Herramientas de dibujo',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── PDF Viewer ───────────────────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _toggleTopBar,
                        child: state.isLoading
                            ? _LoadingPlaceholder()
                            : state.error != null
                                ? Center(child: Text(state.error!))
                                : ColorFiltered(
                                    colorFilter: isDark 
                                        ? (isSepiaProfile ? quietFilter : invertFilter) 
                                        : (isSepiaProfile ? sepiaFilter : const ColorFilter.mode(Colors.transparent, BlendMode.multiply)),
                                    child: PdfViewer.file(
                                      state.localPath!,
                                      key: ValueKey('${state.localPath}_${File(state.localPath!).existsSync() ? File(state.localPath!).lastModifiedSync().millisecondsSinceEpoch : 0}'),
                                      controller: _pdfController,
                                      params: PdfViewerParams(
                                        enableTextSelection: false,
                                        minScale: _minScaleLimit,
                                        boundaryMargin: EdgeInsets.zero,
                                        onViewerReady: (document, controller) {
                                          _calcularLimiteEscala(document);
                                          _ajustarZoomAlAncho();
                                        },
                                        panEnabled: !state.isDrawingMode,
                                        scaleEnabled: true,
                                        layoutPages: isCarousel ? (pages, params) {
                                          final height = pages.fold(0.0, (prev, page) => max(prev, page.height)) + params.margin * 2;
                                          final pageLayouts = <Rect>[];
                                          double x = params.margin;
                                          for (final page in pages) {
                                            pageLayouts.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
                                            x += page.width + params.margin;
                                          }
                                          return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
                                        } : null,
                                        backgroundColor: Colors.white,
                                        pageDropShadow: null,
                                        pageOverlaysBuilder: (context, pageRect, page) => [
                                          Positioned.fill(
                                            child: AnnotationLayer(
                                              cantoId: widget.cantoId,
                                              pageNumber: page.pageNumber,
                                              pageSize: Size(pageRect.width, pageRect.height),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                      ),

                      // ── Panel MIDI Flotante ──────────────────────────────
                      // NOTA: Se mueve a -380 cuando está cerrado para asegurar que no se asome
                      // de manera poco profesional en pantallas cortas o con partituras de una página.
                      StreamBuilder<MidiState>(
                        stream: _midi.stateStream,
                        initialData: _midi.state,
                        builder: (context, snapshot) {
                          final currentMidiState = snapshot.data ?? _midi.state;
                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOutCubic,
                            bottom: _showMidi ? (16 + MediaQuery.of(context).padding.bottom) : -380,
                            left: 12,
                            right: 12,
                            child: _MidiPanel(
                              midiState: currentMidiState,
                              onPlay: () { currentMidiState.isPlaying ? _midi.pause() : _midi.play(); },
                              onStop: _midi.stop,
                              onSeek: _midi.seek,
                              onSpeedChange: _midi.setSpeed,
                              onMetronomo: _midi.toggleMetronomo,
                              onVozToggle: (trackIndex, muted) => _midi.setTrackMute(trackIndex, muted),
                              onVozSolo: (soloTrackIndex) {
                                // Activar solo la voz seleccionada y mutear las demás
                                for (var v in currentMidiState.voces) {
                                  final shouldMute = v.trackIndex != soloTrackIndex;
                                  _midi.setTrackMute(v.trackIndex, shouldMute);
                                }
                              },
                              isLoaded: currentMidiState.isLoaded,
                              isReady: currentMidiState.isReady,
                              accentColor: accentColor,
                            ),
                          );
                        },
                      ),

                      // ── Panel Herramientas de Dibujo ─────────────────────
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        bottom: _showTools ? 20 : -100,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ToolBtn(icon: Icons.pan_tool_rounded, isActive: !state.isDrawingMode, onTap: () => ref.read(pdfEngineProvider.notifier).setDrawingMode(false)),
                                  Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 5)),
                                  _ToolBtn(
                                    icon: Icons.edit_rounded,
                                    isActive: state.isDrawingMode && state.currentTool == ToolType.pencil,
                                    onTap: () { 
                                      final e = ref.read(pdfEngineProvider.notifier); 
                                      e.setDrawingMode(true); 
                                      e.setTool(ToolType.pencil); 
                                      setState(() => _showDrawingPalette = false);
                                    },
                                    onDoubleTap: () {
                                      final e = ref.read(pdfEngineProvider.notifier); 
                                      e.setDrawingMode(true); 
                                      e.setTool(ToolType.pencil);
                                      setState(() => _showDrawingPalette = !_showDrawingPalette);
                                    },
                                  ),
                                  _ToolBtn(
                                    icon: Icons.text_fields_rounded,
                                    isActive: state.isDrawingMode && state.currentTool == ToolType.text,
                                    onTap: () { 
                                      final e = ref.read(pdfEngineProvider.notifier); 
                                      e.setDrawingMode(true); 
                                      e.setTool(ToolType.text); 
                                      setState(() => _showDrawingPalette = false);
                                    }
                                  ),
                                  _ToolBtn(
                                    icon: Icons.cleaning_services_rounded,
                                    isActive: state.isDrawingMode && state.currentTool == ToolType.eraser,
                                    onTap: () { 
                                      final e = ref.read(pdfEngineProvider.notifier); 
                                      e.setDrawingMode(true); 
                                      e.setTool(ToolType.eraser); 
                                      setState(() => _showDrawingPalette = false);
                                    },
                                    onDoubleTap: () {
                                      final e = ref.read(pdfEngineProvider.notifier); 
                                      e.setDrawingMode(true); 
                                      e.setTool(ToolType.eraser);
                                      setState(() => _showDrawingPalette = !_showDrawingPalette);
                                    },
                                  ),
                                  if (state.isDrawingMode) ...[
                                    Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 5)),
                                    _ToolBtn(
                                      icon: Icons.undo_rounded,
                                      isActive: false,
                                      onTap: () => ref.read(pdfEngineProvider.notifier).undo(),
                                    ),
                                    _ToolBtn(
                                      icon: Icons.redo_rounded,
                                      isActive: false,
                                      onTap: () => ref.read(pdfEngineProvider.notifier).redo(),
                                    ),
                                    _ToolBtn(
                                      icon: Icons.delete_sweep_rounded,
                                      isActive: false,
                                      onTap: () => ref.read(pdfEngineProvider.notifier).clearAllGlobal(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // ── Paleta de Dibujo Flotante (Grosor y Color) ─────────
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        bottom: (_showTools && _showDrawingPalette) ? 75 : -100,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Slider de grosor
                                  SizedBox(
                                    width: 100,
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                        trackHeight: 2,
                                        activeTrackColor: accentColor,
                                        inactiveTrackColor: Colors.grey.withOpacity(0.3),
                                        thumbColor: accentColor,
                                      ),
                                      child: Slider(
                                        value: state.currentTool == ToolType.eraser ? state.eraserSize : state.currentSize,
                                        min: 1.0,
                                        max: state.currentTool == ToolType.eraser ? 40.0 : 15.0,
                                        onChanged: (val) => ref.read(pdfEngineProvider.notifier).setCurrentSize(val),
                                      ),
                                    ),
                                  ),
                                  
                                  // Selector de colores solo si no es borrador
                                  if (state.currentTool != ToolType.eraser) ...[
                                    Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 10)),
                                    _ColorBtn(color: Colors.black, isActive: state.currentColor == Colors.black, onTap: () => ref.read(pdfEngineProvider.notifier).setCurrentColor(Colors.black)),
                                    _ColorBtn(color: Colors.red, isActive: state.currentColor == Colors.red, onTap: () => ref.read(pdfEngineProvider.notifier).setCurrentColor(Colors.red)),
                                    _ColorBtn(color: Colors.blue, isActive: state.currentColor == Colors.blue, onTap: () => ref.read(pdfEngineProvider.notifier).setCurrentColor(Colors.blue)),
                                    _ColorBtn(color: Colors.white, isActive: state.currentColor == Colors.white, onTap: () => ref.read(pdfEngineProvider.notifier).setCurrentColor(Colors.white)),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MIDI Panel — Reproductor completo
// ══════════════════════════════════════════════════════════════════════════════
class _MidiPanel extends StatefulWidget {
  final MidiState midiState;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final void Function(double) onSeek;
  final void Function(double) onSpeedChange;
  final VoidCallback onMetronomo;
  final void Function(int, bool) onVozToggle;
  final void Function(int) onVozSolo;
  final bool isLoaded;
  final bool isReady;
  final Color accentColor;

  const _MidiPanel({
    required this.midiState,
    required this.onPlay,
    required this.onStop,
    required this.onSeek,
    required this.onSpeedChange,
    required this.onMetronomo,
    required this.onVozToggle,
    required this.onVozSolo,
    required this.isLoaded,
    required this.isReady,
    required this.accentColor,
  });

  @override
  State<_MidiPanel> createState() => _MidiPanelState();
}

class _MidiPanelState extends State<_MidiPanel> {
  bool _showSettings = false;

  String _formatTime(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool loading = !widget.isReady || !widget.isLoaded;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black.withOpacity(0.2),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.accentColor.withOpacity(0.4)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicador metrónomo (flash en cada beat)
            Row(
              children: [
                Icon(Icons.piano_rounded, color: widget.accentColor, size: 18),
                const SizedBox(width: 8),
                Text('Reproductor', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: widget.accentColor)),
                const Spacer(),
                // Metrónomo Visual (Row de bolitas)
                if (widget.midiState.metronomoActivo && widget.midiState.beatIndex != null && widget.midiState.beatNumerator != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.midiState.beatNumerator!, (index) {
                      final isCurrent = index == widget.midiState.beatIndex;
                      final isFirst = index == 0;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent 
                              ? (isFirst ? Colors.redAccent : widget.accentColor)
                              : Colors.grey.withOpacity(0.3),
                          boxShadow: isCurrent 
                              ? [
                                  BoxShadow(
                                    color: isFirst 
                                        ? Colors.redAccent.withOpacity(0.5) 
                                        : widget.accentColor.withOpacity(0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ]
                              : [],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 12),
                ],
                if (!widget.isReady)
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor),
                  ),
                // Botón Ajustes
                IconButton(
                  onPressed: () => setState(() => _showSettings = !_showSettings),
                  icon: Icon(
                    _showSettings ? Icons.keyboard_arrow_up_rounded : Icons.settings_rounded,
                    color: _showSettings ? widget.accentColor : Colors.grey.withOpacity(0.8),
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Barra de progreso ──────────────────────────────────────────
            Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: widget.accentColor,
                    inactiveTrackColor: widget.accentColor.withOpacity(0.2),
                    thumbColor: widget.accentColor,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: widget.midiState.progress.clamp(0.0, 1.0),
                    onChanged: loading ? null : (v) => widget.onSeek(v * 100),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(widget.midiState.tiempoActual), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                      Text(_formatTime(widget.midiState.tiempoTotal), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Controles principales ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Metrónomo toggle
                 _GoldIconBtn(
                  isActive: widget.midiState.metronomoActivo,
                  activeColor: widget.accentColor,
                  onTap: loading ? null : widget.onMetronomo,
                  tooltip: 'Metrónomo',
                  size: 22,
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 150),
                    tween: Tween<double>(
                      begin: 0.0,
                      end: widget.midiState.metronomoActivo && widget.midiState.isPlaying 
                          ? ((widget.midiState.beatIndex ?? 0) % 2 == 0 ? -0.3 : 0.3) 
                          : 0.0,
                    ),
                    builder: (context, angle, child) {
                      return MetronomeIcon(
                        color: widget.midiState.metronomoActivo ? widget.accentColor : Colors.grey.withOpacity(0.6),
                        size: 20,
                        rotationAngle: angle,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Play / Pause
                GestureDetector(
                  onTap: loading ? null : widget.onPlay,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: loading ? Colors.grey.withOpacity(0.2) : widget.accentColor,
                      boxShadow: loading ? [] : [BoxShadow(color: widget.accentColor.withOpacity(0.4), blurRadius: 12)],
                    ),
                    child: loading
                        ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Icon(
                            widget.midiState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 28,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Stop
                _GoldIconBtn(
                  icon: Icons.stop_rounded,
                  isActive: false,
                  activeColor: widget.accentColor,
                  onTap: loading ? null : widget.onStop,
                  tooltip: 'Detener',
                  size: 22,
                ),
              ],
            ),
            
            // Sección Expandible de Ajustes
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              child: _showSettings 
                  ? Column(
                      children: [
                        const SizedBox(height: 16),
                        // ── Selector de velocidad ──────────────────────────────────────
                        Row(
                          children: [
                            Icon(Icons.speed_rounded, size: 16, color: Colors.grey.withOpacity(0.8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _kSpeeds.map((s) {
                                    final active = (widget.midiState.speed - s).abs() < 0.05;
                                    return GestureDetector(
                                      onTap: loading ? null : () => widget.onSpeedChange(s),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: active ? widget.accentColor : widget.accentColor.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: active ? widget.accentColor : widget.accentColor.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          '${s}x',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: active ? Colors.white : widget.accentColor,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Voces (SATB) ──────────────────────────────────────────────
                        if (widget.midiState.voces.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.people_rounded, size: 16, color: Colors.grey.withOpacity(0.8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      // Botón para activar todas las voces rápidamente (Ensamble)
                                      GestureDetector(
                                        onTap: () {
                                          for (var v in widget.midiState.voces) {
                                            if (!v.activa) {
                                              widget.onVozToggle(v.trackIndex, false); // false = unmute (activa)
                                            }
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: widget.accentColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: widget.accentColor),
                                          ),
                                          child: Text(
                                            'Todos',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: widget.accentColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ...widget.midiState.voces.map((voz) {
                                        return GestureDetector(
                                          onTap: () {
                                            if (voz.activa) {
                                              // Prevenir mutear todas las voces (debe quedar al menos una)
                                              final activeCount = widget.midiState.voces.where((v) => v.activa).length;
                                              if (activeCount <= 1) return;
                                            }
                                            widget.onVozToggle(voz.trackIndex, voz.activa);
                                          },
                                          onLongPress: () => widget.onVozSolo(voz.trackIndex),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            margin: const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: voz.activa ? widget.accentColor : Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: voz.activa ? widget.accentColor : Colors.grey.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Text(
                                              voz.nombre,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: voz.activa ? Colors.white : Colors.grey,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ══════════════════════════════════════════════════════════════════════════════
class _LoadingPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 60, color: Colors.grey)
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 1500.ms, color: theme.colorScheme.primary.withOpacity(0.5))
              .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms, curve: Curves.easeInOutSine)
              .then()
              .scaleXY(begin: 1.05, end: 0.95, duration: 1500.ms, curve: Curves.easeInOutSine),
          const SizedBox(height: 20),
          Text('Preparando partitura...', style: GoogleFonts.inter(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500))
              .animate(onPlay: (c) => c.repeat())
              .fade(duration: 1500.ms, begin: 0.4, end: 1.0)
              .then()
              .fade(duration: 1500.ms, begin: 1.0, end: 0.4),
        ],
      ),
    );
  }
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;
  final String tooltip;

  const _TopBarBtn({required this.icon, required this.isActive, this.activeColor, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = activeColor ?? theme.colorScheme.primary;
    return IconButton(
      icon: Icon(icon, color: isActive ? color : Colors.grey),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }
}

class _GoldIconBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final Color activeColor;

  const _GoldIconBtn({
    this.icon,
    this.child,
    required this.isActive,
    this.onTap,
    required this.tooltip,
    this.size = 20,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Colors.grey.withOpacity(0.6);
    
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.15) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: child ?? Icon(
            icon,
            size: size,
            color: isActive ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }
}

// ─── ICONO PERSONALIZADO DE METRÓNOMO (CustomPainter) ────────────────────────
class MetronomePainter extends CustomPainter {
  final Color color;
  final double rotationAngle;
  const MetronomePainter({required this.color, this.rotationAngle = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. Dibujar el cuerpo (trapezoide del metrónomo)
    final path = Path()
      ..moveTo(size.width * 0.35, size.height * 0.15)
      ..lineTo(size.width * 0.65, size.height * 0.15)
      ..lineTo(size.width * 0.85, size.height * 0.85)
      ..lineTo(size.width * 0.15, size.height * 0.85)
      ..close();
    canvas.drawPath(path, paint);

    // 2. Dibujar el péndulo / varilla inclinada
    canvas.save();
    // Move pivot point to the bottom center of the metronome
    canvas.translate(size.width * 0.5, size.height * 0.8);
    canvas.rotate(rotationAngle);
    
    // Draw needle straight up
    canvas.drawLine(
      Offset.zero,
      Offset(0, -size.height * 0.5),
      paint,
    );

    // 3. Dibujar la pesa del péndulo
    canvas.drawCircle(Offset(0, -size.height * 0.35), 3, fillPaint);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MetronomePainter oldDelegate) => 
      oldDelegate.rotationAngle != rotationAngle || oldDelegate.color != color;
}

class MetronomeIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double rotationAngle;
  const MetronomeIcon({
    super.key, 
    required this.color, 
    this.size = 22,
    this.rotationAngle = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: MetronomePainter(color: color, rotationAngle: rotationAngle),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _ToolBtn({required this.icon, required this.isActive, required this.onTap, this.onDoubleTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: isActive ? theme.colorScheme.primary : Colors.grey),
      ),
    );
  }
}

class _ColorBtn extends StatelessWidget {
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _ColorBtn({required this.color, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = color == Colors.white ? Colors.grey : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              if (isActive) BoxShadow(color: theme.colorScheme.primary.withOpacity(0.5), blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}
