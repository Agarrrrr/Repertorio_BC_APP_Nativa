import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Caché de la aplicación con respaldo en memoria.
///
/// Si Hive no puede abrirse o escribir (por ejemplo, almacenamiento lleno),
/// la aplicación sigue funcionando durante la sesión sin convertir un fallo
/// de persistencia en un fallo de inicio o de red.
class AppCache {
  AppCache._();

  static const String _boxName = 'cache';
  static final Map<String, dynamic> _memory = <String, dynamic>{};
  static Box<dynamic>? _box;

  static bool get isPersistent => _box != null;

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (error) {
      _box = null;
      debugPrint(
        '[AppCache] Persistencia no disponible; se usará memoria: $error',
      );
    }
  }

  static T? get<T>(String key, {T? defaultValue}) {
    if (_memory.containsKey(key)) return _memory[key] as T?;
    try {
      final value = _box?.get(key);
      return value == null ? defaultValue : value as T;
    } catch (error) {
      debugPrint('[AppCache] No se pudo leer $key: $error');
      return defaultValue;
    }
  }

  static Future<void> put(String key, dynamic value) async {
    _memory[key] = value;
    try {
      await _box?.put(key, value);
    } catch (error) {
      debugPrint('[AppCache] $key permanecerá solo en memoria: $error');
    }
  }

  static Future<void> delete(String key) async {
    _memory.remove(key);
    try {
      await _box?.delete(key);
    } catch (error) {
      debugPrint('[AppCache] No se pudo borrar $key de disco: $error');
    }
  }

  static String userKey(
    String key,
    String? userId, {
    String? scope,
  }) {
    final owner = userId?.trim().isNotEmpty == true ? userId! : 'anonimo';
    final suffix = scope?.trim().isNotEmpty == true ? ':$scope' : '';
    return 'user:$owner:$key$suffix';
  }

  static Future<void> clearUser(String userId) async {
    await deletePrefix('user:$userId:');
  }

  static Future<void> deletePrefix(String prefix) async {
    final keys = <String>{
      ..._memory.keys.where((key) => key.startsWith(prefix)),
      ...?_box?.keys.whereType<String>().where((key) => key.startsWith(prefix)),
    };
    for (final key in keys) {
      await delete(key);
    }
  }

  @visibleForTesting
  static void useMemoryOnlyForTests([Map<String, dynamic>? values]) {
    _box = null;
    _memory
      ..clear()
      ..addAll(values ?? const <String, dynamic>{});
  }
}
