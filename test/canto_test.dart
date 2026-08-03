import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
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

  test('identifica el mismo PDF por hash aunque cambien nombre y ruta', () {
    const hash =
        'b7a1e286850283027abb6538b22a2622f565537b3ca8268dd098e26008c63622';
    final local = Canto(
      id: 'local',
      nombre: 'Nombre de la iglesia',
      archivo: 'global/assets/pdf/$hash.enc',
      temas: const ['Local'],
      corosVinculados: const ['florido'],
      origen: 'local',
    );
    final estatal = Canto(
      id: 'estatal',
      nombre: 'Un nombre totalmente diferente',
      archivo: 'https://files.example/global/assets/pdf/$hash.enc?version=3',
      temas: const ['Estatal'],
      corosVinculados: const ['estatal'],
      origen: 'global',
    );

    expect(local.hasSamePdf(estatal), isTrue);
    expect(
      deduplicarCantosPorPdf(
        [estatal, local],
        sedeId: 'florido',
      ).single.id,
      'local',
    );
  });

  test('no combina cantos solo porque sus nombres sean iguales', () {
    final first = Canto(
      id: 'uno',
      nombre: 'Mismo nombre',
      archivo: 'local/florido/assets/pdf/uno.enc',
      temas: const [],
      corosVinculados: const ['florido'],
    );
    final second = Canto(
      id: 'dos',
      nombre: 'Mismo nombre',
      archivo: 'local/florido/assets/pdf/dos.enc',
      temas: const [],
      corosVinculados: const ['estatal'],
    );

    expect(
      deduplicarCantosPorPdf(
        [first, second],
        sedeId: 'florido',
      ),
      hasLength(2),
    );
  });
}
