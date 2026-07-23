import 'dart:ui';
import 'package:repertorio_bc/app/color_extensions.dart';

enum ToolType { pencil, eraser, text }

class PointNormalized {
  final double x; // 0.0 to 1.0 (relative to page width)
  final double y; // 0.0 to 1.0 (relative to page height)

  PointNormalized(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory PointNormalized.fromJson(Map<String, dynamic> json) => PointNormalized(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
  );
}

class Trazo {
  ToolType tool;
  Color color;
  double size;
  
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
    this.points = const [],
    this.texto,
    this.pos,
    this.oculto = false,
  });

  Map<String, dynamic> toJson() => {
    'herramienta': tool.name,
    'color': '#${(color.a * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.r * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.g * 255).toInt().toRadixString(16).padLeft(2, '0')}${(color.b * 255).toInt().toRadixString(16).padLeft(2, '0')}',
    'size': size,
    'puntos': points.map((p) => p.toJson()).toList(),
    'texto': texto,
    'pos': pos?.toJson(),
    'oculto': oculto,
  };

  factory Trazo.fromJson(Map<String, dynamic> json) {
    Color parseColor(String hex) {
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }

    return Trazo(
      tool: ToolType.values.firstWhere(
        (e) => e.name == json['herramienta'], 
        orElse: () => ToolType.pencil
      ),
      color: parseColor(json['color'] ?? '#000000'),
      size: (json['size'] as num?)?.toDouble() ?? 3.0,
      points: (json['puntos'] as List?)
          ?.map((e) => PointNormalized.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      texto: json['texto'],
      pos: json['pos'] != null ? PointNormalized.fromJson(json['pos']) : null,
      oculto: json['oculto'] ?? false,
    );
  }
}
