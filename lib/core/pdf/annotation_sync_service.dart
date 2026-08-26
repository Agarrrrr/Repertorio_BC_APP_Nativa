import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/trazo.dart';

class AnnotationDocument {
  final Map<int, List<Trazo>> pages;
  final Map<int, Map<String, int>> deletedAtByPage;

  const AnnotationDocument({
    this.pages = const {},
    this.deletedAtByPage = const {},
  });

  bool get isEmpty =>
      pages.values.every((items) => items.isEmpty) &&
      deletedAtByPage.values.every((items) => items.isEmpty);
}

/// Sincroniza anotaciones por usuario, canto y página.
///
/// La caché local siempre se escribe primero. La nube se fusiona por ID de
/// trazo y fecha de modificación; nunca se sustituye el documento local por un
/// snapshot remoto completo. Las eliminaciones se conservan como tombstones.
class AnnotationSyncService {
  AnnotationSyncService._();

  static String _cacheKey(String userId, String cantoId) =>
      AppCache.userKey('anotaciones_v2', userId, scope: cantoId);

  static Future<String> _deviceId() async {
    const key = 'annotation_device_id_v1';
    final existing = AppCache.get<String>(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = 'device-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await AppCache.put(key, generated);
    return generated;
  }

  @visibleForTesting
  static AnnotationDocument mergeForTesting(
    AnnotationDocument local,
    AnnotationDocument remote,
  ) =>
      _merge(local, remote);

  static Future<AnnotationDocument> loadAndMerge({
    required String userId,
    required String cantoId,
  }) async {
    final local = _readLocal(userId, cantoId);
    AnnotationDocument remote = const AnnotationDocument();

    try {
      final rows = await SupabaseService.client
          .from('anotaciones')
          .select('pagina,trazos,actualizado_en')
          .eq('usuario_id', userId)
          .eq('canto_id', cantoId);
      remote = _fromRows(List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      debugPrint('[AnnotationSync] Se usará la copia local: $error');
    }

    final merged = _merge(local, remote);
    await _writeLocal(userId, cantoId, merged);

    // Si había datos en cualquiera de los dos lados, normalizamos la nube con
    // el resultado fusionado. Un fallo aquí no afecta a la copia local.
    if (!merged.isEmpty) {
      await _uploadBestEffort(userId, cantoId, merged);
    }
    return merged;
  }

  static Future<AnnotationDocument> cacheLocal({
    required String userId,
    required String cantoId,
    required Map<int, List<Trazo>> pages,
  }) async {
    final previous = _readLocal(userId, cantoId);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final deleted = <int, Map<String, int>>{
      for (final entry in previous.deletedAtByPage.entries)
        entry.key: Map<String, int>.from(entry.value),
    };

    for (final entry in previous.pages.entries) {
      final currentIds = (pages[entry.key] ?? const <Trazo>[])
          .map((trazo) => trazo.syncId)
          .toSet();
      for (final old in entry.value) {
        if (!currentIds.contains(old.syncId)) {
          (deleted[entry.key] ??= <String, int>{})[old.syncId] = now;
        }
      }
    }
    for (final entry in pages.entries) {
      final tombstones = deleted[entry.key];
      if (tombstones == null) continue;
      for (final trazo in entry.value) {
        tombstones.remove(trazo.syncId);
      }
    }

    final local = AnnotationDocument(
      pages: _copyPages(pages),
      deletedAtByPage: deleted,
    );
    await _writeLocal(userId, cantoId, local);
    return local;
  }

  static Future<AnnotationDocument> syncCached({
    required String userId,
    required String cantoId,
  }) async {
    final local = _readLocal(userId, cantoId);
    // Leer y fusionar antes de escribir impide borrar trazos creados en otro
    // dispositivo mientras este equipo estaba desconectado.
    try {
      final rows = await SupabaseService.client
          .from('anotaciones')
          .select('pagina,trazos,actualizado_en')
          .eq('usuario_id', userId)
          .eq('canto_id', cantoId);
      final merged =
          _merge(local, _fromRows(List<Map<String, dynamic>>.from(rows)));
      await _writeLocal(userId, cantoId, merged);
      await _upload(userId, cantoId, merged);
      return merged;
    } catch (error) {
      debugPrint('[AnnotationSync] Guardado local pendiente de nube: $error');
      return local;
    }
  }

  static AnnotationDocument _readLocal(String userId, String cantoId) {
    final raw = AppCache.get<String>(_cacheKey(userId, cantoId));
    if (raw == null || raw.isEmpty) return const AnnotationDocument();
    try {
      return _fromEnvelope(jsonDecode(raw));
    } catch (error) {
      debugPrint('[AnnotationSync] Caché local inválida; se conserva: $error');
      return const AnnotationDocument();
    }
  }

  static Future<void> _writeLocal(
    String userId,
    String cantoId,
    AnnotationDocument document,
  ) =>
      AppCache.put(
        _cacheKey(userId, cantoId),
        jsonEncode(_toEnvelope(document)),
      );

  static AnnotationDocument _fromRows(List<Map<String, dynamic>> rows) {
    var document = const AnnotationDocument();
    for (final row in rows) {
      final page = (row['pagina'] as num?)?.toInt();
      if (page == null) continue;
      final payload = row['trazos'];
      if (payload is List) {
        // Compatibilidad con filas creadas antes del formato versionado.
        final items = payload
            .whereType<Map>()
            .map((item) => Trazo.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        document = _merge(
          document,
          AnnotationDocument(pages: {page: items}),
        );
        continue;
      }
      if (payload is Map) {
        final envelope = _fromEnvelope({
          'pages': {page.toString(): payload['items'] ?? const []},
          'deleted': {page.toString(): payload['deleted'] ?? const {}},
        });
        document = _merge(document, envelope);
      }
    }
    return document;
  }

  static AnnotationDocument _fromEnvelope(dynamic raw) {
    if (raw is! Map) return const AnnotationDocument();
    final map = Map<String, dynamic>.from(raw);
    final pages = <int, List<Trazo>>{};
    final rawPages = map['pages'];
    if (rawPages is Map) {
      for (final entry in rawPages.entries) {
        final page = int.tryParse(entry.key.toString());
        if (page == null || entry.value is! List) continue;
        pages[page] = (entry.value as List)
            .whereType<Map>()
            .map((item) => Trazo.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }
    final deleted = <int, Map<String, int>>{};
    final rawDeleted = map['deleted'];
    if (rawDeleted is Map) {
      for (final entry in rawDeleted.entries) {
        final page = int.tryParse(entry.key.toString());
        if (page == null || entry.value is! Map) continue;
        deleted[page] = {
          for (final tombstone in (entry.value as Map).entries)
            if (tombstone.value is num)
              tombstone.key.toString(): (tombstone.value as num).toInt(),
        };
      }
    }
    return AnnotationDocument(pages: pages, deletedAtByPage: deleted);
  }

  static Map<String, dynamic> _toEnvelope(AnnotationDocument document) => {
        'version': 2,
        'pages': {
          for (final entry in document.pages.entries)
            entry.key.toString():
                entry.value.map((item) => item.toJson()).toList(),
        },
        'deleted': {
          for (final entry in document.deletedAtByPage.entries)
            entry.key.toString(): entry.value,
        },
      };

  static AnnotationDocument _merge(
    AnnotationDocument local,
    AnnotationDocument remote,
  ) {
    final pageNumbers = <int>{
      ...local.pages.keys,
      ...remote.pages.keys,
      ...local.deletedAtByPage.keys,
      ...remote.deletedAtByPage.keys,
    };
    final pages = <int, List<Trazo>>{};
    final deleted = <int, Map<String, int>>{};

    for (final page in pageNumbers) {
      final items = <String, Trazo>{};
      for (final item in remote.pages[page] ?? const <Trazo>[]) {
        items[item.syncId] = item;
      }
      final localItems = local.pages[page] ?? const <Trazo>[];
      final localIds = localItems.map((item) => item.syncId).toSet();
      for (final item in localItems) {
        // Si el dispositivo conserva el trazo, su copia manda incluso cuando
        // la nube tenga otra fecha. Así una desincronización no borra ni
        // reemplaza silenciosamente trabajo local.
        items[item.syncId] = item;
      }

      final tombstones = <String, int>{};
      for (final source in [
        remote.deletedAtByPage[page] ?? const <String, int>{},
        local.deletedAtByPage[page] ?? const <String, int>{},
      ]) {
        for (final entry in source.entries) {
          final previous = tombstones[entry.key] ?? 0;
          if (entry.value > previous) tombstones[entry.key] = entry.value;
        }
      }
      items.removeWhere((id, item) =>
          !localIds.contains(id) && (tombstones[id] ?? 0) >= item.modifiedAtMs);
      final mergedItems = <Trazo>[];
      // Primero se agregan los locales: si existe un duplicado remoto, la
      // geometría y el ID local son los que se conservan.
      for (final item in localItems) {
        if (items.containsKey(item.syncId)) mergedItems.add(item);
      }
      final remoteOnly = items.values
          .where((item) => !localIds.contains(item.syncId))
          .toList()
        ..sort((a, b) => a.modifiedAtMs.compareTo(b.modifiedAtMs));
      for (final candidate in remoteOnly) {
        if (mergedItems.any((item) => _areNearDuplicates(item, candidate))) {
          continue;
        }
        mergedItems.add(candidate);
      }
      pages[page] = mergedItems;
      deleted[page] = tombstones;
    }
    return AnnotationDocument(pages: pages, deletedAtByPage: deleted);
  }

  static bool _areNearDuplicates(Trazo a, Trazo b) {
    if (a.tool != b.tool ||
        !_sameColor(a, b) ||
        (a.size - b.size).abs() > 0.15) {
      return false;
    }
    if (a.tool == ToolType.text) {
      final aText = (a.texto ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      final bText = (b.texto ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (aText != bText || a.pos == null || b.pos == null) return false;
      return _pointDistanceSquared(a.pos!, b.pos!) <= 0.000009;
    }
    if (a.points.length != b.points.length || a.points.isEmpty) return false;
    // Tolerancia máxima de 0.1% del tamaño de página por punto. Es suficiente
    // para redondeos de serialización, pero no combina trazos cercanos reales.
    for (var index = 0; index < a.points.length; index++) {
      if (_pointDistanceSquared(a.points[index], b.points[index]) > 0.000001) {
        return false;
      }
    }
    return true;
  }

  static bool _sameColor(Trazo a, Trazo b) =>
      a.color.a == b.color.a &&
      a.color.r == b.color.r &&
      a.color.g == b.color.g &&
      a.color.b == b.color.b;

  static double _pointDistanceSquared(PointNormalized a, PointNormalized b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }

  static Future<void> _uploadBestEffort(
    String userId,
    String cantoId,
    AnnotationDocument document,
  ) async {
    try {
      await _upload(userId, cantoId, document);
    } catch (error) {
      debugPrint('[AnnotationSync] La nube se actualizará después: $error');
    }
  }

  static Future<void> _upload(
    String userId,
    String cantoId,
    AnnotationDocument document,
  ) async {
    final deviceId = await _deviceId();
    final pageNumbers = <int>{
      ...document.pages.keys,
      ...document.deletedAtByPage.keys,
    };
    if (pageNumbers.isEmpty) return;
    for (final page in pageNumbers) {
      final row = {
        'usuario_id': userId,
        'canto_id': cantoId,
        'pagina': page,
        'dispositivo_id': deviceId,
        'trazos': {
          'version': 2,
          'items': (document.pages[page] ?? const <Trazo>[])
              .map((item) => item.toJson())
              .toList(),
          'deleted': document.deletedAtByPage[page] ?? const <String, int>{},
        },
        'actualizado_en': DateTime.now().toUtc().toIso8601String(),
      };
      final existing = await SupabaseService.client
          .from('anotaciones')
          .select('id')
          .eq('usuario_id', userId)
          .eq('canto_id', cantoId)
          .eq('pagina', page)
          .eq('dispositivo_id', deviceId);
      if ((existing as List).isEmpty) {
        await SupabaseService.client.from('anotaciones').insert(row);
      } else {
        // Si existen duplicados históricos, todos reciben el mismo documento
        // fusionado. No se elimina ninguna fila ni ningún trazo.
        await SupabaseService.client
            .from('anotaciones')
            .update(row)
            .eq('usuario_id', userId)
            .eq('canto_id', cantoId)
            .eq('pagina', page)
            .eq('dispositivo_id', deviceId);
      }
    }
  }

  static Map<int, List<Trazo>> _copyPages(Map<int, List<Trazo>> source) => {
        for (final entry in source.entries)
          entry.key: entry.value.map((item) => item.copyWith()).toList(),
      };
}
