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

  ParsedMidiSong({
    required this.tracks,
    required this.durationSeconds,
    required this.tempoBpm,
    required this.ppq,
  });
}

class _TempoEvent {
  final int tick;
  final int microsecondsPerQuarter;

  _TempoEvent({required this.tick, required this.microsecondsPerQuarter});
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
              final us = (bytes[off] << 16) |
                  (bytes[off + 1] << 8) |
                  bytes[off + 2];
              if (tempoMap.isEmpty && curTick == 0) {
                defaultBpm = (60000000 / us).round();
              }
              tempoMap.add(_TempoEvent(
                tick: curTick,
                microsecondsPerQuarter: us,
              ));
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
            if (command == 0x90 || command == 0x80 ||
                command == 0xA0 || command == 0xB0 || command == 0xE0) {
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
    }

    // ── Pasada 2: extraer notas de todas las pistas ───────────────────────
    int offset = 14;
    double maxTime = 0.0;
    final List<MidiTrackInfo> trackInfos = [];

    for (int t = 0; t < numTracks && offset < bytes.length; t++) {
      if (offset + 8 > bytes.length) break;
      final chunkHeader = String.fromCharCodes(bytes.sublist(offset, offset + 4));
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
      final Map<int, Map<int, int>> openNotes = {};      // channel -> note -> startTick
      final Map<int, Map<int, int>> openVelocities = {}; // channel -> note -> velocity
      final List<_RawNote> rawNotes = [];

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
            trackName = String.fromCharCodes(
                bytes.sublist(offset, offset + metaLen)).trim();
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
              openVelocities.putIfAbsent(channel, () => {})[note] = velocity;
            } else {
              // Note Off (0x80 o 0x90 con velocity 0)
              final startTick = openNotes[channel]?.remove(note);
              final noteVel = openVelocities[channel]?.remove(note) ?? 64;
              if (startTick != null) {
                rawNotes.add(_RawNote(
                  note: note,
                  velocity: noteVel,
                  startTick: startTick,
                  endTick: currentTick,
                  channel: channel,
                ));
              }
            }
          } else if (command == 0xA0 || command == 0xB0 || command == 0xE0) {
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

      // Convertir ticks → segundos con el mapa de tempo completo
      final List<MidiNoteEvent> notes = [];
      for (final rn in rawNotes) {
        final startTime = _ticksToSeconds(rn.startTick, ppq, tempoMap, defaultBpm);
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
        } else if (lowerName.contains('baritono') || lowerName.contains('barítono')) {
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

    // Etiquetas automáticas para MIDIs sin nombre de pista
    if (trackInfos.length == 4) {
      final names = trackInfos.map((t) => t.name.toLowerCase()).toList();
      bool isGeneric(String n) =>
          n.isEmpty || n.startsWith('pista') || n.contains('piano');
      if (names.every(isGeneric)) {
        final labels = ['Soprano', 'Alto', 'Tenor', 'Bajo'];
        for (int i = 0; i < 4; i++) {
          trackInfos[i] = MidiTrackInfo(
            index: trackInfos[i].index,
            name: labels[i],
            notes: trackInfos[i].notes,
          );
        }
      }
    }

    return ParsedMidiSong(
      tracks: trackInfos,
      durationSeconds: maxTime,
      tempoBpm: defaultBpm,
      ppq: ppq,
    );
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
