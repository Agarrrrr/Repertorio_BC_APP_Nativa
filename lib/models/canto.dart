class Canto {
  final String id;
  final String nombre;
  final String archivo;
  final List<String> temas;
  final String? midiArchivo;
  final List<String> corosVinculados; // Array de coro_ids extraídos de cantos_coros
  final List<String> eventosVinculados; // Array de evento_ids extraídos de eventos_cantos
  final String? updatedAt;

  Canto({
    required this.id,
    required this.nombre,
    required this.archivo,
    required this.temas,
    this.midiArchivo,
    required this.corosVinculados,
    this.eventosVinculados = const [],
    this.updatedAt,
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
    
    // Manejar la relación eventos_cantos
    List<String> eventos = [];
    if (json['eventos_cantos'] != null && json['eventos_cantos'] is List) {
      for (var rel in json['eventos_cantos']) {
        if (rel['evento_id'] != null) {
          eventos.add(rel['evento_id'].toString());
        }
      }
    }

    return Canto(
      id: json['id'].toString(),
      nombre: json['nombre'] as String? ?? '',
      archivo: json['archivo'] as String? ?? '',
      temas: (json['temas'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      midiArchivo: json['midi_archivo'] as String?,
      corosVinculados: coros,
      eventosVinculados: eventos,
      updatedAt: json['updated_at']?.toString() ?? json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'archivo': archivo,
      'temas': temas,
      if (midiArchivo != null) 'midi_archivo': midiArchivo,
      // cantos_coros no se serializa de vuelta directamente así, 
      // suele manejarse en endpoints separados.
    };
  }
}
