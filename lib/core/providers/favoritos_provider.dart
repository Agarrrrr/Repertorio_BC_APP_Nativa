import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';

/// Provider ligero que persiste los IDs de los cantos favoritos por usuario.
class FavoritosNotifier extends Notifier<Set<String>> {
  String get _key => AppCache.userKey(
        'favoritos',
        SupabaseService.client.auth.currentUser?.id,
      );

  @override
  Set<String> build() {
    ref.watch(authUserProvider);
    final data = AppCache.get<List<dynamic>>(_key);
    if (data is List) {
      return data.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  void _persist() {
    AppCache.put(_key, state.toList());
  }

  void toggle(String cantoId) {
    final nuevo = Set<String>.from(state);
    if (nuevo.contains(cantoId)) {
      nuevo.remove(cantoId);
    } else {
      nuevo.add(cantoId);
    }
    state = nuevo;
    _persist();
  }

  bool esFavorito(String cantoId) => state.contains(cantoId);
}

final favoritosProvider =
    NotifierProvider<FavoritosNotifier, Set<String>>(FavoritosNotifier.new);

/// Filtro rápido "solo favoritos" para el chip del dashboard.
class SoloFavoritosNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final soloFavoritosProvider =
    NotifierProvider<SoloFavoritosNotifier, bool>(SoloFavoritosNotifier.new);
