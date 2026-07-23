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

class NativeMidiParser {
  static ParsedMidiSong parse(Uint8List bytes) {
    if (bytes.length < 14) {
      throw FormatException('Fichero MIDI inválido: demasiado corto');
    }

    final headerStr = String.fromCharCodes(bytes.sublist(0, 4));
    if (headerStr != 'MThd') {
      throw FormatException('Fichero MIDI inválido: no contiene cabecera MThd');
    }

    final format = (bytes[8] << 8) | bytes[9];
    final numTracks = (bytes[10] << 8) | bytes[11];
    final ppq = (bytes[12] << 8) | bytes[13];

    int offset = 14;
    int initialBpm = 120;
    double maxTime = 0.0;
    final List<MidiTrackInfo> trackInfos = [];

    // Estructura interna para seguimiento de tiempos de tempo
    final List<_TempoEvent> tempoMap = [];

    // Pasada 1: Leer eventos y tempos
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
      final Map<int, Map<int, int>> openNotes = {}; // channel -> note -> startTick
      final List<_RawNote> rawNotes = [];

      while (offset < trackEnd && offset < bytes.length) {
        final delta = _readVarInt(bytes, offset, (o) => offset = o);
        currentTick += delta;

        if (offset >= bytes.length) break;
        int status = bytes[offset++];

        if (status == 0xFF) {
          // Evento Meta
          if (offset >= bytes.length) break;
          final metaType = bytes[offset++];
          final metaLen = _readVarInt(bytes, offset, (o) => offset = o);
          if (offset + metaLen > bytes.length) break;

          if (metaType == 0x03 && metaLen > 0) {
            trackName = String.fromCharCodes(bytes.sublist(offset, offset + metaLen)).trim();
          } else if (metaType == 0x51 && metaLen == 3) {
            final microsecondsPerQuarter =
                (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
            final bpm = (60000000 / microsecondsPerQuarter).round();
            if (tempoMap.isEmpty && currentTick == 0) {
              initialBpm = bpm;
            }
            tempoMap.add(_TempoEvent(tick: currentTick, microsecondsPerQuarter: microsecondsPerQuarter));
          }
          offset += metaLen;
        } else if (status == 0xF0 || status == 0xF7) {
          // SysEx
          final sysExLen = _readVarInt(bytes, offset, (o) => offset = o);
          offset += sysExLen;
        } else {
          // Evento MIDI normal
          if ((status & 0x80) == 0) {
            status = runningStatus;
            offset--; // Retroceder porque el byte leído era el primer data byte
          } else {
            runningStatus = status;
          }

          final command = status & 0xF0;
          final channel = status & 0x0F;

          if (command == 0x90 || command == 0x80) {
            final note = bytes[offset++];
            final velocity = bytes[offset++];

            if (command == 0x90 && velocity > 0) {
              // Note On
              openNotes.putIfAbsent(channel, () => {})[note] = currentTick;
            } else {
              // Note Off (0x80 o 0x90 con velocity 0)
              final startTick = openNotes[channel]?.remove(note);
              if (startTick != null) {
                rawNotes.add(_RawNote(
                  note: note,
                  velocity: command == 0x90 ? 80 : velocity,
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

      // Convertir rawNotes a MidiNoteEvents usando el mapa de tempo
      final List<MidiNoteEvent> notes = [];
      for (final rn in rawNotes) {
        final startTime = _ticksToSeconds(rn.startTick, ppq, tempoMap, initialBpm);
        final endTime = _ticksToSeconds(rn.endTick, ppq, tempoMap, initialBpm);
        final duration = endTime - startTime;
        if (endTime > maxTime) maxTime = endTime;

        notes.add(MidiNoteEvent(
          note: rn.note,
          velocity: rn.velocity,
          timeSeconds: startTime,
          durationSeconds: duration > 0 ? duration : 0.1,
          trackIndex: t,
          channel: rn.channel,
        ));
      }

      if (notes.isNotEmpty) {
        final lowerName = trackName.toLowerCase();
        if (lowerName.contains('soprano 2') || lowerName == 's2') trackName = 'S2';
        else if (lowerName.contains('alto 2') || lowerName == 'a2') trackName = 'A2';
        else if (lowerName.contains('tenor 2') || lowerName == 't2') trackName = 'T2';
        else if (lowerName.contains('bajo 2') || lowerName == 'b2') trackName = 'B2';
        else if (lowerName.contains('baritono') || lowerName.contains('barítono')) trackName = 'Barítono';

        trackInfos.add(MidiTrackInfo(
          index: t,
          name: trackName,
          notes: notes,
        ));
      }

      offset = trackEnd;
    }

    if (trackInfos.length == 4) {
      final names = trackInfos.map((t) => t.name.toLowerCase()).toList();
      final isGeneric = (String n) => n.isEmpty || n.startsWith('pista') || n.contains('piano');
      if (names.every(isGeneric)) {
        final labels = ['Soprano', 'Alto', 'Tenor', 'Bajo'];
        for (int i = 0; i < 4; i++) {
          trackInfos[i] = MidiTrackInfo(index: trackInfos[i].index, name: labels[i], notes: trackInfos[i].notes);
        }
      }
    }

    return ParsedMidiSong(
      tracks: trackInfos,
      durationSeconds: maxTime,
      tempoBpm: initialBpm,
      ppq: ppq,
    );
  }

  static int _readVarInt(Uint8List bytes, int startOffset, void Function(int) setOffset) {
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

class _TempoEvent {
  final int tick;
  final int microsecondsPerQuarter;

  _TempoEvent({required this.tick, required this.microsecondsPerQuarter});
}
