import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';

void main() {
  setUp(AppCache.useMemoryOnlyForTests);

  test('continúa leyendo y escribiendo cuando solo hay memoria', () async {
    await AppCache.put('catalogo', 'disponible');

    expect(AppCache.isPersistent, isFalse);
    expect(AppCache.get<String>('catalogo'), 'disponible');
  });

  test('aísla y limpia únicamente las llaves del usuario que sale', () async {
    final first = AppCache.userKey('perfil', 'usuario-a');
    final second = AppCache.userKey('perfil', 'usuario-b');
    await AppCache.put(first, 'A');
    await AppCache.put(second, 'B');

    await AppCache.clearUser('usuario-a');

    expect(AppCache.get<String>(first), isNull);
    expect(AppCache.get<String>(second), 'B');
  });
}
