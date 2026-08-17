import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/utils/single_flight.dart';

void main() {
  test('comparte una descarga concurrente de la misma partitura', () async {
    final gate = Completer<int>();
    final flights = SingleFlight<int>();
    var executions = 0;

    Future<int> operation() {
      executions++;
      return gate.future;
    }

    final first = flights.run('pdf:1', operation);
    final second = flights.run('pdf:1', operation);
    gate.complete(42);

    expect(await Future.wait([first, second]), [42, 42]);
    expect(executions, 1);
  });
}
