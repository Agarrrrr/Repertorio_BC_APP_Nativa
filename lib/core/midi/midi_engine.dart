// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import the platform specific implementations
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Servidor local ultra-ligero para eludir bloqueos CORS (file://) en el WebView.
class LocalAssetServer {
  HttpServer? _server;
  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) async {
      final path = request.uri.path.substring(1); // Quitar '/'
      print('🌐 [LocalAssetServer] Request: $path');
      try {
        if (path.isEmpty) {
          request.response.statusCode = 404;
          request.response.close();
          return;
        }

        final ByteData data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List();

        String mimeType = 'text/plain';
        if (path.endsWith('.html')) {
          mimeType = 'text/html; charset=utf-8';
        } else if (path.endsWith('.js')) {
          mimeType = 'application/javascript; charset=utf-8';
        } else if (path.endsWith('.mp3')) {
          mimeType = 'audio/mpeg';
        } else if (path.endsWith('.wav')) {
          mimeType = 'audio/wav';
        }

        request.response.headers.set('Content-Type', mimeType);
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        
        request.response.add(bytes);
        await request.response.close();
        print('🌐 [LocalAssetServer] Served 200: $path');
      } catch (e) {
        print('🌐 [LocalAssetServer] Error loading $path: $e');
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
  }
}

/// Estado público del motor de audio.
class MidiState {
  final bool isPlaying;
  final bool isLoaded;
  final bool isReady; // WebView + Tone.js listos
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
    this.isReady = false,
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

/// Singleton que gestiona el WebView del motor MIDI y expone
/// su estado como un Stream reactivo.
class MidiEngine {
  static final MidiEngine _instance = MidiEngine._internal();
  factory MidiEngine() => _instance;
  MidiEngine._internal();

  WebViewController? _controller;
  bool _bridgeReady = false;
  final LocalAssetServer _server = LocalAssetServer();

  final _stateController = StreamController<MidiState>.broadcast();
  Stream<MidiState> get stateStream => _stateController.stream;

  MidiState _state = const MidiState();
  MidiState get state => _state;

  void _emit(MidiState s) {
    _state = s;
    _stateController.add(s);
  }

  // ─── Crear / obtener el WebViewController ─────────────────────────────────
  WebViewController buildController() {
    if (_controller != null) return _controller!;

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onBridgeMessage,
      );

    _controller = controller;
    _loadPlayerPage();
    return _controller!;
  }

  Future<void> _loadPlayerPage() async {
    // Iniciar el servidor local
    await _server.start();
    // Se usa 'localhost' en lugar de '127.0.0.1' para exentar las reglas de cleartextTraffic en Android
    final url = 'http://localhost:${_server.port}/assets/midi_player.html';
    
    // Cargar vía HTTP local
    await _controller!.loadRequest(Uri.parse(url));
  }

  // ─── Recibir mensajes del JS ──────────────────────────────────────────────
  void _onBridgeMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final event = data['event'] as String;
      final payload = data['data'] as Map<String, dynamic>? ?? {};

      switch (event) {
        case 'bridge_ready':
          _bridgeReady = true;
          // Inicializar Tone.js automáticamente (requiere gesto posterior para audio)
          _js('MidiPlayer.init()');
          break;

        case 'ready':
          _emit(_state.copyWith(isReady: true));
          break;

        case 'loaded':
          final tracks = (payload['tracks'] as List? ?? []).map((t) {
            return MidiVoz(
              trackIndex: (t['index'] as num).toInt(),
              nombre: t['nombre'] as String? ?? 'Pista',
            );
          }).toList();
          _emit(_state.copyWith(
            isLoaded: true,
            tiempoTotal: (payload['duracion'] as num?)?.toDouble() ?? 0.0,
            voces: tracks,
          ));
          break;

        case 'progress':
          _emit(_state.copyWith(
            progress: (payload['progress'] as num?)?.toDouble() ?? _state.progress,
            tiempoActual: (payload['actual'] as num?)?.toDouble() ?? _state.tiempoActual,
            tiempoTotal: (payload['total'] as num?)?.toDouble() ?? _state.tiempoTotal,
          ));
          break;

        case 'beat':
          _emit(_state.copyWith(
            beatIndex: (payload['beatIndex'] as num?)?.toInt(),
            beatNumerator: (payload['numerator'] as num?)?.toInt(),
            beatEsPrimero: payload['isFirstBeat'] as bool?,
          ));
          break;

        case 'ended':
          _emit(_state.copyWith(isPlaying: false, progress: 0.0, tiempoActual: 0.0));
          break;

        case 'speedChanged':
          _emit(_state.copyWith(speed: (payload['speed'] as num?)?.toDouble() ?? _state.speed));
          break;

        case 'metronomoChanged':
          _emit(_state.copyWith(metronomoActivo: payload['activo'] as bool? ?? _state.metronomoActivo));
          break;

        case 'error':
          print('❌ [MidiEngine] ${payload['message']}');
          break;
      }
    } catch (e) {
      print('❌ [MidiEngine] Error parsing bridge message: $e');
    }
  }

  // ─── Cargar un archivo MIDI desde ruta local ──────────────────────────────
  Future<void> loadMidi(String filePath, String nombre) async {
    if (!_bridgeReady) return;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ [MidiEngine] Archivo MIDI no encontrado: $filePath');
        return;
      }
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      // Enviar en chunks si es muy largo — el WebView tiene límite de eval
      // Aquí enviamos todo en una llamada; los archivos .mid son usualmente <100KB
      _js("MidiPlayer.load('$b64', ${jsonEncode(nombre)})");
      _emit(_state.copyWith(isLoaded: false, isPlaying: false, progress: 0.0));
    } catch (e) {
      print('❌ [MidiEngine] Error cargando MIDI: $e');
    }
  }

  // ─── Controles de Playback ────────────────────────────────────────────────
  void play() {
    _js('MidiPlayer.play()');
    _emit(_state.copyWith(isPlaying: true));
  }

  void pause() {
    _js('MidiPlayer.pause()');
    _emit(_state.copyWith(isPlaying: false));
  }

  void stop() {
    _js('MidiPlayer.stop()');
    _emit(_state.copyWith(isPlaying: false, progress: 0.0, tiempoActual: 0.0));
  }

  void seek(double porcentaje) {
    _js('MidiPlayer.seek($porcentaje)');
  }

  void setSpeed(double speed) {
    _js('MidiPlayer.setSpeed($speed)');
    _emit(_state.copyWith(speed: speed));
  }

  void toggleMetronomo() {
    final nuevoEstado = !_state.metronomoActivo;
    _js('MidiPlayer.toggleMetronomo($nuevoEstado)');
    _emit(_state.copyWith(metronomoActivo: nuevoEstado));
  }

  void setTrackMute(int trackIndex, bool muted) {
    final vol = muted ? 0.0 : 1.0;
    _js('MidiPlayer.setTrackVolume($trackIndex, $vol)');
    final updatedVoces = _state.voces.map((v) {
      if (v.trackIndex == trackIndex) return MidiVoz(trackIndex: v.trackIndex, nombre: v.nombre, activa: !muted);
      return v;
    }).toList();
    _emit(_state.copyWith(voces: updatedVoces));
  }

  // ─── Destruir al salir ────────────────────────────────────────────────────
  void dispose() {
    if (_state.isPlaying) _js('MidiPlayer.stop()');
    _controller = null;
    _bridgeReady = false;
    _server.stop();
    _emit(const MidiState());
  }

  // ─── Helper: ejecutar JS ──────────────────────────────────────────────────
  void _js(String code) {
    _controller?.runJavaScript(code).catchError((e) {
      print('❌ [MidiEngine] JS Error: $e');
    });
  }
}
