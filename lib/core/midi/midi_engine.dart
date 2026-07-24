import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:repertorio_bc/core/midi/native_midi_parser.dart';

/// Estado público del motor de audio.
class MidiState {
  final bool isPlaying;
  final bool isLoaded;
  final bool isReady;
  final double progress; // 0.0 .. 1.0
  final double tiempoActual; // segundos
  final double tiempoTotal; // segundos
  final double speed;
  final bool metronomoActivo;
  final List<MidiVoz> voces;
  final int? beatIndex;
  final int? beatNumerator;
  final bool? beatEsPrimero;

  const MidiState({
    this.isPlaying = false,
    this.isLoaded = false,
    this.isReady = true,
    this.progress = 0.0,
    this.tiempoActual = 0.0,
    this.tiempoTotal = 0.0,
    this.speed = 1.0,
    this.metronomoActivo = false,
    this.voces = const [],
    this.beatIndex,
    this.beatNumerator,
    this.beatEsPrimero,
  });

  MidiState copyWith({
    bool? isPlaying, bool? isLoaded, bool? isReady,
    double? progress, double? tiempoActual, double? tiempoTotal,
    double? speed, bool? metronomoActivo, List<MidiVoz>? voces,
    int? beatIndex, int? beatNumerator, bool? beatEsPrimero,
  }) => MidiState(
    isPlaying: isPlaying ?? this.isPlaying,
    isLoaded: isLoaded ?? this.isLoaded,
    isReady: isReady ?? this.isReady,
    progress: progress ?? this.progress,
    tiempoActual: tiempoActual ?? this.tiempoActual,
    tiempoTotal: tiempoTotal ?? this.tiempoTotal,
    speed: speed ?? this.speed,
    metronomoActivo: metronomoActivo ?? this.metronomoActivo,
    voces: voces ?? this.voces,
    beatIndex: beatIndex ?? this.beatIndex,
    beatNumerator: beatNumerator ?? this.beatNumerator,
    beatEsPrimero: beatEsPrimero ?? this.beatEsPrimero,
  );
}

class MidiVoz {
  final int trackIndex;
  final String nombre;
  bool activa;

  MidiVoz({required this.trackIndex, required this.nombre, this.activa = true});
}

/// Motor de audio MIDI 100% Nativo en Flutter utilizando [MidiPro]
/// (FluidSynth en Android y AVFoundation/AudioUnits en iOS).
class MidiEngine {
  static final MidiEngine _instance = MidiEngine._internal();
  factory MidiEngine() => _instance;
  MidiEngine._internal();

  final _midiPro = MidiPro();

  ParsedMidiSong? _song;
  Timer? _playbackTimer;
  final Stopwatch _stopwatch = Stopwatch();
  double _startOffsetSeconds = 0.0;
  final Set<int> _playedNoteIndices = {};
  final Map<int, bool> _mutedTracks = {}; // trackIndex -> isMuted

  final _stateController = StreamController<MidiState>.broadcast();
  Stream<MidiState> get stateStream => _stateController.stream;

  MidiState _state = const MidiState(isReady: true);
  MidiState get state => _state;

  void _emit(MidiState s) {
    _state = s;
    _stateController.add(s);
  }

  // Compatibilidad hacia atrás: ya no requiere WebView
  dynamic buildController() => null;

  /// Inicializa el motor de audio nativo cargando el SoundFont desde los assets
  /// de Flutter. Debe llamarse una sola vez antes de reproducir.
  Future<void> initAudio() async {
    if (_midiPro.initialized) return;
    try {
      debugPrint('🎵 [NativeMidiEngine] Cargando SoundFont desde assets...');
      // loadSoundfont usa rootBundle internamente — el path debe ser el
      // asset key tal como está declarado en pubspec.yaml.
      await _midiPro.loadSoundfont(
        sf2Path: 'assets/Piano.sf2',
        instrumentIndex: 0, // Acoustic Grand Piano
      );
      debugPrint('🎵 [NativeMidiEngine] SoundFont cargado ✓ — Piano Acústico activo');
    } catch (e, st) {
      debugPrint('❌ [NativeMidiEngine] Error cargando SoundFont: $e\n$st');
    }
  }

  Future<void> loadMidi(String filePath, String nombre) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ [NativeMidiEngine] Archivo MIDI no encontrado: $filePath');
        return;
      }

      stop();

      // Aseguramos que el motor de audio esté listo antes de cargar
      await initAudio();

      final bytes = await file.readAsBytes();
      _song = NativeMidiParser.parse(bytes);

      _mutedTracks.clear();
      final voces = _song!.tracks.map((t) {
        _mutedTracks[t.index] = false;
        return MidiVoz(trackIndex: t.index, nombre: t.name, activa: true);
      }).toList();

      _startOffsetSeconds = 0.0;
      _playedNoteIndices.clear();

      _emit(_state.copyWith(
        isLoaded: true,
        isReady: true,
        isPlaying: false,
        progress: 0.0,
        tiempoActual: 0.0,
        tiempoTotal: _song!.durationSeconds,
        voces: voces,
      ));
      debugPrint('🎵 [NativeMidiEngine] MIDI cargado: "$nombre", duración: ${_song!.durationSeconds}s');
    } catch (e) {
      debugPrint('❌ [NativeMidiEngine] Error cargando MIDI: $e');
    }
  }

  void play() {
    if (_song == null || _state.isPlaying) return;

    _stopwatch.reset();
    _stopwatch.start();

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 20), _onTick);

    _emit(_state.copyWith(isPlaying: true));
  }

  void pause() {
    _stopwatch.stop();
    _startOffsetSeconds = _getCurrentTimeSeconds();
    _playbackTimer?.cancel();
    _stopAllNotes();
    _emit(_state.copyWith(isPlaying: false));
  }

  void stop() {
    _stopwatch.stop();
    _stopwatch.reset();
    _playbackTimer?.cancel();
    _startOffsetSeconds = 0.0;
    _playedNoteIndices.clear();
    _stopAllNotes();
    _emit(_state.copyWith(
      isPlaying: false,
      progress: 0.0,
      tiempoActual: 0.0,
    ));
  }

  void seek(double porcentaje) {
    if (_song == null) return;
    final targetTime = (porcentaje.clamp(0.0, 1.0)) * _song!.durationSeconds;
    final wasPlaying = _state.isPlaying;

    _stopwatch.stop();
    _stopAllNotes();

    _startOffsetSeconds = targetTime;
    _stopwatch.reset();

    _playedNoteIndices.clear();

    final total = _song!.durationSeconds;
    final progress = total > 0 ? (targetTime / total).clamp(0.0, 1.0) : 0.0;

    _emit(_state.copyWith(
      tiempoActual: targetTime,
      progress: progress,
    ));

    if (wasPlaying) {
      _stopwatch.start();
    }
  }

  void setSpeed(double speed) {
    if (_state.isPlaying) {
      pause();
      _emit(_state.copyWith(speed: speed));
      play();
    } else {
      _emit(_state.copyWith(speed: speed));
    }
  }

  void toggleMetronomo() {
    _emit(_state.copyWith(metronomoActivo: !_state.metronomoActivo));
  }

  void setTrackMute(int trackIndex, bool muted) {
    _mutedTracks[trackIndex] = muted;
    final updatedVoces = _state.voces.map((v) {
      if (v.trackIndex == trackIndex) {
        return MidiVoz(trackIndex: v.trackIndex, nombre: v.nombre, activa: !muted);
      }
      return v;
    }).toList();
    _emit(_state.copyWith(voces: updatedVoces));
  }

  double _getCurrentTimeSeconds() {
    return _startOffsetSeconds + (_stopwatch.elapsedMicroseconds / 1000000.0) * _state.speed;
  }

  void _onTick(Timer timer) {
    if (_song == null) return;

    final currentTime = _getCurrentTimeSeconds();
    final totalTime = _song!.durationSeconds;

    if (currentTime >= totalTime) {
      stop();
      return;
    }

    final progress = totalTime > 0 ? (currentTime / totalTime).clamp(0.0, 1.0) : 0.0;
    _emit(_state.copyWith(
      tiempoActual: currentTime,
      progress: progress,
    ));

    int noteGlobalIndex = 0;
    for (final track in _song!.tracks) {
      final isMuted = _mutedTracks[track.index] ?? false;
      for (final note in track.notes) {
        final idx = noteGlobalIndex++;
        if (!_playedNoteIndices.contains(idx) && currentTime >= note.timeSeconds) {
          _playedNoteIndices.add(idx);
          if (!isMuted) {
            _playNativeNote(note);
          }
        }
      }
    }
  }

  void _playNativeNote(MidiNoteEvent note) {
    if (!_midiPro.initialized) return;
    try {
      _midiPro.playMidiNote(
        midi: note.note,
        velocity: note.velocity,
      );
      final durMs = ((note.durationSeconds / _state.speed) * 1000).round();
      Future.delayed(Duration(milliseconds: durMs > 50 ? durMs : 50), () {
        if (_midiPro.initialized) {
          _midiPro.stopMidiNote(midi: note.note);
        }
      });
    } catch (e) {
      debugPrint('❌ [NativeMidiEngine] Error en playMidiNote: $e');
    }
  }

  void _stopAllNotes() {
    try {
      if (_midiPro.initialized) {
        _midiPro.stopAllMidiNotes();
      }
    } catch (_) {}
  }

  void dispose() {
    stop();
    _stateController.close();
  }
}
