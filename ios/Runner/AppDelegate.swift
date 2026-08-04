import Flutter
import UIKit
import AVFoundation
import AudioToolbox
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configurar AVAudioSession como Playback para que el audio suene
    // incluso con el interruptor físico de silencio activado.
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Error configurando AVAudioSession: \(error)")
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // No dependemos exclusivamente del registro automático de Firebase.
    // Si APNs tarda en responder en TestFlight, este registro explícito hace
    // que didRegisterForRemoteNotificationsWithDeviceToken se ejecute y el
    // plugin pueda emitir el token FCM que se guarda en Supabase.
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    let flutterViewController = window!.rootViewController as! FlutterViewController
    let midiExportChannel = FlutterMethodChannel(
      name: "repertorio_bc/midi_export",
      binaryMessenger: flutterViewController.binaryMessenger
    )
    midiExportChannel.setMethodCallHandler { call, result in
      guard call.method == "renderMidiToWav",
            let args = call.arguments as? [String: Any],
            let midiPath = args["midiPath"] as? String,
            let soundfontPath = args["soundfontPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Self.renderMidiToWav(
            midiPath: midiPath,
            soundfontPath: soundfontPath,
            outputPath: outputPath,
            expectedDurationSeconds: args["expectedDurationSeconds"] as? Double ?? 0
          )
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "MIDI_RENDER_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Renderiza el MIDI fuera de línea con los sintetizadores nativos de iOS.
  /// Así no depende de símbolos de FluidSynth, que solo se empaquetan en Android.
  private static func renderMidiToWav(
    midiPath: String,
    soundfontPath: String,
    outputPath: String,
    expectedDurationSeconds: Double
  ) throws {
    let midiURL = URL(fileURLWithPath: midiPath)
    let soundfontURL = URL(fileURLWithPath: soundfontPath)
    let outputURL = URL(fileURLWithPath: outputPath)
    guard FileManager.default.fileExists(atPath: midiURL.path),
          FileManager.default.fileExists(atPath: soundfontURL.path) else {
      throw NSError(
        domain: "RepertorioMidiExport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No se encontró el MIDI o el SoundFont para exportar."]
      )
    }

    try? FileManager.default.removeItem(at: outputURL)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)

    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: format)
    try sampler.loadSoundBankInstrument(
      at: soundfontURL,
      program: 0,
      bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
      bankLSB: 0
    )

    let sequencer = AVAudioSequencer(audioEngine: engine)
    try sequencer.load(from: midiURL, options: [])
    for track in sequencer.tracks {
      track.destinationAudioUnit = sampler
    }

    try engine.enableManualRenderingMode(
      .offline,
      format: format,
      maximumFrameCount: 4096
    )
    try engine.start()
    sequencer.prepareToPlay()
    try sequencer.start()

    let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(
      pcmFormat: engine.manualRenderingFormat,
      frameCapacity: engine.manualRenderingMaximumFrameCount
    )!
    // El analizador Dart calcula la misma duración que muestra el reproductor.
    // Renderizar exactamente esos frames evita ciclos interminables cuando
    // AVAudioSequencer no cambia `isPlaying` en modo manual offline.
    let totalFrames = AVAudioFrameCount(max(
      1,
      (max(expectedDurationSeconds, 0.05) * format.sampleRate).rounded(.up)
    ))
    var renderedFrames: AVAudioFrameCount = 0
    var idleRenders = 0

    while renderedFrames < totalFrames {
      let framesToRender = min(
        engine.manualRenderingMaximumFrameCount,
        totalFrames - renderedFrames
      )
      let status = try engine.renderOffline(
        framesToRender,
        to: buffer
      )
      switch status {
      case .success:
        idleRenders = 0
        try output.write(from: buffer)
        renderedFrames += buffer.frameLength
      case .insufficientDataFromInputNode:
        idleRenders += 1
        if idleRenders > 32 {
          throw NSError(
            domain: "RepertorioMidiExport",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "El render MIDI dejó de recibir audio."]
          )
        }
        continue
      case .cannotDoInCurrentContext:
        continue
      case .error:
        throw NSError(
          domain: "RepertorioMidiExport",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "iOS no pudo renderizar el MIDI."]
        )
      @unknown default:
        throw NSError(
          domain: "RepertorioMidiExport",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Estado de render MIDI no reconocido."]
        )
      }
    }
    engine.stop()
    guard FileManager.default.fileExists(atPath: outputURL.path) else {
      throw NSError(
        domain: "RepertorioMidiExport",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "No se generó el audio WAV."]
      )
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[PushService] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
