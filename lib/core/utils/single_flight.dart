/// Comparte una operación en curso entre todos los consumidores de la misma
/// llave. Evita que visor y sincronizador escriban el mismo archivo a la vez.
class SingleFlight<T> {
  final Map<String, Future<T>> _active = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() operation) {
    final current = _active[key];
    if (current != null) return current;

    final future = operation();
    _active[key] = future;
    future.whenComplete(() {
      if (identical(_active[key], future)) _active.remove(key);
    }).ignore();
    return future;
  }
}
