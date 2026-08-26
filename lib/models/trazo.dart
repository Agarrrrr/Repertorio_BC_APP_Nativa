import 'dart:ui';

enum ToolType { pencil, eraser, text }

class PointNormalized {
  final double x; // 0.0 to 1.0 (relative to page width)
  final double y; // 0.0 to 1.0 (relative to page height)

  PointNormalized(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory PointNormalized.fromJson(Map<String, dynamic> json) =>
      PointNormalized(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      );
}

class Trazo {
  static int _idSequence = 0;

  ToolType tool;
  Color color;
  double size;
  final String syncId;
  final int modifiedAtMs;

  // Para lapiz y borrador
  List<PointNormalized> points;

  // Para texto flotante
  String? texto;
  PointNormalized? pos;
  bool oculto; // Usado temporalmente mientras se edita

  Trazo({
    required this.tool,
    required this.color,
    required this.size,
    String? syncId,
    int? modifiedAtMs,
    this.points = const [],
    this.texto,
    this.pos,
    this.oculto = false,
  })  : syncId = syncId ?? _newSyncId(),
        modifiedAtMs =
            modifiedAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;

  static String _newSyncId() {
    _idSequence++;
    return '${DateTime.now().toUtc().microsecondsSinceEpoch}-$_idSequence';
  }

  static String _legacySyncId(Map<String, dynamic> json) {
    final source = [
      json['herramienta'],
      json['color'],
      json['size'],
      json['texto'],
      json['pos'],
      json['puntos'],
    ].join('|');
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'legacy-${hash.toRadixString(16)}';
  }

  Trazo copyWith({
    ToolType? tool,
    Color? color,
    double? size,
    List<PointNormalized>? points,
    String? texto,
    PointNormalized? pos,
    bool? oculto,
    int? modifiedAtMs,
  }) =>
      Trazo(
        tool: tool ?? this.tool,
        color: color ?? this.color,
        size: size ?? this.size,
        points: points ??
            this.points.map((p) => PointNormalized(p.x, p.y)).toList(),
        texto: texto ?? this.texto,
        pos: pos ??
            (this.pos == null
                ? null
                : PointNormalized(this.pos!.x, this.pos!.y)),
        oculto: oculto ?? this.oculto,
        syncId: syncId,
        modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'herramienta': tool.name,
        'color':
            '#${(color.a * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.r * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.g * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.b * 255).toInt().toRadixString(16).padLeft(2, '0')}',
        'size': size,
        'puntos': points.map((p) => p.toJson()).toList(),
        'texto': texto,
        'pos': pos?.toJson(),
        'oculto': oculto,
        '_id': syncId,
        '_modifiedAt': modifiedAtMs,
      };

  factory Trazo.fromJson(Map<String, dynamic> json) {
    Color parseColor(String hex) {
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }

    return Trazo(
      tool: ToolType.values.firstWhere((e) => e.name == json['herramienta'],
          orElse: () => ToolType.pencil),
      color: parseColor(json['color'] ?? '#000000'),
      size: (json['size'] as num?)?.toDouble() ?? 3.0,
      points: (json['puntos'] as List?)
              ?.map((e) => PointNormalized.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      texto: json['texto'],
      pos: json['pos'] != null ? PointNormalized.fromJson(json['pos']) : null,
      oculto: json['oculto'] ?? false,
      syncId: json['_id']?.toString() ?? _legacySyncId(json),
      modifiedAtMs: (json['_modifiedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
