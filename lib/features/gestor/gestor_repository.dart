import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:repertorio_bc/core/security/file_crypto.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestorMetrics {
  final int miembros;
  final int activosSemana;
  final int notificaciones;
  final int offline;
  final int repertorio;
  final int conMidi;
  final Map<String, int> voces;
  final List<Map<String, dynamic>> topCantos;
  final List<Map<String, dynamic>> errores;
  final List<Map<String, dynamic>> auditoria;

  const GestorMetrics({
    required this.miembros,
    required this.activosSemana,
    required this.notificaciones,
    required this.offline,
    required this.repertorio,
    required this.conMidi,
    required this.voces,
    required this.topCantos,
    required this.errores,
    required this.auditoria,
  });
}

class GestorRepository {
  GestorRepository({SupabaseClient? client})
      : client = client ?? SupabaseService.client;

  final SupabaseClient client;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  static const int _pageSize = 250;

  Future<List<Map<String, dynamic>>> sedes() async {
    final rows = await client
        .from('coros')
        .select('id,nombre,municipio')
        .order('municipio')
        .order('nombre');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Canto>> repertorio(String sedeId) async {
    final relations = <Map<String, dynamic>>[];
    for (var from = 0;; from += _pageSize) {
      final page = await client
          .from('cantos_coros')
          .select('cantos(*)')
          .eq('coro_id', sedeId)
          .range(from, from + _pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      relations.addAll(rows);
      if (rows.length < _pageSize) break;
    }
    return relations
        .map((row) => row['cantos'])
        .whereType<Map<String, dynamic>>()
        .map((row) => Canto.fromJson({
              ...row,
              'coros_vinculados': [sedeId],
            }))
        .toList()
      ..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  Future<List<Canto>> catalogoGlobal() async {
    final rows = <Map<String, dynamic>>[];
    for (var from = 0;; from += _pageSize) {
      final page = await client
          .rpc('catalogo_global_bilingue')
          .range(from, from + _pageSize - 1);
      final values = List<Map<String, dynamic>>.from(page);
      rows.addAll(values);
      if (values.length < _pageSize) break;
    }
    return rows
        .where((row) => (row['idioma'] ?? 'es') == 'es')
        .map(Canto.fromJson)
        .toList();
  }

  Future<List<Map<String, dynamic>>> miembros(String sedeId) async {
    final rows = await client
        .from('perfiles')
        .select(
            'id,nombre,email,rol,estado,voz,ultimo_acceso,offline_ready,notificaciones_activas')
        .eq('coro_id', sedeId)
        .order('nombre');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<GestorMetrics> metricas(
    String sedeId, {
    List<Canto>? cantos,
    List<Map<String, dynamic>>? perfiles,
  }) async {
    final roster = perfiles ?? await miembros(sedeId);
    final songs = cantos ?? await repertorio(sedeId);
    final ids = roster.map((p) => p['id'].toString()).toSet();
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final analyticsCutoff =
        DateTime.now().toUtc().subtract(const Duration(days: 30));
    final supplemental = await Future.wait([
      client
          .from('telemetria_vistas')
          .select('canto_id,fecha')
          .eq('coro_id', sedeId)
          .gte('fecha', analyticsCutoff.toIso8601String())
          .limit(5000),
      client
          .from('errores_app')
          .select('mensaje,fecha,url')
          .eq('coro_id', sedeId)
          .order('fecha', ascending: false)
          .limit(5),
      client
          .from('auditoria')
          .select('accion,detalles,fecha')
          .order('fecha', ascending: false)
          .limit(100),
    ]);

    var subscriptions = <String>{};
    if (ids.isNotEmpty) {
      final rows = await client
          .from('suscripciones_push')
          .select('usuario_id,endpoint')
          .inFilter('usuario_id', ids.toList());
      subscriptions = List<Map<String, dynamic>>.from(rows)
          .where(
              (row) => (row['endpoint']?.toString().trim().isNotEmpty ?? false))
          .map((row) => row['usuario_id'].toString())
          .toSet();
    }
    for (final profile in roster) {
      profile['_push_active'] =
          subscriptions.contains(profile['id'].toString());
    }

    final activos = roster.where((profile) {
      final value = profile['ultimo_acceso']?.toString();
      final date = value == null ? null : DateTime.tryParse(value)?.toUtc();
      return date != null && date.isAfter(cutoff);
    }).length;
    final voices = <String, int>{};
    for (final profile in roster.where((p) => p['estado'] == 'activo')) {
      final voice = profile['voz']?.toString() ?? 'sin_asignar';
      voices[voice] = (voices[voice] ?? 0) + 1;
    }
    final views = List<Map<String, dynamic>>.from(supplemental[0] as List);
    final viewsBySong = <String, int>{};
    for (final view in views) {
      final id = view['canto_id']?.toString();
      if (id != null) viewsBySong[id] = (viewsBySong[id] ?? 0) + 1;
    }
    final names = {for (final song in songs) song.id: song.nombre};
    final top = viewsBySong.entries
        .where((entry) => names.containsKey(entry.key))
        .map((entry) => <String, dynamic>{
              'id': entry.key,
              'nombre': names[entry.key],
              'vistas': entry.value,
            })
        .toList()
      ..sort((a, b) => (b['vistas'] as int).compareTo(a['vistas'] as int));
    final audit = List<Map<String, dynamic>>.from(supplemental[2] as List)
        .where((row) =>
            (row['detalles'] as Map?)?['coro_id']?.toString() == sedeId)
        .take(12)
        .toList();

    return GestorMetrics(
      miembros: roster.length,
      activosSemana: activos,
      notificaciones: subscriptions.length,
      offline: roster.where((p) => p['offline_ready'] == true).length,
      repertorio: songs.length,
      conMidi:
          songs.where((song) => song.midiArchivo?.isNotEmpty == true).length,
      voces: voices,
      topCantos: top.take(10).toList(),
      errores: List<Map<String, dynamic>>.from(supplemental[1] as List),
      auditoria: audit,
    );
  }

  Future<void> enviarRecordatorio(String sedeId, String message) async {
    final clean = message.trim();
    if (clean.isEmpty || clean.length > 500) {
      throw const FormatException(
          'El recordatorio debe tener entre 1 y 500 caracteres.');
    }
    await client.from('avisos').insert({
      'coro_id': sedeId,
      'tipo': 'RECORDATORIO',
      'mensaje': clean,
      'metadata': {'subtipo': 'RECORDATORIO_GESTOR_NATIVO'},
    });
    await _audit('NOTIFICO', sedeId, {'mensaje': clean});
  }

  Future<String> upload({
    required String sedeId,
    required String type,
    required Uint8List bytes,
  }) async {
    if (type != 'pdf' && type != 'midi') {
      throw const FormatException('Solo se aceptan archivos PDF y MIDI.');
    }
    final max = type == 'pdf' ? 25 * 1024 * 1024 : 5 * 1024 * 1024;
    final valid =
        type == 'pdf' ? FileCrypto.isPdf(bytes) : FileCrypto.isMidi(bytes);
    if (!valid) {
      throw FormatException(
        type == 'pdf'
            ? 'El archivo no contiene una cabecera PDF válida.'
            : 'El archivo no contiene una cabecera MIDI válida.',
      );
    }
    if (bytes.isEmpty || bytes.length > max) {
      throw FormatException(
          'El archivo supera el límite de ${type == 'pdf' ? '25' : '5'} MB.');
    }

    final token = client.auth.currentSession?.accessToken;
    if (token == null) throw const AuthException('La sesión expiró.');
    final response = await _dio.put<Map<String, dynamic>>(
      '${SupabaseService.storageUrl}/v1/local/upload',
      queryParameters: {'type': type, 'sede': sedeId},
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': type == 'pdf' ? 'application/pdf' : 'audio/midi',
          'Content-Length': bytes.length,
        },
      ),
    );
    final key = response.data?['object_key']?.toString();
    if (key == null || key.isEmpty) {
      throw StateError('Cloudflare no devolvió la ruta del archivo.');
    }
    return key;
  }

  Future<Canto> guardarLocal({
    Canto? original,
    required String sedeId,
    required String nombre,
    required List<String> temas,
    String? archivo,
    String? midi,
    bool quitarMidi = false,
  }) async {
    final cleanName = nombre.trim();
    if (cleanName.isEmpty || cleanName.length > 150) {
      throw const FormatException(
          'El nombre debe tener entre 1 y 150 caracteres.');
    }
    final pdf = archivo ?? original?.archivo;
    if (pdf == null || pdf.isEmpty) {
      throw const FormatException('Selecciona un PDF válido.');
    }

    final isOwnedLocal = original != null &&
        original.origen == 'local' &&
        original.corosVinculados.contains(sedeId);
    final payload = <String, dynamic>{
      'nombre': cleanName,
      'archivo': pdf,
      'midi_archivo': quitarMidi ? null : (midi ?? original?.midiArchivo),
      'temas': temas,
      'coro_id': sedeId,
      'es_privado': true,
      'origen': 'local',
      'idioma': 'es',
      'cifrado_version': 1,
      'estado_revision_global': 'pendiente',
      'activo': true,
    };

    Map<String, dynamic> saved;
    if (isOwnedLocal) {
      saved = await client
          .from('cantos')
          .update(payload)
          .eq('id', original.id)
          .select()
          .single();
    } else {
      if (original != null) payload['derivado_de'] = original.id;
      saved = await client.from('cantos').insert(payload).select().single();
      await client.from('cantos_coros').insert({
        'canto_id': saved['id'],
        'coro_id': sedeId,
      });
      if (original != null) {
        await client
            .from('cantos_coros')
            .delete()
            .eq('canto_id', original.id)
            .eq('coro_id', sedeId);
      }
    }
    await _audit(original == null ? 'CREO' : 'EDITO', sedeId, {
      'canto_id': saved['id'],
      'canto_nombre': cleanName,
    });
    return Canto.fromJson({
      ...saved,
      'coros_vinculados': [sedeId]
    });
  }

  Future<void> agregarGlobal(Canto source, String sedeId) async {
    final current = await repertorio(sedeId);
    if (current
        .any((song) => song.id == source.id || song.derivadoDe == source.id)) {
      throw StateError('Esta partitura ya está en el repertorio de la sede.');
    }
    await guardarLocal(
      original: source,
      sedeId: sedeId,
      nombre: source.nombre,
      temas: source.temas,
    );
  }

  Future<void> quitarDeSede(Canto song, String sedeId) async {
    await client
        .from('cantos_coros')
        .delete()
        .eq('canto_id', song.id)
        .eq('coro_id', sedeId);
    await _audit('ELIMINO', sedeId, {
      'canto_id': song.id,
      'canto_nombre': song.nombre,
      'alcance': 'solo_sede',
    });
  }

  Future<void> actualizarMiembro(
    String userId, {
    String? estado,
    String? rol,
  }) async {
    await client.from('perfiles').update({
      if (estado != null) 'estado': estado,
      if (rol != null) 'rol': rol,
    }).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> eventos(String sedeId) async {
    final rows = await client
        .from('eventos')
        .select('id,nombre,fecha,es_estatal,eventos_cantos(canto_id,orden)')
        .or('coro_id.eq.$sedeId,coro_id.eq.estatal')
        .order('fecha', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> crearEvento(String sedeId, String nombre, DateTime fecha) async {
    await client.from('eventos').insert({
      'nombre': nombre.trim(),
      'coro_id': sedeId,
      'fecha': fecha.toIso8601String().split('T').first,
      'creado_por': client.auth.currentUser?.id,
      'es_estatal': sedeId == 'estatal',
    });
  }

  Future<void> eliminarEvento(String eventId) async {
    await client.from('eventos').delete().eq('id', eventId);
  }

  Future<void> _audit(
    String action,
    String sedeId,
    Map<String, dynamic> details,
  ) async {
    try {
      await client.from('auditoria').insert({
        'usuario_id': client.auth.currentUser?.id,
        'accion': action,
        'detalles': {...details, 'coro_id': sedeId},
      });
    } catch (_) {
      // La acción principal no debe fallar porque la auditoría esté temporalmente fuera.
    }
  }
}
