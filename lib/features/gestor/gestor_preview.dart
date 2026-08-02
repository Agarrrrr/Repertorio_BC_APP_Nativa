import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
  const EnsemblePlayer({super.key, required this.canto});

  final Canto canto;

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
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.canto.nombre,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        const Text('Escucha el ensamble completo o aísla cada voz.'),
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
