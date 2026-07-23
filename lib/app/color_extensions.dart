import 'package:flutter/material.dart';

extension ColorValuesCompat on Color {
  Color withValues({
    double? alpha,
    double? red,
    double? green,
    double? blue,
  }) {
    return withOpacity(alpha ?? opacity);
  }

  int toARGB32() => value;

  double get a => opacity;
  double get r => red / 255.0;
  double get g => green / 255.0;
  double get b => blue / 255.0;
}
