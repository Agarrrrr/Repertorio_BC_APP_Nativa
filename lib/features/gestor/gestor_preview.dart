import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:repertorio_bc/core/midi/midi_engine.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/models/canto.dart';

class GestorPdfPreview extends StatefulWidget {
  const GestorPdfPreview({super.key, required this.canto});

  final Canto canto;

  @override
  State<GestorPdfPreview> createState() => _GestorPdfPreviewState();
}

class CatalogDetailScreen extends StatefulWidget {
  const CatalogDetailScreen({
    super.key,
    required this.canto,
    this.onAdd,
  });

  final Canto canto;
  final Future<void> Function()? onAdd;

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  late final Future<File> _pdf = OfflineFiles.ensurePdf(widget.canto);
  bool _adding = false;
  bool _added = false;
  bool _midiReady = false;
  Object? _assetError;

  @override
  void initState() {
    super.initState();
    _prepareAssets();
  }

  Future<void> _prepareAssets() async {
    try {
      await _pdf;
      if (widget.canto.midiArchivo?.isNotEmpty == true) {
        await OfflineFiles.ensureMidi(widget.canto);
        if (mounted) setState(() => _midiReady = true);
      }
    } catch (error) {
      if (mounted) setState(() => _assetError = error);
    }
  }

  Future<void> _add() async {
    final action = widget.onAdd;
    if (action == null || _adding) return;
    setState(() => _adding = true);
    try {
      await action();
      if (mounted) setState(() => _added = true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMidi = widget.canto.midiArchivo?.isNotEmpty == true;
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.canto.nombre, overflow: TextOverflow.ellipsis),
              Text(
                hasMidi ? 'Partitura y ensamble' : 'Vista previa de partitura',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            if (widget.onAdd != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  onPressed: _adding || _added ? null : _add,
                  icon: _adding
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_added ? Icons.check_rounded : Icons.add_rounded),
                  label: Text(_added ? 'Añadida' : 'Añadir'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pdf = _CatalogPdf(file: _pdf);
              final player = hasMidi && _midiReady
                  ? EnsemblePlayer(canto: widget.canto, compact: true)
                  : hasMidi
                      ? (_assetError == null
                          ? const Center(child: CircularProgressIndicator())
                          : _PreviewError(
                              message:
                                  'No fue posible cargar el ensamble.\n$_assetError',
                            ))
                      : const _NoEnsemble();
              if (constraints.maxWidth >= 850) {
                return Row(
                  children: [
                    Expanded(flex: 7, child: pdf),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 370, child: player),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(flex: hasMidi ? 6 : 1, child: pdf),
                  if (hasMidi) ...[
                    const Divider(height: 1),
                    Expanded(flex: 4, child: player),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CatalogPdf extends StatelessWidget {
  const _CatalogPdf({required this.file});

  final Future<File> file;

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
        future: file,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _PreviewError(
              message: 'No fue posible abrir el PDF.\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return PdfViewer.file(
            snapshot.data!.path,
            params: const PdfViewerParams(
              enableTextSelection: false,
              boundaryMargin: EdgeInsets.only(bottom: 24),
            ),
          );
        },
      );
}

class _NoEnsemble extends StatelessWidget {
  const _NoEnsemble();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off_outlined, size: 44),
              SizedBox(height: 10),
              Text(
                'Esta partitura todavía no tiene ensamble MIDI.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _GestorPdfPreviewState extends State<GestorPdfPreview> {
  late final Future<File> _file = OfflineFiles.ensurePdf(widget.canto);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.canto.nombre)),
      body: SafeArea(
        child: FutureBuilder<File>(
          future: _file,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _PreviewError(
                message: 'No fue posible abrir el PDF.\n${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return PdfViewer.file(
              snapshot.data!.path,
              params: const PdfViewerParams(
                enableTextSelection: false,
                boundaryMargin: EdgeInsets.only(bottom: 24),
              ),
            );
          },
        ),
      ),
    );
  }
}

class EnsemblePlayer extends StatefulWidget {
  const EnsemblePlayer({
    super.key,
    required this.canto,
    this.compact = false,
  });

  final Canto canto;
  final bool compact;

  @override
  State<EnsemblePlayer> createState() => _EnsemblePlayerState();
}

class _EnsemblePlayerState extends State<EnsemblePlayer> {
  final MidiEngine _engine = MidiEngine();
  StreamSubscription<MidiState>? _subscription;
  MidiState _state = const MidiState();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _engine.stateStream.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await OfflineFiles.ensureMidi(widget.canto);
      await _engine.initAudio();
      await _engine.loadMidi(file.path, widget.canto.nombre);
      if (mounted) setState(() => _state = _engine.state);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _engine.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _PreviewError(message: 'No fue posible cargar el MIDI.\n$_error');
    }
    if (!_state.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: EdgeInsets.all(widget.compact ? 14 : 20),
      children: [
        if (!widget.compact)
          Text(
            widget.canto.nombre,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        const SizedBox(height: 8),
        Text(
          widget.compact
              ? 'ENSAMBLE · escucha mientras revisas la partitura'
              : 'Escucha el ensamble completo o aísla cada voz.',
          style: widget.compact
              ? Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w800)
              : null,
        ),
        const SizedBox(height: 20),
        Slider(
          value: _state.progress.clamp(0, 1),
          onChanged: _engine.seek,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              iconSize: 34,
              onPressed: _state.isPlaying ? _engine.pause : _engine.play,
              icon: Icon(_state.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _engine.stop,
              icon: const Icon(Icons.stop_rounded),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Voces', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._state.voces.map(
          (voice) => SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(voice.nombre),
            value: voice.activa,
            onChanged: (enabled) =>
                _engine.setTrackMute(voice.trackIndex, !enabled),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: .75, label: Text('75%')),
            ButtonSegment(value: 1, label: Text('100%')),
            ButtonSegment(value: 1.25, label: Text('125%')),
          ],
          selected: {_state.speed},
          onSelectionChanged: (values) => _engine.setSpeed(values.first),
        ),
      ],
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: Colors.red.shade700),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
