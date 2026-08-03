import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/models/canto.dart';

Canto song(String id) => Canto(
      id: id,
      nombre: 'Canto $id',
      archivo: '$id.pdf',
      temas: const [],
      corosVinculados: const ['estatal'],
    );

void main() {
  test('un catálogo vacío confirmado retira el catálogo anterior', () {
    final result = resolveCatalogResult(
      server: const [],
      cached: [song('anterior')],
      requestSucceeded: true,
    );

    expect(result, isEmpty);
  });

  test('un fallo de red conserva el catálogo anterior', () {
    final cached = [song('anterior')];
    final result = resolveCatalogResult(
      server: const [],
      cached: cached,
      requestSucceeded: false,
    );

    expect(result, same(cached));
  });
}
