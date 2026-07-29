import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:repertorio_bc/app/app.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('repertorio_bc_test_');
    Hive.init(hiveDirectory.path);
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('Smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RepertorioApp(),
      ),
    );
  });
}
