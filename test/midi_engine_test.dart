import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/midi/midi_engine.dart';
import 'package:repertorio_bc/core/midi/native_midi_parser.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => null,
    );
  });

  test('agrupa métricas compuestas rápidas sin alterar 3/8', () {
    final sixEight = MidiMeterPattern.from(
      numerator: 6,
      denominator: 8,
      bpm: 71,
    );
    expect(sixEight.isCompound, isTrue);
    expect(sixEight.beatsPerMeasure, 6);
    expect(sixEight.groups, [3, 3]);

    final threeEight = MidiMeterPattern.from(
      numerator: 3,
      denominator: 8,
      bpm: 120,
    );
    expect(threeEight.isCompound, isFalse);
    expect(threeEight.beatsPerMeasure, 3);

    final sevenEight = MidiMeterPattern.from(
      numerator: 7,
      denominator: 8,
      bpm: 100,
    );
    expect(sevenEight.groups, [3, 2, 2]);

    final sixteenEight = MidiMeterPattern.from(
      numerator: 16,
      denominator: 8,
      bpm: 100,
    );
    expect(sixteenEight.groups, [3, 3, 3, 3, 2, 2]);
    expect(sixteenEight.groups.reduce((a, b) => a + b), 16);

    final customClocks = MidiMeterPattern.from(
      numerator: 16,
      denominator: 8,
      bpm: 60,
      metronomeClocks: 48,
    );
    expect(customClocks.groups, [4, 4, 4, 4]);
  });

  test('normaliza pistas ambiguas a la estructura coral', () {
    MidiTrackInfo track(int index, String name) => MidiTrackInfo(
          index: index,
          name: name,
          notes: const [],
        );

    final duplicatedPianos = NativeMidiParser.normalizeVoiceNames([
      track(0, 'Piano'),
      track(1, 'Alto'),
      track(2, 'Piano'),
      track(3, 'Bajo'),
    ]);
    expect(
      duplicatedPianos.map((track) => track.name),
      ['Soprano', 'Alto', 'Tenor', 'Bajo'],
    );

    final unnamedFiveVoices = NativeMidiParser.normalizeVoiceNames([
      track(0, 'Pista 1'),
      track(1, 'Pista 2'),
      track(2, 'Pista 3'),
      track(3, 'Pista 4'),
      track(4, 'Pista 5'),
    ]);
    expect(
      unnamedFiveVoices.map((track) => track.name),
      ['Solo', 'Soprano', 'Alto', 'Tenor', 'Bajo'],
    );

    final explicitNames = NativeMidiParser.normalizeVoiceNames([
      track(0, 'Cantus'),
      track(1, 'Altus'),
      track(2, 'Tenor'),
      track(3, 'Bassus'),
    ]);
    expect(
      explicitNames.map((track) => track.name),
      ['Cantus', 'Altus', 'Tenor', 'Bassus'],
    );
  });

  test('la compresión conserva acentos y limita acordes densos', () {
    final soft = MidiEngine.masteredVelocity(24, 0);
    final medium = MidiEngine.masteredVelocity(72, 0);
    final loud = MidiEngine.masteredVelocity(127, 0);
    final dense = MidiEngine.masteredVelocity(127, 24);

    expect(soft, lessThan(medium));
    expect(medium, lessThan(loud));
    expect(loud, lessThanOrEqualTo(120));
    expect(dense, lessThan(loud));
  });

  test('setTrackVolume y resetTrackVolumes ajustan el volumen de voces', () {
    final voz = MidiVoz(trackIndex: 0, nombre: 'Soprano', activa: true, volumen: 1.0);
    expect(voz.volumen, 1.0);

    voz.volumen = 0.5;
    expect(voz.volumen, 0.5);

    final engine = MidiEngine();
    expect(engine.state.voces, isEmpty);
    engine.setTrackVolume(0, 0.5);
    engine.resetTrackVolumes();
  });
}
