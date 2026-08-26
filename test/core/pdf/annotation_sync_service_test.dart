import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/pdf/annotation_sync_service.dart';
import 'package:repertorio_bc/models/trazo.dart';

Trazo _stroke(String id, int modifiedAt, {double offset = 0}) => Trazo(
      tool: ToolType.pencil,
      color: const Color(0xff000000),
      size: 3,
      syncId: id,
      modifiedAtMs: modifiedAt,
      points: [
        PointNormalized(0.1 + offset, 0.2),
        PointNormalized(0.2 + offset, 0.3),
      ],
    );

void main() {
  test('fusiona trazos creados en dos dispositivos sin perder ninguno', () {
    final merged = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [_stroke('tablet', 10)]
      }),
      AnnotationDocument(pages: {
        1: [_stroke('telefono', 20, offset: 0.2)]
      }),
    );

    expect(
      merged.pages[1]!.map((item) => item.syncId),
      containsAll(<String>['tablet', 'telefono']),
    );
  });

  test('deduplica el mismo trazo recibido con IDs diferentes', () {
    final merged = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [_stroke('local', 10)]
      }),
      AnnotationDocument(pages: {
        1: [_stroke('remoto', 20)]
      }),
    );

    expect(merged.pages[1], hasLength(1));
    expect(merged.pages[1]!.single.syncId, 'local');
  });

  test('conserva trazos distintos aunque estén en la misma página', () {
    final merged = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [_stroke('local', 10)]
      }),
      AnnotationDocument(pages: {
        1: [_stroke('remoto', 20, offset: 0.01)]
      }),
    );

    expect(merged.pages[1], hasLength(2));
  });

  test('la versión local gana aunque la nube tenga una fecha posterior', () {
    final local = _stroke('mismo', 20)..size = 8;
    final remote = _stroke('mismo', 200)..size = 2;
    final merged = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [local]
      }),
      AnnotationDocument(pages: {
        1: [remote]
      }),
    );

    expect(merged.pages[1]!.single.size, 8);
  });

  test('una nube vacía no borra la copia local', () {
    final merged = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        2: [_stroke('local', 30)]
      }),
      const AnnotationDocument(),
    );

    expect(merged.pages[2]!.single.syncId, 'local');
  });

  test('una eliminación remota no borra un trazo conservado localmente', () {
    final kept = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [_stroke('nota', 50)]
      }),
      const AnnotationDocument(
        deletedAtByPage: {
          1: {'nota': 40}
        },
      ),
    );
    final protected = AnnotationSyncService.mergeForTesting(
      AnnotationDocument(pages: {
        1: [_stroke('nota', 50)]
      }),
      const AnnotationDocument(
        deletedAtByPage: {
          1: {'nota': 60}
        },
      ),
    );

    expect(kept.pages[1], hasLength(1));
    expect(protected.pages[1], hasLength(1));
  });

  test('serializar un trazo conserva su identidad de sincronización', () {
    final original = _stroke('estable', 123);
    final restored = Trazo.fromJson(original.toJson());

    expect(restored.syncId, 'estable');
    expect(restored.modifiedAtMs, 123);
  });
}
