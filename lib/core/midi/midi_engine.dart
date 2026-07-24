import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:audioplayers/audioplayers.dart';
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
class MidiEngine with WidgetsBindingObserver {
  static final MidiEngine _instance = MidiEngine._internal();
  factory MidiEngine() => _instance;
  MidiEngine._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _midiPro = MidiPro();
  final _metronomePlayer = AudioPlayer();

  ParsedMidiSong? _song;
  Timer? _playbackTimer;
  final Stopwatch _stopwatch = Stopwatch();
  double _startOffsetSeconds = 0.0;
  final Set<int> _playedNoteIndices = {};
  final Map<int, bool> _mutedTracks = {}; // trackIndex -> isMuted

  // Metrónomo
  bool _metronomeInitialized = false;
  double _lastBeatTime = -1.0;
  int _currentBeatIndex = 0;
  static const int _beatsPerMeasure = 4;

  // Control de Note-Off:
  // - _noteGeneration[pitch]: contador de instancias por nota. Permite re-disparar
  //   la misma nota sin que el "stop" programado de la instancia anterior la corte.
  // - _playbackEpoch: se incrementa en pause/stop/seek para invalidar los stops
  //   pendientes que ya no corresponden a la reproducción actual.
  final Map<int, int> _noteGeneration = {};
  int _playbackEpoch = 0;

  // StreamController broadcast: no lo cerramos en dispose() porque el singleton
  // vive toda la sesión y cerrarlo rompería el stream para siempre.
  final StreamController<MidiState> _stateController = StreamController<MidiState>.broadcast();
  Stream<MidiState> get stateStream => _stateController.stream;

  MidiState _state = const MidiState(isReady: true);
  MidiState get state => _state;

  void _emit(MidiState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // Compatibilidad hacia atrás: ya no requiere WebView
  dynamic buildController() => null;

  // ── Manejo del ciclo de vida de la app (iOS background audio) ──────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (!Platform.isIOS) return;
    if (appState == AppLifecycleState.resumed) {
      _reinitAudioAfterResume();
    }
  }

  /// Al regresar del background en iOS, AVFoundation puede haber invalidado
  /// la sesión de audio. Reinicializamos el SoundFont si hay un canto cargado
  /// para restaurar el sonido del piano.
  Future<void> _reinitAudioAfterResume() async {
    if (_song == null) return;
    debugPrint('🎵 [MidiEngine] iOS resume — reinicializando SoundFont...');
    try {
      // Reactivar la sesión de audio de iOS
      AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
      // Recargar el SoundFont para restaurar FluidSynth
      await _midiPro.loadSoundfont(
        sf2Path: 'assets/Piano.sf2',
        instrumentIndex: 0,
      );
      debugPrint('🎵 [MidiEngine] SoundFont restaurado tras resume ✓');
    } catch (e) {
      debugPrint('❌ [MidiEngine] Error restaurando audio tras resume: $e');
    }
  }

  /// Inicializa el motor de audio nativo cargando el SoundFont desde los assets
  /// de Flutter. Debe llamarse una sola vez antes de reproducir.
  Future<void> initAudio() async {
    if (_midiPro.initialized) return;
    try {
      debugPrint('🎵 [NativeMidiEngine] Cargando SoundFont desde assets...');
      await _midiPro.loadSoundfont(
        sf2Path: 'assets/Piano.sf2',
        instrumentIndex: 0,
      );
      debugPrint('🎵 [NativeMidiEngine] SoundFont cargado ✓ — Piano Acústico activo');
    } catch (e, st) {
      debugPrint('❌ [NativeMidiEngine] Error cargando SoundFont: $e\n$st');
    }

    // Inicializar metrónomo
    if (!_metronomeInitialized) {
      try {
        // En iOS, asegurar que el audio suene aunque el switch físico esté en silencio
        if (Platform.isIOS) {
          AudioPlayer.global.setAudioContext(AudioContext(
            iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
          ));
        }
        await _metronomePlayer.setPlayerMode(PlayerMode.lowLatency);
        await _metronomePlayer.setReleaseMode(ReleaseMode.stop);
        await _metronomePlayer.setSourceAsset('audio/metro/wood-hi.mp3');
        _metronomeInitialized = true;
        debugPrint('🎵 [NativeMidiEngine] Metrónomo inicializado ✓');
      } catch (e) {
        debugPrint('❌ [NativeMidiEngine] Error inicializando metrónomo: $e');
      }
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
    _playbackEpoch++; // Invalidar stops pendientes
    _stopAllNotes();
    _emit(_state.copyWith(isPlaying: false));
  }

  void stop() {
    _stopwatch.stop();
    _stopwatch.reset();
    _playbackTimer?.cancel();
    _startOffsetSeconds = 0.0;
    _playedNoteIndices.clear();
    _playbackEpoch++; // Invalidar stops pendientes
    _lastBeatTime = -1.0;
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

    // Cancelar timer y detener notas actuales
    _playbackTimer?.cancel();
    _stopwatch.stop();
    _stopAllNotes();

    // Actualizar posición
    _startOffsetSeconds = targetTime;
    _stopwatch.reset();
    _playedNoteIndices.clear();
    _playbackEpoch++; // Invalidar stops pendientes
    _lastBeatTime = -1.0;

    final total = _song!.durationSeconds;
    final progress = total > 0 ? (targetTime / total).clamp(0.0, 1.0) : 0.0;

    _emit(_state.copyWith(
      tiempoActual: targetTime,
      progress: progress,
      isPlaying: wasPlaying,
    ));

    // Reiniciar el loop de reproducción si estaba sonando
    if (wasPlaying) {
      _stopwatch.start();
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 20), _onTick);
    }
  }

  /// FIX: Cambio de velocidad sin re-disparar notas ya tocadas.
  ///
  /// Antes: pause() → play() limpiaba el epoch y el _startOffsetSeconds
  /// pero conservaba _playedNoteIndices, haciendo que al re-evaluar con
  /// la misma posición de tiempo se dispararan todas las notas de golpe.
  ///
  /// Ahora: capturamos la posición actual, cancelamos el timer, actualizamos
  /// el offset y la velocidad sin tocar _playedNoteIndices, y reiniciamos
  /// el stopwatch. El epoch se incrementa para invalidar los Note-Off pendientes
  /// de la velocidad anterior.
  void setSpeed(double speed) {
    if (_state.isPlaying) {
      final currentTime = _getCurrentTimeSeconds();

      _stopwatch.stop();
      _playbackTimer?.cancel();
      _playbackEpoch++;    // Invalidar Note-Off pendientes de la velocidad anterior
      _stopAllNotes();

      // Preservar _playedNoteIndices — no limpiarlos evita el disparo masivo
      _startOffsetSeconds = currentTime;
      _stopwatch.reset();

      _emit(_state.copyWith(speed: speed, isPlaying: true));

      _stopwatch.start();
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 20), _onTick);
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

    // ── Metrónomo ──────────────────────────────────────────────────────
    if (_state.metronomoActivo && _song != null && _song!.tempoBpm > 0) {
      _playMetronome(currentTime);
    }

    // ── Notas MIDI ─────────────────────────────────────────────────────
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

  /// Reproduce el click del metrónomo en cada beat.
  void _playMetronome(double currentTime) {
    if (!_metronomeInitialized || _song == null) return;

    final bpm = _song!.tempoBpm;
    final secondsPerBeat = 60.0 / bpm;
    final beatTime = (currentTime / secondsPerBeat).floorToDouble();

    // Solo disparamos si cambiamos a un nuevo beat
    if (beatTime != _lastBeatTime) {
      _lastBeatTime = beatTime;
      _currentBeatIndex = beatTime.toInt() % _beatsPerMeasure;
      final isFirstBeat = _currentBeatIndex == 0;

      _emit(_state.copyWith(
        beatIndex: _currentBeatIndex,
        beatNumerator: _beatsPerMeasure,
        beatEsPrimero: isFirstBeat,
      ));

      // Reproducir sonido de click
      try {
        if (isFirstBeat) {
          _metronomePlayer.play(AssetSource('audio/metro/wood-hi.mp3'));
        } else {
          _metronomePlayer.play(AssetSource('audio/metro/wood-lo.mp3'));
        }
      } catch (e) {
        debugPrint('❌ [NativeMidiEngine] Error metrónomo: $e');
      }
    }
  }

  /// Reproduce una nota MIDI con Note-Off programado al final de su duración.
  ///
  /// El sistema de "generación" resuelve el staccato: si la misma nota se
  /// re-dispara antes de que termine la instancia anterior, el stop pendiente
  /// de la instancia vieja se ignora y solo cuenta el de la más reciente.
  /// El "epoch" invalida stops pendientes tras pause/stop/seek/setSpeed.
  void _playNativeNote(MidiNoteEvent note) {
    if (!_midiPro.initialized) return;
    try {
      final pitch = note.note;
      final epoch = _playbackEpoch;
      final gen = (_noteGeneration[pitch] ?? 0) + 1;
      _noteGeneration[pitch] = gen;

      // Re-disparo limpio: cortar la voz anterior de la misma altura para
      // evitar voces apiladas (sonido "golpeado" / saturado).
      _midiPro.stopMidiNote(midi: pitch);
      _midiPro.playMidiNote(midi: pitch, velocity: note.velocity);

      // Note-Off exactamente al final de la duración de la nota (ajustado
      // por velocidad de reproducción). Sin margen extra para no alargar
      // el sonido más allá de lo escrito en la partitura.
      final durMs = ((note.durationSeconds / _state.speed) * 1000).round().clamp(80, 30000);
      Future.delayed(Duration(milliseconds: durMs), () {
        if (!_midiPro.initialized) return;
        if (_playbackEpoch != epoch) return;       // hubo pause/stop/seek/setSpeed
        if (_noteGeneration[pitch] != gen) return; // nota re-disparada
        _midiPro.stopMidiNote(midi: pitch);
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

  /// Detiene la reproducción actual. NO cierra el stream (el singleton vive toda la sesión).
  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
    // El StreamController NO se cierra porque el singleton es compartido entre
    // múltiples instancias de VisorScreen. Cerrarlo rompe el stream para siempre.
  }
}
