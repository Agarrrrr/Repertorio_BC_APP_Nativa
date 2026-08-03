import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/offline/offline_files.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'dart:convert';

// Funciones puras para procesar datos en Isolate
List<Canto> _parseCantosJsonString(String jsonString) {
  final List<dynamic> decoded = jsonDecode(jsonString);
  return _parseCantosList(decoded);
}

List<Canto> _parseCantosList(List<dynamic> data) {
  final lista = data.map((e) => Canto.fromJson(e)).toList();
  lista.sort(
      (a, b) => _naturalSort(_normalizar(a.nombre), _normalizar(b.nombre)));
  return lista;
}

/// Elimina copias que apuntan al mismo PDF sin comparar nombres. Cuando una
/// copia local y una estatal comparten el asset, conserva la copia de la sede.
List<Canto> deduplicarCantosPorPdf(
  List<Canto> cantos, {
  required String? sedeId,
}) {
  final byAsset = <String, Canto>{};
  for (final canto in cantos) {
    final key = canto.pdfIdentity;
    final current = byAsset[key];
    if (current == null ||
        _prioridadParaSede(canto, sedeId) >
            _prioridadParaSede(current, sedeId)) {
      byAsset[key] = canto;
    }
  }
  return byAsset.values.toList();
}

@visibleForTesting
List<Canto> resolveCatalogResult({
  required List<Canto> server,
  required List<Canto> cached,
  required bool requestSucceeded,
}) {
  return requestSucceeded ? server : cached;
}

int _prioridadParaSede(Canto canto, String? sedeId) {
  final local = sedeId != null && canto.corosVinculados.contains(sedeId);
  if (local && canto.origen == 'local') return 4;
  if (local) return 3;
  if (canto.corosVinculados.contains('estatal')) return 2;
  return 1;
}

Future<List<dynamic>> _fetchCompatibleCatalog(String sedeId) async {
  final rowsByCanto = <String, Map<String, dynamic>>{};
  const pageSize = 250;
  final sedes = <String>{sedeId, 'estatal'}.toList();

  for (var from = 0;; from += pageSize) {
    final page = await SupabaseService.client
        .from('cantos_coros')
        .select('coro_id,cantos(*,eventos_cantos(evento_id))')
        .inFilter('coro_id', sedes)
        .range(from, from + pageSize - 1);
    final relations = List<Map<String, dynamic>>.from(page);
    for (final relation in relations) {
      final rawSong = relation['cantos'];
      if (rawSong is! Map) continue;
      final song = Map<String, dynamic>.from(rawSong);
      final id = song['id']?.toString();
      final coroId = relation['coro_id']?.toString();
      if (id == null || coroId == null) continue;
      final existing = rowsByCanto.putIfAbsent(id, () => song);
      final linked = <String>{
        ...((existing['coros_vinculados'] as List?) ?? const [])
            .map((value) => value.toString()),
        coroId,
      };
      existing['coros_vinculados'] = linked.toList();
    }
    if (relations.length < pageSize) break;
  }
  return rowsByCanto.values.toList();
}

// Provider base que descarga el catalogo de cantos desde Supabase
class CantosNotifier extends AsyncNotifier<List<Canto>> {
  @override
  Future<List<Canto>> build() async {
    final perfil = ref.watch(perfilProvider).value;
    final userId = SupabaseService.client.auth.currentUser?.id ?? 'sin_usuario';
    final cacheKey = AppCache.userKey(
      'cantos_json',
      userId,
      scope: perfil?.coroId ?? 'sin_sede',
    );

    // 1. Carga inmediata desde caché (Offline-First)
    var cachedData = AppCache.get<String>(cacheKey);
    final legacyKey = 'cantos_json_${userId}_${perfil?.coroId ?? 'sin_sede'}';
    if (cachedData == null) {
      cachedData = AppCache.get<String>(legacyKey);
      if (cachedData != null) {
        await AppCache.put(cacheKey, cachedData);
        await AppCache.delete(legacyKey);
      }
    }
    if (cachedData != null) {
      try {
        final lista = await compute(_parseCantosJsonString, cachedData);
        state = AsyncValue.data(lista); // Emitir data al instante
      } catch (e) {
        debugPrint('Error parsing cached cantos: $e');
      }
    }

    // 2. Carga desde la base de datos (Supabase) en background
    try {
      List<dynamic> response;
      try {
        final unified =
            await SupabaseService.client.rpc('mis_cantos_disponibles');
        response = unified as List<dynamic>;
        if (response.isEmpty && perfil != null && perfil.coroId.isNotEmpty) {
          response = await _fetchCompatibleCatalog(perfil.coroId);
        }
      } catch (error) {
        debugPrint('Usando consulta compatible de catálogo: $error');
        if (perfil == null || perfil.coroId.isEmpty) {
          if (state.hasValue) return state.value!;
          return [];
        }
        response = await _fetchCompatibleCatalog(perfil.coroId);
      }

      final lista = await compute(_parseCantosList, response);

      // El almacenamiento puede estar lleno. El catálogo en línea sigue
      // siendo utilizable durante toda la sesión aunque no pueda persistirse.
      try {
        await AppCache.put(cacheKey, jsonEncode(response));
      } catch (error) {
        debugPrint(
          'No se pudo guardar el catálogo en caché; se conserva en RAM: $error',
        );
      }

      await OfflineFiles.reconcileAuthorized(lista);

      // Emitir los nuevos datos
      return resolveCatalogResult(
        server: lista,
        cached: state.value ?? const <Canto>[],
        requestSucceeded: true,
      );
    } catch (e) {
      debugPrint('Error fetching cantos from DB: $e');
      // Si falla y teniamos state (del cache), devolvemos el viejo state para que no se sobreescriba con error
      return resolveCatalogResult(
        server: const <Canto>[],
        cached: state.value ?? const <Canto>[],
        requestSucceeded: false,
      );
    }
  }
}

final cantosBaseProvider =
    AsyncNotifierProvider<CantosNotifier, List<Canto>>(CantosNotifier.new);

// Filtro de texto (barra de busqueda)
class SearchTextNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final searchTextProvider =
    NotifierProvider<SearchTextNotifier, String>(SearchTextNotifier.new);

// Normalizacion de tildes (portado de JS)
String _normalizar(String str) {
  return str
      .toLowerCase()
      .replaceAll(RegExp(r'[áäâà]'), 'a')
      .replaceAll(RegExp(r'[éëêè]'), 'e')
      .replaceAll(RegExp(r'[íïîì]'), 'i')
      .replaceAll(RegExp(r'[óöôò]'), 'o')
      .replaceAll(RegExp(r'[úüûù]'), 'u')
      .replaceAll('ñ', 'n')
      .trim();
}

int _naturalSort(String a, String b) {
  final regex = RegExp(r'(\d+|\D+)');
  final matchesA = regex.allMatches(a).map((m) => m.group(0)!).toList();
  final matchesB = regex.allMatches(b).map((m) => m.group(0)!).toList();

  for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
    final partA = matchesA[i];
    final partB = matchesB[i];

    final numA = int.tryParse(partA);
    final numB = int.tryParse(partB);

    if (numA != null && numB != null) {
      final cmp = numA.compareTo(numB);
      if (cmp != 0) return cmp;
    } else {
      final cmp = partA.compareTo(partB);
      if (cmp != 0) return cmp;
    }
  }
  return matchesA.length.compareTo(matchesB.length);
}

// Categoria actual: 'local', 'estatal', o un ev_ID de un evento
class CategoryFilterNotifier extends Notifier<String> {
  @override
  String build() => 'local';
  void set(String value) => state = value;
}

final categoryFilterProvider = NotifierProvider<CategoryFilterNotifier, String>(
    CategoryFilterNotifier.new);

class FilterParams {
  final List<Canto> cantos;
  final String query;
  final String categoria;
  final String? perfilCoroId;
  FilterParams(
      {required this.cantos,
      required this.query,
      required this.categoria,
      this.perfilCoroId});
}

// Algoritmo de distancia de Levenshtein (Fuzzy Search)
int _levenshtein(String s, String t) {
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  int n = s.length;
  int m = t.length;
  List<List<int>> d = List.generate(n + 1, (i) => List.filled(m + 1, 0));

  for (int i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (int j = 0; j <= m; j++) {
    d[0][j] = j;
  }

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      int cost = s[i - 1] == t[j - 1] ? 0 : 1;
      d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost]
          .reduce((min, val) => val < min ? val : min);
    }
  }
  return d[n][m];
}

// Lógica pura de filtrado extraída a nivel superior para el Isolate
List<Canto> _filterAndSortCantosEnIsolate(FilterParams params) {
  final queryNormalizada = _normalizar(params.query);
  final queryWords =
      queryNormalizada.isEmpty ? <String>[] : queryNormalizada.split(' ');

  var filtrados = params.cantos.where((canto) {
    // La búsqueda nunca debe saltar al repertorio de otra sede.
    final perteneceALaSede = params.perfilCoroId != null &&
        (canto.corosVinculados.contains(params.perfilCoroId) ||
            canto.corosVinculados.contains('estatal'));
    if (!perteneceALaSede) return false;

    // 1. Si la barra de búsqueda tiene texto: Búsqueda Global en TODOS los cantos del catálogo
    if (queryWords.isNotEmpty) {
      final nNombre = _normalizar(canto.nombre);
      final nTemas = canto.temas.map((t) => _normalizar(t)).join(' ');

      for (final word in queryWords) {
        if (word.length <= 2) {
          // Búsqueda exacta para palabras cortas (ej. "el", "yo", "fe", "salmo")
          if (!nNombre.contains(word) && !nTemas.contains(word)) {
            return false;
          }
        } else {
          // Búsqueda difusa para palabras más largas
          bool match = nNombre.contains(word) || nTemas.contains(word);
          if (!match) {
            final titleWords = nNombre.split(' ');
            for (final tw in titleWords) {
              if (tw.length >= word.length - 1) {
                int distance = _levenshtein(word, tw);
                int allowedErrors = word.length >= 5 ? 2 : 1;
                if (distance <= allowedErrors) {
                  match = true;
                  break;
                }
              }
            }
          }
          if (!match) {
            return false;
          }
        }
      }
      return true; // Coincide con la búsqueda global en cualquier carpeta o tema
    }

    // 2. Si la búsqueda está VACÍA: Filtrar estrictamente según la carpeta o categoría seleccionada
    final esLocal = params.perfilCoroId != null &&
        canto.corosVinculados.contains(params.perfilCoroId);
    final esEstatal = canto.corosVinculados.contains('estatal');

    if (params.categoria == 'local') {
      if (!esLocal) return false;
    } else if (params.categoria == 'estatal') {
      if (!esEstatal) return false;
    } else if (params.categoria.startsWith('evento_')) {
      final eventoId = params.categoria.replaceFirst('evento_', '');
      if (!canto.eventosVinculados.contains(eventoId)) return false;
    } else if (params.categoria.startsWith('tema_')) {
      final temaABuscar = params.categoria.replaceFirst('tema_', '');
      final hasTema =
          canto.temas.any((t) => _normalizar(t) == _normalizar(temaABuscar));
      if (!hasTema) return false;
    } else {
      return false;
    }

    return true;
  }).toList();

  if (queryNormalizada.isNotEmpty) {
    filtrados = deduplicarCantosPorPdf(
      filtrados,
      sedeId: params.perfilCoroId,
    );
  }

  // 3. Ordenar resultados por relevancia
  if (queryNormalizada.isNotEmpty) {
    filtrados.sort((a, b) {
      final nA = _normalizar(a.nombre);
      final nB = _normalizar(b.nombre);
      final nTemasA = a.temas.map((t) => _normalizar(t)).join(' ');
      final nTemasB = b.temas.map((t) => _normalizar(t)).join(' ');

      int scoreA = 0;
      int scoreB = 0;

      if (nA == queryNormalizada) {
        scoreA += 200;
      } else if (nA.startsWith(queryNormalizada)) {
        scoreA += 100;
      } else if (nA.contains(queryNormalizada)) {
        scoreA += 50;
      }
      if (nTemasA.contains(queryNormalizada)) {
        scoreA += 30;
      }

      if (nB == queryNormalizada) {
        scoreB += 200;
      } else if (nB.startsWith(queryNormalizada)) {
        scoreB += 100;
      } else if (nB.contains(queryNormalizada)) {
        scoreB += 50;
      }
      if (nTemasB.contains(queryNormalizada)) {
        scoreB += 30;
      }

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      return _naturalSort(nA, nB);
    });
  }

  return filtrados;
}

// Cantos filtrados reactivamente vía Isolate
final cantosFiltradosProvider = FutureProvider<List<Canto>>((ref) async {
  final cantosAsync = ref.watch(cantosBaseProvider);
  final query = ref.watch(searchTextProvider);
  final categoria = ref.watch(categoryFilterProvider);
  final perfilAsync = ref.watch(perfilProvider);

  if (cantosAsync.value == null || perfilAsync.isLoading) {
    return [];
  }

  final cantos = cantosAsync.value!;
  final perfil = perfilAsync.value;

  final params = FilterParams(
    cantos: cantos,
    query: query,
    categoria: categoria,
    perfilCoroId: perfil?.coroId,
  );

  return await compute(_filterAndSortCantosEnIsolate, params);
});

// Provider específico para descargas offline (evita bajar cantos de otras sedes)
final cantosOfflineStateProvider = Provider<AsyncValue<List<Canto>>>((ref) {
  final cantosAsync = ref.watch(cantosBaseProvider);
  final perfilAsync = ref.watch(perfilProvider);

  if (cantosAsync.value == null || perfilAsync.isLoading) {
    return const AsyncValue.loading();
  }

  final cantos = cantosAsync.value!;
  final perfil = perfilAsync.value;

  // Si no hay perfil, no descargamos nada por seguridad
  if (perfil == null) {
    return const AsyncValue.data([]);
  }

  final permitidos = cantos.where((canto) {
    // Es de la sede local del usuario
    if (canto.corosVinculados.contains(perfil.coroId)) {
      return true;
    }
    // O es un canto Estatal
    if (canto.corosVinculados.contains('estatal')) {
      return true;
    }
    return false;
  }).toList();

  return AsyncValue.data(deduplicarCantosPorPdf(
    permitidos,
    sedeId: perfil.coroId,
  ));
});

final cantosDeLaSedeProvider = Provider<List<Canto>>((ref) {
  return ref.watch(cantosOfflineStateProvider).value ?? [];
});
