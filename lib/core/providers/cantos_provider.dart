import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:hive/hive.dart';

// Provider base que descarga el catalogo de cantos desde Supabase
class CantosNotifier extends AsyncNotifier<List<Canto>> {
  RealtimeChannel? _channel;

  @override
  Future<List<Canto>> build() async {
    _setupRealtime();
    final box = Hive.box('cache');
    
    // 1. Carga inmediata desde caché (Offline-First)
    final cachedData = box.get('cantos_json');
    if (cachedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedData);
        final lista = decoded.map((e) => Canto.fromJson(e)).toList();
        lista.sort((a, b) => _naturalSort(_normalizar(a.nombre), _normalizar(b.nombre)));
        state = AsyncValue.data(lista); // Emitir data al instante
      } catch (e) {
        debugPrint('Error parsing cached cantos: $e');
      }
    }

    // 2. Carga desde la base de datos (Supabase) en background
    try {
      final response = await SupabaseService.client
          .from('cantos')
          .select('*, cantos_coros(coro_id), eventos_cantos(evento_id)');
          
      // Guardar el string en crudo para la proxima sesion
      box.put('cantos_json', jsonEncode(response));

      final lista = (response as List).map((e) => Canto.fromJson(e)).toList();
      // Ordenar usando natural sort para los numeros
      lista.sort((a, b) => _naturalSort(_normalizar(a.nombre), _normalizar(b.nombre)));
      
      // Emitir los nuevos datos
      return lista;
    } catch (e) {
      debugPrint('Error fetching cantos from DB: $e');
      // Si falla y teniamos state (del cache), devolvemos el viejo state para que no se sobreescriba con error
      if (state.hasValue) return state.value!;
      return [];
    }
  }

  void _setupRealtime() {
    if (_channel != null) return;
    _channel = SupabaseService.client
        .channel('db-changes')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cantos',
            callback: (payload) {
              ref.invalidateSelf();
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cantos_coros',
            callback: (payload) {
              ref.invalidateSelf();
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'eventos_cantos',
            callback: (payload) {
              ref.invalidateSelf();
            })
        .subscribe();
  }
}
final cantosBaseProvider = AsyncNotifierProvider<CantosNotifier, List<Canto>>(CantosNotifier.new);

// Filtro de texto (barra de busqueda)
class SearchTextNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}
final searchTextProvider = NotifierProvider<SearchTextNotifier, String>(SearchTextNotifier.new);

// Normalizacion de tildes (portado de JS)
String _normalizar(String str) {
  return str.toLowerCase()
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
final categoryFilterProvider = NotifierProvider<CategoryFilterNotifier, String>(CategoryFilterNotifier.new);

// Cantos filtrados reactivamente
final cantosFiltradosProvider = Provider<List<Canto>>((ref) {
  final cantosAsync = ref.watch(cantosBaseProvider);
  final query = ref.watch(searchTextProvider);
  final categoria = ref.watch(categoryFilterProvider);
  final perfilAsync = ref.watch(perfilProvider);
  
  if (cantosAsync.value == null || perfilAsync.isLoading) {
    return [];
  }

  final cantos = cantosAsync.value!;
  final perfil = perfilAsync.value;
  final queryNormalizada = _normalizar(query);

  final filtrados = cantos.where((canto) {
    // 1. Filtro por categoría (Sede local vs Estatal vs Tema)
    if (categoria == 'local') {
      // Permitir todo si el perfil es null para debug, o si esta vinculado
      if (perfil != null && !canto.corosVinculados.contains(perfil.coroId)) {
        return false;
      }
    } else if (categoria == 'estatal') {
      if (!canto.corosVinculados.contains('estatal')) return false;
    } else if (categoria.startsWith('evento_')) {
      // Pase de Invitado (Bypass de Sede)
      final eventoId = categoria.replaceFirst('evento_', '');
      if (!canto.eventosVinculados.contains(eventoId)) return false;
    } else if (categoria.startsWith('tema_')) {
      // Filtrar por tag y asegurar que el canto sea accesible (local o estatal)
      final temaABuscar = categoria.replaceFirst('tema_', '');
      final hasTema = canto.temas.any((t) => _normalizar(t) == _normalizar(temaABuscar));
      if (!hasTema) return false;
      
      // Restringir a scope del usuario
      final esLocal = perfil == null || canto.corosVinculados.contains(perfil.coroId);
      final esEstatal = canto.corosVinculados.contains('estatal');
      if (!esLocal && !esEstatal) return false;
    } else {
      // Por si hay otra categoria no manejada
      return false;
    }

    // 2. Filtro por busqueda de texto
    if (queryNormalizada.isNotEmpty) {
      final nNombre = _normalizar(canto.nombre);
      final nTemas = canto.temas.map((t) => _normalizar(t)).join(' ');
      
      final queryWords = queryNormalizada.split(' ');
      for (final word in queryWords) {
        if (!nNombre.contains(word) && !nTemas.contains(word)) return false;
      }
    }

    return true;
  }).toList();

  // 3. Ordenar resultados de busqueda por relevancia (si hay query)
  if (queryNormalizada.isNotEmpty) {
    filtrados.sort((a, b) {
      final nA = _normalizar(a.nombre);
      final nB = _normalizar(b.nombre);
      
      final nTemasA = a.temas.map((t) => _normalizar(t)).join(' ');
      final nTemasB = b.temas.map((t) => _normalizar(t)).join(' ');
      
      int scoreA = 0;
      int scoreB = 0;
      
      // Match en nombre
      if (nA == queryNormalizada) {
        scoreA += 200;
      } else if (nA.startsWith(queryNormalizada)) {
        scoreA += 100;
      } else if (nA.contains(queryNormalizada)) {
        scoreA += 50;
      }
      
      // Match en tags
      if (nTemasA.contains(queryNormalizada)) {
        scoreA += 30;
      }
      
      // Match en nombre
      if (nB == queryNormalizada) {
        scoreB += 200;
      } else if (nB.startsWith(queryNormalizada)) {
        scoreB += 100;
      } else if (nB.contains(queryNormalizada)) {
        scoreB += 50;
      }
      
      // Match en tags
      if (nTemasB.contains(queryNormalizada)) {
        scoreB += 30;
      }
      
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Mayor score primero
      }
      return _naturalSort(nA, nB); // Si empatan, natural sort
    });
  }

  return filtrados;
});

// Provider específico para descargas offline (evita bajar cantos de otras sedes)
final cantosDeLaSedeProvider = Provider<List<Canto>>((ref) {
  final cantosAsync = ref.watch(cantosBaseProvider);
  final perfilAsync = ref.watch(perfilProvider);
  
  if (cantosAsync.value == null || perfilAsync.isLoading) {
    return [];
  }

  final cantos = cantosAsync.value!;
  final perfil = perfilAsync.value;
  
  // Si no hay perfil, no descargamos nada por seguridad
  if (perfil == null) {
    return [];
  }

  return cantos.where((canto) {
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
});
