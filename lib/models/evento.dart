class Evento {
  final String id;
  final String nombre;
  final String coroId;
  final bool esEstatal;
  final List<String> sedesParticipantes;
  final List<String> miembrosParticipantes;

  Evento({
    required this.id,
    required this.nombre,
    required this.coroId,
    required this.esEstatal,
    this.sedesParticipantes = const [],
    this.miembrosParticipantes = const [],
  });

  factory Evento.fromJson(Map<String, dynamic> json) {
    return Evento(
      id: json['id'].toString(),
      nombre: json['nombre'] as String? ?? '',
      coroId: json['coro_id'] as String? ?? '',
      esEstatal: json['es_estatal'] == true,
      sedesParticipantes: (json['sedes_participantes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      miembrosParticipantes: (json['miembros_participantes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'coro_id': coroId,
      'es_estatal': esEstatal,
      'sedes_participantes': sedesParticipantes,
      'miembros_participantes': miembrosParticipantes,
    };
  }
}
