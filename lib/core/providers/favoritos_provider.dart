import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Provider ligero que persiste los IDs de los cantos favoritos en Hive.
///
/// Caja: `favoritos_box`, llave: `favoritos` (List<String> de IDs).
class FavoritosNotifier extends Notifier<Set<String>> {
  static const String boxName = 'favoritos_box';
  static const String key = 'favoritos';

  @override
  Set<String> build() {
    final box = Hive.box(boxName);
    final data = box.get(key);
    if (data is List) {
      return data.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  void _persist() {
    Hive.box(boxName).put(key, state.toList());
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
