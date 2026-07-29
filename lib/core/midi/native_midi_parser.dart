import 'dart:typed_data';

class MidiNoteEvent {
  final int note;
  final int velocity;
  final double timeSeconds;
  final double durationSeconds;
  final int trackIndex;
  final int channel;

  MidiNoteEvent({
    required this.note,
    required this.velocity,
    required this.timeSeconds,
    required this.durationSeconds,
    required this.trackIndex,
    required this.channel,
  });
}

class MidiTrackInfo {
  final int index;
  final String name;
  final List<MidiNoteEvent> notes;

  MidiTrackInfo({
    required this.index,
    required this.name,
    required this.notes,
  });
}

class ParsedMidiSong {
  final List<MidiTrackInfo> tracks;
  final double durationSeconds;
  final int tempoBpm;
  final int ppq;
  final List<MidiTempoChange> tempoChanges;
  final List<MidiTimeSignature> timeSignatures;

  ParsedMidiSong({
    required this.tracks,
    required this.durationSeconds,
    required this.tempoBpm,
    required this.ppq,
    required this.tempoChanges,
    required this.timeSignatures,
  });
}

class MidiTempoChange {
  final int tick;
  final double timeSeconds;
  final int bpm;

  const MidiTempoChange({
    required this.tick,
    required this.timeSeconds,
    required this.bpm,
  });
}

class MidiTimeSignature {
  final int tick;
  final double timeSeconds;
  final int numerator;
  final int denominator;
  final int metronomeClocks;

  const MidiTimeSignature({
    required this.tick,
    required this.timeSeconds,
    required this.numerator,
    required this.denominator,
    required this.metronomeClocks,
  });
}

class MidiMeterPattern {
  final List<int> groups;
  final double writtenUnitInQuarters;
  final bool isCompound;

  const MidiMeterPattern({
    required this.groups,
    required this.writtenUnitInQuarters,
    required this.isCompound,
  });

  int get beatsPerMeasure => groups.length;
  double get measureLengthInQuarters =>
      groups.fold<int>(0, (sum, group) => sum + group) * writtenUnitInQuarters;

  factory MidiMeterPattern.from({
    required int numerator,
    required int denominator,
    required int bpm,
    int metronomeClocks = 24,
  }) {
    final writtenPulseInQuarters = 4.0 / denominator;
    var preferredGroup = 1;

    if (denominator == 8 && metronomeClocks == 24) {
      preferredGroup = bpm > 70 && numerator != 3 ? 3 : 1;
    } else if (metronomeClocks > 0) {
      final units = (metronomeClocks / 24.0) / writtenPulseInQuarters;
      final rounded = units.round();
      if ((units - rounded).abs() < 0.001 && rounded >= 1) {
        preferredGroup = rounded;
      }
    }

    final groups = _partitionMeter(numerator, preferredGroup);
    final compound = denominator == 8 &&
        numerator > 3 &&
        groups.every((group) => group == 3);
    return MidiMeterPattern(
      groups: groups,
      writtenUnitInQuarters: writtenPulseInQuarters,
      isCompound: compound,
    );
  }

  int pulseSerialAt(double elapsedQuarters) {
    final safeElapsed = elapsedQuarters.clamp(0.0, double.infinity);
    final measureIndex = (safeElapsed / measureLengthInQuarters + 1e-8).floor();
    final insideMeasure =
        safeElapsed - (measureIndex * measureLengthInQuarters);
    final writtenPosition = insideMeasure / writtenUnitInQuarters;
    return (measureIndex * groups.length) + beatIndexAt(writtenPosition);
  }

  int beatIndexAt(double writtenPosition) {
    var boundary = 0.0;
    var active = 0;
    for (var index = 0; index < groups.length; index++) {
      if (writtenPosition + 1e-7 >= boundary) active = index;
      boundary += groups[index];
    }
    return active;
  }

  static List<int> _partitionMeter(int numerator, int preferredGroup) {
    if (numerator <= 0) return const [1];
    if (preferredGroup <= 1 || numerator == 3) {
      return List<int>.filled(numerator, 1, growable: false);
    }

    final groups = <int>[];
    var remaining = numerator;
    while (remaining > 0) {
      if (remaining == 1 && groups.isNotEmpty && groups.last > 2) {
        groups[groups.length - 1] = groups.last - 1;
        groups.add(2);
        break;
      }
      if (remaining >= preferredGroup) {
        groups.add(preferredGroup);
        remaining -= preferredGroup;
      } else {
        groups.add(remaining);
        break;
      }
    }
    return List<int>.unmodifiable(groups);
  }
}

class _TempoEvent {
  final int tick;
  final int microsecondsPerQuarter;

  _TempoEvent({required this.tick, required this.microsecondsPerQuarter});
}

class _RawTimeSignature {
  final int tick;
  final int numerator;
  final int denominator;
  final int metronomeClocks;

  const _RawTimeSignature({
    required this.tick,
    required this.numerator,
    required this.denominator,
    required this.metronomeClocks,
  });
}

class _RawNote {
  final int note;
  final int velocity;
  final int startTick;
  final int endTick;
  final int channel;

  _RawNote({
    required this.note,
    required this.velocity,
    required this.startTick,
    required this.endTick,
    required this.channel,
  });
}

class _SustainedNote {
  final int note;
  final int velocity;
  final int startTick;
  final int channel;

  const _SustainedNote({
    required this.note,
    required this.velocity,
    required this.startTick,
    required this.channel,
  });
}

class NativeMidiParser {
  static ParsedMidiSong parse(Uint8List bytes) {
    if (bytes.length < 14) {
      throw FormatException('Fichero MIDI inválido: demasiado corto');
    }

    final headerStr = String.fromCharCodes(bytes.sublist(0, 4));
    if (headerStr != 'MThd') {
      throw FormatException('Fichero MIDI inválido: no contiene cabecera MThd');
    }

    final numTracks = (bytes[10] << 8) | bytes[11];
    final ppq = (bytes[12] << 8) | bytes[13];

    // ── Pasada 1: recolectar TODO el mapa de tempo de TODAS las pistas ──────
    // (en formato 0 los tempos van en la única pista; en formato 1 van en la
    // pista 0, pero a veces también hay cambios de tempo en pistas de notas)
    final List<_TempoEvent> tempoMap = [];
    final List<_RawTimeSignature> rawTimeSignatures = [];
    int defaultBpm = 120;

    {
      int off = 14;
      for (int t = 0; t < numTracks && off < bytes.length; t++) {
        if (off + 8 > bytes.length) break;
        final chunkId = String.fromCharCodes(bytes.sublist(off, off + 4));
        final chunkSize = (bytes[off + 4] << 24) |
            (bytes[off + 5] << 16) |
            (bytes[off + 6] << 8) |
            bytes[off + 7];
        off += 8;

        if (chunkId != 'MTrk') {
          off += chunkSize;
          continue;
        }

        final trackEnd = off + chunkSize;
        int curTick = 0;
        int runStatus = 0;

        while (off < trackEnd && off < bytes.length) {
          final delta = _readVarInt(bytes, off, (o) => off = o);
          curTick += delta;

          if (off >= bytes.length) break;
          int status = bytes[off++];

          if (status == 0xFF) {
            if (off >= bytes.length) break;
            final metaType = bytes[off++];
            final metaLen = _readVarInt(bytes, off, (o) => off = o);
            if (off + metaLen > bytes.length) break;

            if (metaType == 0x51 && metaLen == 3) {
              final us =
                  (bytes[off] << 16) | (bytes[off + 1] << 8) | bytes[off + 2];
              if (tempoMap.isEmpty && curTick == 0) {
                defaultBpm = (60000000 / us).round();
              }
              tempoMap.add(_TempoEvent(
                tick: curTick,
                microsecondsPerQuarter: us,
              ));
            } else if (metaType == 0x58 && metaLen >= 2) {
              final numerator = bytes[off];
              final denominator = 1 << bytes[off + 1];
              final metronomeClocks = metaLen >= 3 ? bytes[off + 2] : 24;
              if (numerator > 0 && denominator > 0) {
                rawTimeSignatures.add(_RawTimeSignature(
                  tick: curTick,
                  numerator: numerator,
                  denominator: denominator,
                  metronomeClocks: metronomeClocks,
                ));
              }
            }
            off += metaLen;
          } else if (status == 0xF0 || status == 0xF7) {
            final len = _readVarInt(bytes, off, (o) => off = o);
            off += len;
          } else {
            if ((status & 0x80) == 0) {
              status = runStatus;
              off--;
            } else {
              runStatus = status;
            }
            final command = status & 0xF0;
            if (command == 0x90 ||
                command == 0x80 ||
                command == 0xA0 ||
                command == 0xB0 ||
                command == 0xE0) {
              off += 2;
            } else if (command == 0xC0 || command == 0xD0) {
              off += 1;
            }
          }
        }

        off = trackEnd;
      }

      // Ordenar por tick por si vienen en orden incorrecto
      tempoMap.sort((a, b) => a.tick.compareTo(b.tick));
      rawTimeSignatures.sort((a, b) => a.tick.compareTo(b.tick));
    }

    // ── Pasada 2: extraer notas de todas las pistas ───────────────────────
    int offset = 14;
    double maxTime = 0.0;
    final List<MidiTrackInfo> trackInfos = [];

    for (int t = 0; t < numTracks && offset < bytes.length; t++) {
      if (offset + 8 > bytes.length) break;
      final chunkHeader =
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = (bytes[offset + 4] << 24) |
          (bytes[offset + 5] << 16) |
          (bytes[offset + 6] << 8) |
          bytes[offset + 7];
      offset += 8;

      if (chunkHeader != 'MTrk') {
        offset += chunkSize;
        continue;
      }

      final trackEnd = offset + chunkSize;
      int currentTick = 0;
      int runningStatus = 0;
      String trackName = 'Pista ${t + 1}';
      final Map<int, Map<int, int>> openNotes =
          {}; // channel -> note -> startTick
      final Map<int, Map<int, int>> openVelocities =
          {}; // channel -> note -> velocity
      final Map<int, bool> sustainDown = {};
      final Map<int, List<_SustainedNote>> sustainedNotes = {};
      final Map<int, int> channelExpression = {};
      final Map<int, int> channelVolume = {};
      final List<_RawNote> rawNotes = [];

      void releaseSustainedNotes(int channel, int endTick) {
        final pending =
            sustainedNotes.remove(channel) ?? const <_SustainedNote>[];
        for (final note in pending) {
          rawNotes.add(_RawNote(
            note: note.note,
            velocity: note.velocity,
            startTick: note.startTick,
            endTick: endTick,
            channel: note.channel,
          ));
        }
      }

      while (offset < trackEnd && offset < bytes.length) {
        final delta = _readVarInt(bytes, offset, (o) => offset = o);
        currentTick += delta;

        if (offset >= bytes.length) break;
        int status = bytes[offset++];

        if (status == 0xFF) {
          if (offset >= bytes.length) break;
          final metaType = bytes[offset++];
          final metaLen = _readVarInt(bytes, offset, (o) => offset = o);
          if (offset + metaLen > bytes.length) break;

          if (metaType == 0x03 && metaLen > 0) {
            trackName =
                String.fromCharCodes(bytes.sublist(offset, offset + metaLen))
                    .trim();
          }
          offset += metaLen;
        } else if (status == 0xF0 || status == 0xF7) {
          final sysExLen = _readVarInt(bytes, offset, (o) => offset = o);
          offset += sysExLen;
        } else {
          if ((status & 0x80) == 0) {
            status = runningStatus;
            offset--;
          } else {
            runningStatus = status;
          }

          final command = status & 0xF0;
          final channel = status & 0x0F;

          if (command == 0x90 || command == 0x80) {
            if (offset + 1 >= bytes.length) break;
            final note = bytes[offset++];
            final velocity = bytes[offset++];

            if (command == 0x90 && velocity > 0) {
              // Note On real
              openNotes.putIfAbsent(channel, () => {})[note] = currentTick;
              final expression = channelExpression[channel] ?? 127;
              final volume = channelVolume[channel] ?? 127;
              final adjustedVelocity =
                  (velocity * expression * volume / (127 * 127))
                      .round()
                      .clamp(1, 127);
              openVelocities.putIfAbsent(channel, () => {})[note] =
                  adjustedVelocity;
            } else {
              // Note Off (0x80 o 0x90 con velocity 0)
              final startTick = openNotes[channel]?.remove(note);
              final noteVel = openVelocities[channel]?.remove(note) ?? 64;
              if (startTick != null) {
                if (sustainDown[channel] ?? false) {
                  sustainedNotes.putIfAbsent(channel, () => []).add(
                        _SustainedNote(
                          note: note,
                          velocity: noteVel,
                          startTick: startTick,
                          channel: channel,
                        ),
                      );
                } else {
                  rawNotes.add(_RawNote(
                    note: note,
                    velocity: noteVel,
                    startTick: startTick,
                    endTick: currentTick,
                    channel: channel,
                  ));
                }
              }
            }
          } else if (command == 0xB0) {
            if (offset + 1 >= bytes.length) break;
            final controller = bytes[offset++];
            final value = bytes[offset++];
            if (controller == 64) {
              final wasDown = sustainDown[channel] ?? false;
              final isDown = value >= 64;
              sustainDown[channel] = isDown;
              if (wasDown && !isDown) {
                releaseSustainedNotes(channel, currentTick);
              }
            } else if (controller == 11) {
              channelExpression[channel] = value;
            } else if (controller == 7) {
              channelVolume[channel] = value;
            }
          } else if (command == 0xA0 || command == 0xE0) {
            offset += 2;
          } else if (command == 0xC0 || command == 0xD0) {
            offset += 1;
          }
        }
      }

      // Cerrar notas que no tuvieron Note Off explícito
      for (final chEntry in openNotes.entries) {
        final ch = chEntry.key;
        for (final noteEntry in chEntry.value.entries) {
          final n = noteEntry.key;
          final startTick = noteEntry.value;
          final vel = openVelocities[ch]?[n] ?? 64;
          rawNotes.add(_RawNote(
            note: n,
            velocity: vel,
            startTick: startTick,
            endTick: currentTick,
            channel: ch,
          ));
        }
      }
      for (final channel in sustainedNotes.keys.toList(growable: false)) {
        releaseSustainedNotes(channel, currentTick);
      }

      // Convertir ticks → segundos con el mapa de tempo completo
      final List<MidiNoteEvent> notes = [];
      for (final rn in rawNotes) {
        final startTime =
            _ticksToSeconds(rn.startTick, ppq, tempoMap, defaultBpm);
        final endTime = _ticksToSeconds(rn.endTick, ppq, tempoMap, defaultBpm);
        final duration = endTime - startTime;
        if (endTime > maxTime) {
          maxTime = endTime;
        }

        notes.add(MidiNoteEvent(
          note: rn.note,
          velocity: rn.velocity,
          timeSeconds: startTime,
          durationSeconds: duration > 0 ? duration : 0.25,
          trackIndex: t,
          channel: rn.channel,
        ));
      }

      // Ordenar por tiempo de inicio
      notes.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

      if (notes.isNotEmpty) {
        String displayName = trackName;
        final lowerName = trackName.toLowerCase();
        if (lowerName.contains('soprano 2') || lowerName == 's2') {
          displayName = 'S2';
        } else if (lowerName.contains('alto 2') || lowerName == 'a2') {
          displayName = 'A2';
        } else if (lowerName.contains('tenor 2') || lowerName == 't2') {
          displayName = 'T2';
        } else if (lowerName.contains('bajo 2') || lowerName == 'b2') {
          displayName = 'B2';
        } else if (lowerName.contains('baritono') ||
            lowerName.contains('barítono')) {
          displayName = 'Barítono';
        }

        trackInfos.add(MidiTrackInfo(
          index: t,
          name: displayName,
          notes: notes,
        ));
      }

      offset = trackEnd;
    }

    final namedTracks = normalizeVoiceNames(trackInfos);

    final normalizedTempos = <_TempoEvent>[];
    for (final tempo in tempoMap) {
      if (normalizedTempos.isNotEmpty &&
          normalizedTempos.last.tick == tempo.tick) {
        normalizedTempos[normalizedTempos.length - 1] = tempo;
      } else {
        normalizedTempos.add(tempo);
      }
    }
    if (normalizedTempos.isEmpty || normalizedTempos.first.tick != 0) {
      normalizedTempos.insert(
        0,
        _TempoEvent(
          tick: 0,
          microsecondsPerQuarter: (60000000 / defaultBpm).round(),
        ),
      );
    }
    final publicTempos = normalizedTempos
        .map((tempo) => MidiTempoChange(
              tick: tempo.tick,
              timeSeconds: _ticksToSeconds(
                tempo.tick,
                ppq,
                normalizedTempos,
                defaultBpm,
              ),
              bpm: (60000000 / tempo.microsecondsPerQuarter).round(),
            ))
        .toList(growable: false);

    final normalizedSignatures = <_RawTimeSignature>[];
    for (final signature in rawTimeSignatures) {
      if (normalizedSignatures.isNotEmpty &&
          normalizedSignatures.last.tick == signature.tick) {
        normalizedSignatures[normalizedSignatures.length - 1] = signature;
      } else {
        normalizedSignatures.add(signature);
      }
    }
    if (normalizedSignatures.isEmpty || normalizedSignatures.first.tick != 0) {
      normalizedSignatures.insert(
        0,
        const _RawTimeSignature(
          tick: 0,
          numerator: 4,
          denominator: 4,
          metronomeClocks: 24,
        ),
      );
    }
    final publicSignatures = normalizedSignatures
        .map((signature) => MidiTimeSignature(
              tick: signature.tick,
              timeSeconds: _ticksToSeconds(
                signature.tick,
                ppq,
                normalizedTempos,
                defaultBpm,
              ),
              numerator: signature.numerator,
              denominator: signature.denominator,
              metronomeClocks: signature.metronomeClocks,
            ))
        .toList(growable: false);

    return ParsedMidiSong(
      tracks: namedTracks,
      durationSeconds: maxTime,
      tempoBpm: defaultBpm,
      ppq: ppq,
      tempoChanges: publicTempos,
      timeSignatures: publicSignatures,
    );
  }

  /// Conserva los nombres del MIDI únicamente cuando todas las pistas tienen
  /// una etiqueta útil y no hay varios pianos que vuelvan ambigua la función
  /// coral. Los escaneos de cuatro y cinco pentagramas se interpretan por el
  /// orden convencional de la partitura.
  static List<MidiTrackInfo> normalizeVoiceNames(
    List<MidiTrackInfo> tracks,
  ) {
    if (tracks.length != 4 && tracks.length != 5) {
      return List<MidiTrackInfo>.unmodifiable(tracks);
    }

    final normalizedNames =
        tracks.map((track) => track.name.trim().toLowerCase()).toList();
    final allNamed = normalizedNames.every(
      (name) =>
          name.isNotEmpty && !RegExp(r'^(pista|track)\s*\d*$').hasMatch(name),
    );
    final pianoCount =
        normalizedNames.where((name) => name.contains('piano')).length;

    if (allNamed && pianoCount <= 1) {
      return List<MidiTrackInfo>.unmodifiable(tracks);
    }

    final labels = tracks.length == 5
        ? const ['Solo', 'Soprano', 'Alto', 'Tenor', 'Bajo']
        : const ['Soprano', 'Alto', 'Tenor', 'Bajo'];
    return List<MidiTrackInfo>.unmodifiable([
      for (var index = 0; index < tracks.length; index++)
        MidiTrackInfo(
          index: tracks[index].index,
          name: labels[index],
          notes: tracks[index].notes,
        ),
    ]);
  }

  // ── Lectura de variable-length int (VarInt) ─────────────────────────────
  static int _readVarInt(
      Uint8List bytes, int startOffset, void Function(int) setOffset) {
    int value = 0;
    int offset = startOffset;

    int byte;
    do {
      if (offset >= bytes.length) break;
      byte = bytes[offset++];
      value = (value << 7) | (byte & 0x7F);
    } while ((byte & 0x80) != 0);

    setOffset(offset);
    return value;
  }

  // ── Conversión de ticks a segundos respetando cambios de tempo ────────
  static double _ticksToSeconds(
      int ticks, int ppq, List<_TempoEvent> tempoMap, int initialBpm) {
    if (tempoMap.isEmpty) {
      return (ticks / ppq) * (60.0 / initialBpm);
    }

    double time = 0.0;
    int currentTick = 0;
    int currentUsPerQuarter = (60000000 / initialBpm).round();

    for (final te in tempoMap) {
      if (te.tick >= ticks) break;
      final deltaTicks = te.tick - currentTick;
      time += (deltaTicks / ppq) * (currentUsPerQuarter / 1000000.0);
      currentTick = te.tick;
      currentUsPerQuarter = te.microsecondsPerQuarter;
    }

    if (ticks > currentTick) {
      final deltaTicks = ticks - currentTick;
      time += (deltaTicks / ppq) * (currentUsPerQuarter / 1000000.0);
    }

    return time;
  }
}
