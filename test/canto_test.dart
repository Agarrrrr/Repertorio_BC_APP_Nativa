import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/models/canto.dart';

void main() {
  test('limpia el prefijo accidental de señal en vivo', () {
    final canto = Canto.fromJson({
      'id': 'canto-1',
      'nombre': 'Envió señal en vivo: Oh Creador',
      'archivo': 'global/pdf.enc',
    });

    expect(canto.nombre, 'Oh Creador');
  });

  test('conserva los nombres normales', () {
    final canto = Canto.fromJson({
      'id': 'canto-2',
      'nombre': 'Sublime Gracia',
      'archivo': 'global/pdf.enc',
    });

    expect(canto.nombre, 'Sublime Gracia');
  });
}
