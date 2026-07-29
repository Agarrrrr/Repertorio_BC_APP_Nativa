import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:repertorio_bc/core/midi/native_midi_parser.dart';

/// Estado pﾃｺblico del motor de audio.
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
  final int beatSerial;
  final bool? beatEsPrimero;
  final int? timeSignatureNumerator;
  final int? timeSignatureDenominator;

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
    this.beatSerial = 0,
    this.beatEsPrimero,
    this.timeSignatureNumerator,
    this.timeSignatureDenominator,
  });

  MidiState copyWith({
    bool? isPlaying,
    bool? isLoaded,
    bool? isReady,
    double? progress,
    double? tiempoActual,
    double? tiempoTotal,
    double? speed,
    bool? metronomoActivo,
    List<MidiVoz>? voces,
    int? beatIndex,
    int? beatNumerator,
    int? beatSerial,
    bool? beatEsPrimero,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
  }) =>
      MidiState(
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
        beatSerial: beatSerial ?? this.beatSerial,
        beatEsPrimero: beatEsPrimero ?? this.beatEsPrimero,
        timeSignatureNumerator:
            timeSignatureNumerator ?? this.timeSignatureNumerator,
        timeSignatureDenominator:
            timeSignatureDenominator ?? this.timeSignatureDenominator,
      );
}

class MidiVoz {
  final int trackIndex;
  final String nombre;
  bool activa;

  MidiVoz({required this.trackIndex, required this.nombre, this.activa = true});
}

class _ScheduledMidiNote {
  final int trackIndex;
  final MidiNoteEvent note;

  const _ScheduledMidiNote({
    required this.trackIndex,
    required this.note,
  });
}

/// Motor de audio MIDI 100% Nativo en Flutter utilizando [MidiPro]
/// (FluidSynth en Android y AVFoundation/AudioUnits en iOS).
class MidiEngine {
  static final MidiEngine _instance = MidiEngine._internal();
  factory MidiEngine() => _instance;
  MidiEngine._internal();

  final _midiPro = MidiPro();
  int? _sfId; // SoundfontSamplerId devuelto por loadSoundfontAsset en v4
  final _metronomeHighPlayer = AudioPlayer();
  final _metronomeLowPlayer = AudioPlayer();

  ParsedMidiSong? _song;
  Timer? _playbackTimer;
  final Stopwatch _stopwatch = Stopwatch();
  double _startOffsetSeconds = 0.0;
  List<_ScheduledMidiNote> _scheduledNotes = const [];
  int _playbackCursor = 0;
  int _lastProgressEmitMicros = 0;
  final Map<int, bool> _mutedTracks = {}; // trackIndex -> isMuted
  final Map<int, int> _trackChannels = {};

  // Metrﾃｳnomo
  bool _metronomeInitialized = false;
  String? _lastMetronomePulseKey;
  int _currentBeatIndex = 0;

  // Control de Note-Off por canal y altura. Cada lﾃｭnea coral mantiene su canal
  // para que dos voces en la misma nota no se corten ni se fusionen.
  // - _playbackEpoch: se incrementa en pause/stop/seek para invalidar los stops
  //   pendientes que ya no corresponden a la reproducciﾃｳn actual.
  final Map<int, int> _activeNoteCounts = {};
  int _playbackEpoch = 0;

  // StreamController broadcast: no lo cerramos en dispose() porque el singleton
  // vive toda la sesiﾃｳn y cerrarlo romperﾃｭa el stream para siempre.
  final StreamController<MidiState> _stateController =
      StreamController<MidiState>.broadcast();
  Stream<MidiState> get stateStream => _stateController.stream;

  /// Callback invocado cuando la canciﾃｳn actual termina de reproducirse
  /// (usado por el Jukebox para avanzar automﾃ｡ticamente al siguiente canto).
  void Function()? onSongComplete;

  MidiState _state = const MidiState(isReady: true);
  MidiState get state => _state;

  void _emit(MidiState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // Compatibilidad hacia atrﾃ｡s: ya no requiere WebView
  dynamic buildController() => null;

  /// Inicializa el motor de audio nativo cargando el SoundFont desde los assets
  /// de Flutter. Debe llamarse una sola vez antes de reproducir.
  Future<void> initAudio() async {
    if (!_midiPro.isInitialized) {
      try {
        debugPrint('七 [NativeMidiEngine] Inicializando sintetizador...');
        await _midiPro.init(sampleRate: 48000, bufferSize: 256, polyphony: 96);
        debugPrint('七 [NativeMidiEngine] Cargando SoundFont desde assets...');
        _sfId = await _midiPro.loadSoundfontAsset(
          assetPath: 'assets/Piano.sf2',
          bank: 0,
          program: 0,
        );
        await _configureMastering();
        // En iOS: reproducir aunque el switch fﾃｭsico estﾃｩ en silencio
        if (Platform.isIOS) {
          await _midiPro.configureAudioSession(
            category: AudioSessionCategory.playback,
            mixWithOthers: false,
          );
        }
        debugPrint(
            '七 [NativeMidiEngine] SoundFont cargado 笨・(sfId=$_sfId) 窶・Piano Acﾃｺstico activo');
      } catch (e, st) {
        debugPrint('笶・[NativeMidiEngine] Error cargando SoundFont: $e\n$st');
      }
    }

    // Inicializar metrﾃｳnomo
    if (!_metronomeInitialized) {
      try {
        // En iOS, asegurar que el audio suene aunque el switch fﾃｭsico estﾃｩ en silencio
        if (Platform.isIOS) {
          AudioPlayer.global.setAudioContext(AudioContext(
            iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
          ));
        }
        for (final player in [
          _metronomeHighPlayer,
          _metronomeLowPlayer,
        ]) {
          await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setReleaseMode(ReleaseMode.stop);
        }
        await _metronomeHighPlayer.setSourceAsset('audio/metro/wood-hi.mp3');
        await _metronomeLowPlayer.setSourceAsset('audio/metro/wood-lo.mp3');
        _metronomeInitialized = true;
        debugPrint('[NativeMidiEngine] Metrónomo inicializado');
      } catch (e) {
        debugPrint('笶・[NativeMidiEngine] Error inicializando metrﾃｳnomo: $e');
      }
    }
  }

  Future<void> loadMidi(String filePath, String nombre) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint(
            '笶・[NativeMidiEngine] Archivo MIDI no encontrado: $filePath');
        return;
      }

      stop();

      // Aseguramos que el motor de audio estﾃｩ listo antes de cargar
      await initAudio();

      final bytes = await file.readAsBytes();
      _song = NativeMidiParser.parse(bytes);
      _scheduledNotes = [
        for (final track in _song!.tracks)
          for (final note in track.notes)
            _ScheduledMidiNote(trackIndex: track.index, note: note),
      ]..sort(
          (a, b) => a.note.timeSeconds.compareTo(b.note.timeSeconds),
        );

      _mutedTracks.clear();
      _trackChannels.clear();
      final voces = _song!.tracks.map((t) {
        _mutedTracks[t.index] = false;
        return MidiVoz(trackIndex: t.index, nombre: t.name, activa: true);
      }).toList();
      await _configureVoiceChannels(_song!.tracks);
      final initialSignature = _song!.timeSignatures.first;
      final initialPattern = MidiMeterPattern.from(
        numerator: initialSignature.numerator,
        denominator: initialSignature.denominator,
        bpm: _song!.tempoChanges.first.bpm,
        metronomeClocks: initialSignature.metronomeClocks,
      );

      _startOffsetSeconds = 0.0;
      _playbackCursor = 0;
      _lastProgressEmitMicros = 0;

      _emit(_state.copyWith(
        isLoaded: true,
        isReady: true,
        isPlaying: false,
        progress: 0.0,
        tiempoActual: 0.0,
        tiempoTotal: _song!.durationSeconds,
        voces: voces,
        beatIndex: 0,
        beatNumerator: initialPattern.beatsPerMeasure,
        beatSerial: 0,
        beatEsPrimero: true,
        timeSignatureNumerator: initialSignature.numerator,
        timeSignatureDenominator: initialSignature.denominator,
      ));
      debugPrint(
          '七 [NativeMidiEngine] MIDI cargado: "$nombre", duraciﾃｳn: ${_song!.durationSeconds}s');
    } catch (e) {
      debugPrint('笶・[NativeMidiEngine] Error cargando MIDI: $e');
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
    _playbackCursor = 0;
    _lastProgressEmitMicros = 0;
    _playbackEpoch++; // Invalidar stops pendientes
    _lastMetronomePulseKey = null;
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

    // Actualizar posiciﾃｳn
    _startOffsetSeconds = targetTime;
    _stopwatch.reset();
    _playbackCursor = _firstNoteAtOrAfter(targetTime);
    _lastProgressEmitMicros = 0;
    _playbackEpoch++; // Invalidar stops pendientes
    _primeMetronomeAt(targetTime);

    final total = _song!.durationSeconds;
    final progress = total > 0 ? (targetTime / total).clamp(0.0, 1.0) : 0.0;

    _emit(_state.copyWith(
      tiempoActual: targetTime,
      progress: progress,
      isPlaying: wasPlaying,
    ));

    // Reiniciar el loop de reproducciﾃｳn si estaba sonando
    if (wasPlaying) {
      _stopwatch.start();
      _playbackTimer =
          Timer.periodic(const Duration(milliseconds: 20), _onTick);
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
    final enabled = !_state.metronomoActivo;
    if (enabled && !_metronomeInitialized) {
      unawaited(initAudio().then((_) {
        if (_state.metronomoActivo) {
          _primeMetronomeAt(_getCurrentTimeSeconds());
        }
      }));
    } else if (enabled) {
      _primeMetronomeAt(_getCurrentTimeSeconds());
    } else {
      _lastMetronomePulseKey = null;
    }
    _emit(_state.copyWith(metronomoActivo: enabled));
  }

  void setTrackMute(int trackIndex, bool muted) {
    _mutedTracks[trackIndex] = muted;
    final updatedVoces = _state.voces.map((v) {
      if (v.trackIndex == trackIndex) {
        return MidiVoz(
            trackIndex: v.trackIndex, nombre: v.nombre, activa: !muted);
      }
      return v;
    }).toList();
    _emit(_state.copyWith(voces: updatedVoces));
  }

  double _getCurrentTimeSeconds() {
    return _startOffsetSeconds +
        (_stopwatch.elapsedMicroseconds / 1000000.0) * _state.speed;
  }

  void _onTick(Timer timer) {
    if (_song == null) return;

    final currentTime = _getCurrentTimeSeconds();
    final totalTime = _song!.durationSeconds;

    if (currentTime >= totalTime) {
      stop();
      onSongComplete?.call();
      return;
    }

    final elapsedMicros = _stopwatch.elapsedMicroseconds;
    if (elapsedMicros - _lastProgressEmitMicros >= 50000) {
      _lastProgressEmitMicros = elapsedMicros;
      final progress =
          totalTime > 0 ? (currentTime / totalTime).clamp(0.0, 1.0) : 0.0;
      _emit(_state.copyWith(
        tiempoActual: currentTime,
        progress: progress,
      ));
    }

    // 笏笏 Metrﾃｳnomo 笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏
    if (_state.metronomoActivo && _song != null && _song!.tempoBpm > 0) {
      _playMetronome(currentTime);
    }

    // 笏笏 Notas MIDI 笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏
    while (_playbackCursor < _scheduledNotes.length &&
        _scheduledNotes[_playbackCursor].note.timeSeconds <= currentTime) {
      final scheduled = _scheduledNotes[_playbackCursor++];
      if (!(_mutedTracks[scheduled.trackIndex] ?? false)) {
        _playNativeNote(
          scheduled.note,
          _trackChannels[scheduled.trackIndex] ?? 0,
        );
      }
    }
  }

  int _firstNoteAtOrAfter(double timeSeconds) {
    var low = 0;
    var high = _scheduledNotes.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_scheduledNotes[middle].note.timeSeconds < timeSeconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _primeMetronomeAt(double currentTime) {
    _lastMetronomePulseKey = null;
    if (_song == null) return;
    _playMetronome(currentTime, playClick: false);
  }

  /// Reproduce el click respetando tempo, compﾃ｡s y unidad de pulso del MIDI.
  void _playMetronome(double currentTime, {bool playClick = true}) {
    if (!_metronomeInitialized || _song == null) return;

    final song = _song!;
    final tempo = _tempoAt(song, currentTime);
    final signature = _signatureAt(song, currentTime);
    final quarterPosition = (tempo.tick / song.ppq) +
        ((currentTime - tempo.timeSeconds) * tempo.bpm / 60.0);
    final signatureQuarter = signature.tick / song.ppq;

    final meterPattern = MidiMeterPattern.from(
      numerator: signature.numerator,
      denominator: signature.denominator,
      bpm: tempo.bpm,
      metronomeClocks: signature.metronomeClocks,
    );
    final elapsedQuarters =
        (quarterPosition - signatureQuarter).clamp(0.0, double.infinity);
    final pulse = meterPattern.pulseSerialAt(elapsedQuarters);
    final pulseKey = '${signature.tick}:$pulse';

    // Solo disparamos si cambiamos a un nuevo pulso musical.
    if (pulseKey != _lastMetronomePulseKey) {
      _lastMetronomePulseKey = pulseKey;
      _currentBeatIndex = pulse % meterPattern.beatsPerMeasure;
      final isFirstBeat = _currentBeatIndex == 0;

      _emit(_state.copyWith(
        beatIndex: _currentBeatIndex,
        beatNumerator: meterPattern.beatsPerMeasure,
        beatSerial: playClick ? _state.beatSerial + 1 : _state.beatSerial,
        beatEsPrimero: isFirstBeat,
        timeSignatureNumerator: signature.numerator,
        timeSignatureDenominator: signature.denominator,
      ));

      if (playClick) {
        unawaited(_playMetronomeClick(isFirstBeat));
      }
    }
  }

  MidiTempoChange _tempoAt(ParsedMidiSong song, double time) {
    var active = song.tempoChanges.first;
    for (final change in song.tempoChanges) {
      if (change.timeSeconds > time) break;
      active = change;
    }
    return active;
  }

  MidiTimeSignature _signatureAt(ParsedMidiSong song, double time) {
    var active = song.timeSignatures.first;
    for (final signature in song.timeSignatures) {
      if (signature.timeSeconds > time) break;
      active = signature;
    }
    return active;
  }

  Future<void> _playMetronomeClick(bool accent) async {
    final player = accent ? _metronomeHighPlayer : _metronomeLowPlayer;
    try {
      await player.stop();
      await player.resume();
    } catch (e) {
      debugPrint('笶・[NativeMidiEngine] Error metrﾃｳnomo: $e');
    }
  }

  /// Reproduce una nota MIDI con Note-Off programado al final de su duraciﾃｳn.
  ///
  /// El conteo por altura evita cortar una nota sostenida por otra voz.
  /// El "epoch" invalida stops pendientes tras pause/stop/seek.
  void _playNativeNote(MidiNoteEvent note, int channel) {
    if (!_midiPro.isInitialized || _sfId == null) return;
    try {
      final pitch = note.note;
      final sfId = _sfId!;
      final epoch = _playbackEpoch;
      final noteKey = (channel << 8) | pitch;
      final activeNotes =
          _activeNoteCounts.values.fold<int>(0, (sum, count) => sum + count);
      final velocity = masteredVelocity(note.velocity, activeNotes);
      _activeNoteCounts[noteKey] = (_activeNoteCounts[noteKey] ?? 0) + 1;
      _midiPro.playNote(
        channel: channel,
        key: pitch,
        velocity: velocity,
        sfId: sfId,
      );

      // Note-Off exactamente al final de la duraciﾃｳn de la nota (ajustado
      // por velocidad de reproducciﾃｳn). Sin margen extra para no alargar
      // el sonido mﾃ｡s allﾃ｡ de lo escrito en la partitura.
      final durMs = ((note.durationSeconds / _state.speed) * 1000)
          .round()
          .clamp(40, 120000);
      Future.delayed(Duration(milliseconds: durMs), () {
        if (!_midiPro.isInitialized) return;
        if (_playbackEpoch != epoch) return; // hubo pause/stop/seek
        final remaining = (_activeNoteCounts[noteKey] ?? 1) - 1;
        if (remaining <= 0) {
          _activeNoteCounts.remove(noteKey);
          _midiPro.stopNote(channel: channel, key: pitch, sfId: sfId);
        } else {
          _activeNoteCounts[noteKey] = remaining;
        }
      });
    } catch (e) {
      debugPrint('笶・[NativeMidiEngine] Error en playMidiNote: $e');
    }
  }

  /// Compresiﾃｳn de dinﾃ｡mica MIDI con rodilla suave y compensaciﾃｳn moderada de
  /// polifonﾃｭa. Conserva los acentos, pero evita ataques aislados y acordes que
  /// saturen el piano.
  static int masteredVelocity(int inputVelocity, int activeNotes) {
    final normalized = inputVelocity.clamp(1, 127) / 127.0;
    final compressed = 30.0 + math.pow(normalized, 0.68) * 66.0;
    final polyphonyGain =
        (1 / math.sqrt(1 + activeNotes.clamp(0, 96) / 24.0)).clamp(0.72, 1.0);
    return (compressed * polyphonyGain).round().clamp(1, 104);
  }

  Future<void> _configureMastering() async {
    await _midiPro.setMasterGain(0.72);
    await _midiPro.setEqualizer(
      enabled: true,
      bassGain: -1.5,
      midGain: 1.25,
      trebleGain: -2.0,
    );
    await _midiPro.setReverb(
      enabled: true,
      roomSize: 0.18,
      damping: 0.65,
      width: 0.45,
      level: 0.12,
    );
    await _midiPro.setChorus(enabled: false);
  }

  Future<void> _configureVoiceChannels(List<MidiTrackInfo> tracks) async {
    if (_sfId == null) return;
    const melodicChannels = <int>[
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      10,
      11,
      12,
      13,
      14,
      15,
    ];
    final count = tracks.length;
    final halfSpread = count <= 1 ? 0.0 : math.min(14.0, 4.0 + count * 2.0);

    for (var index = 0; index < tracks.length; index++) {
      final channel = melodicChannels[index % melodicChannels.length];
      _trackChannels[tracks[index].index] = channel;
      final pan = count <= 1
          ? 64
          : (64 - halfSpread + (halfSpread * 2 * index / (count - 1)))
              .round()
              .clamp(0, 127);
      await _midiPro.selectInstrument(
        sfId: _sfId!,
        channel: channel,
        bank: 0,
        program: 0,
      );
      await _midiPro.controlChange(
        sfId: _sfId!,
        channel: channel,
        controller: 10,
        value: pan,
      );
      await _midiPro.controlChange(
        sfId: _sfId!,
        channel: channel,
        controller: 7,
        value: 104,
      );
    }
  }

  void _stopAllNotes() {
    _activeNoteCounts.clear();
    try {
      if (_midiPro.isInitialized && _sfId != null) {
        _midiPro.stopAllNotes(sfId: _sfId!);
      }
    } catch (_) {}
  }

  /// Detiene la reproducciﾃｳn actual. NO cierra el stream (el singleton vive toda la sesiﾃｳn).
  void dispose() {
    stop();
    // El StreamController NO se cierra porque el singleton es compartido entre
    // mﾃｺltiples instancias de VisorScreen. Cerrarlo rompe el stream para siempre.
  }
}
