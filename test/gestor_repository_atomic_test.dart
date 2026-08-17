import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/features/gestor/gestor_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<(String, Map<String, dynamic>)> calls;
  late GestorRepository repository;

  setUp(() {
    calls = [];
    repository = GestorRepository(
      client: SupabaseClient('https://example.supabase.co', 'anon-key'),
      rpc: (function, params) async {
        calls.add((function, params));
        if (function == 'guardar_canto_local_atomico') {
          return {
            'id': '11111111-1111-4111-8111-111111111111',
            'nombre': params['p_nombre'],
            'archivo': params['p_archivo'],
            'temas': params['p_temas'],
            'origen': 'local',
            'version': 1,
          };
        }
      },
      audit: (_, __, ___) async {},
    );
  });

  test('guardar una partitura usa una sola mutación transaccional', () async {
    await repository.guardarLocal(
      sedeId: 'florido',
      nombre: 'Prueba',
      temas: const ['Ensayo'],
      archivo: 'local/florido/assets/pdf/hash.enc',
    );

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'guardar_canto_local_atomico');
  });

  test('reemplazar cantos de evento usa una sola mutación', () async {
    await repository.guardarCantosEvento(
      '22222222-2222-4222-8222-222222222222',
      const ['11111111-1111-4111-8111-111111111111'],
    );

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'guardar_cantos_evento_atomico');
  });
}
