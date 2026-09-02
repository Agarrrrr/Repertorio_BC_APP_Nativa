import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/midi/midi_export_service.dart';
import 'package:repertorio_bc/models/canto.dart';

void main() {
  test('el nombre compartido es MP3 humano y no expone IDs internos', () {
    final canto = Canto(
      id: 'interno-42',
      nombre: 'Sublime Gracia 550e8400-e29b-41d4-a716-446655440000',
      archivo: 'global/pdf.enc',
      temas: const [],
      corosVinculados: const [],
    );

    final name = MidiExportService.displayFileName(canto);

    expect(name, 'Sublime Gracia - Ensamble.mp3');
    expect(name, isNot(contains(canto.id)));
    expect(name.toLowerCase(), endsWith('.mp3'));
  });
}
