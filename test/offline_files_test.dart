import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/models/canto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un fork local resuelve su copia sin depender del canto global', () {
    final canto = Canto(
      id: '44444444-4444-4444-8444-444444444444',
      nombre: 'Nombre local',
      archivo: 'global/assets/pdf/heredado.enc',
      midiArchivo: 'global/assets/midi/heredado.enc',
      temas: const [],
      corosVinculados: const ['florido'],
      derivadoDe: '33333333-3333-4333-8333-333333333333',
    );

    expect(
      OfflineFiles.resolvePdfUrl(canto),
      contains('/v1/files/44444444-4444-4444-8444-444444444444/pdf'),
    );
    expect(
      OfflineFiles.resolveMidiUrl(canto),
      contains('/v1/files/44444444-4444-4444-8444-444444444444/midi'),
    );
  });
}
