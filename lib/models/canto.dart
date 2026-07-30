class Canto {
  final String id;
  final String nombre;
  final String archivo;
  final List<String> temas;
  final String? midiArchivo;
  final List<String>
      corosVinculados; // Array de coro_ids extraídos de cantos_coros
  final List<String>
      eventosVinculados; // Array de evento_ids extraídos de eventos_cantos
  final String? updatedAt;
  final String origen;
  final String idioma;
  final int version;
  final int cifradoVersion;
  final String? derivadoDe;

  Canto({
    required this.id,
    required this.nombre,
    required this.archivo,
    required this.temas,
    this.midiArchivo,
    required this.corosVinculados,
    this.eventosVinculados = const [],
    this.updatedAt,
    this.origen = 'local',
    this.idioma = 'es',
    this.version = 1,
    this.cifradoVersion = 1,
    this.derivadoDe,
  });

  factory Canto.fromJson(Map<String, dynamic> json) {
    // Manejar la relación cantos_coros que viene de Supabase
    List<String> coros = [];
    if (json['cantos_coros'] != null && json['cantos_coros'] is List) {
      for (var rel in json['cantos_coros']) {
        if (rel['coro_id'] != null) {
          coros.add(rel['coro_id'].toString());
        }
      }
    }
    if (json['coros_vinculados'] is List) {
      coros = (json['coros_vinculados'] as List)
          .map((value) => value.toString())
          .toList();
    }

    // Manejar la relación eventos_cantos
    List<String> eventos = [];
    if (json['eventos_cantos'] != null && json['eventos_cantos'] is List) {
      for (var rel in json['eventos_cantos']) {
        if (rel['evento_id'] != null) {
          eventos.add(rel['evento_id'].toString());
        }
      }
    }
    if (json['eventos_vinculados'] is List) {
      eventos = (json['eventos_vinculados'] as List)
          .map((value) => value.toString())
          .toList();
    }

    return Canto(
      id: json['id'].toString(),
      nombre: json['nombre'] as String? ?? '',
      archivo: json['archivo'] as String? ?? '',
      temas: (json['temas'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      midiArchivo: json['midi_archivo'] as String?,
      corosVinculados: coros,
      eventosVinculados: eventos,
      updatedAt:
          json['updated_at']?.toString() ?? json['updatedAt']?.toString(),
      origen: json['origen'] as String? ?? 'local',
      idioma: json['idioma'] as String? ?? 'es',
      version: (json['version'] as num?)?.toInt() ?? 1,
      cifradoVersion: (json['cifrado_version'] as num?)?.toInt() ?? 1,
      derivadoDe: json['derivado_de']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'archivo': archivo,
      'temas': temas,
      if (midiArchivo != null) 'midi_archivo': midiArchivo,
      'origen': origen,
      'idioma': idioma,
      'version': version,
      'cifrado_version': cifradoVersion,
      if (derivadoDe != null) 'derivado_de': derivadoDe,
      // cantos_coros no se serializa de vuelta directamente así,
      // suele manejarse en endpoints separados.
    };
  }
}
