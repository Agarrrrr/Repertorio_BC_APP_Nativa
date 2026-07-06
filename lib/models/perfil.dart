class Perfil {
  final String id;
  final String nombre;
  final String email;
  final String coroId;
  final String rol;
  final String? municipio;

  Perfil({
    required this.id,
    required this.nombre,
    required this.email,
    required this.coroId,
    required this.rol,
    this.municipio,
  });

  factory Perfil.fromJson(Map<String, dynamic> json) {
    return Perfil(
      id: json['id'] as String,
      nombre: json['nombre'] as String? ?? '',
      email: json['email'] as String? ?? '',
      coroId: json['coro_id']?.toString() ?? '',
      rol: json['rol'] as String? ?? 'miembro',
      municipio: json['municipio'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'email': email,
      'coro_id': coroId,
      'rol': rol,
      if (municipio != null) 'municipio': municipio,
    };
  }

  Perfil copyWith({
    String? id,
    String? nombre,
    String? email,
    String? coroId,
    String? rol,
    String? municipio,
  }) {
    return Perfil(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      coroId: coroId ?? this.coroId,
      rol: rol ?? this.rol,
      municipio: municipio ?? this.municipio,
    );
  }
}
