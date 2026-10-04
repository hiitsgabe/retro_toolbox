import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/python_worker.dart';

void main() {
  test('starts the embedded interpreter only once even though run() returns immediately', () async {
    var launches = 0;
    // Async serious_python returns as soon as the worker thread spawns.
    PythonWorker.launch = (_) async {
      launches++;
      return null;
    };

    await PythonWorker.ensureStarted();
    await Future<void>.delayed(Duration.zero);
    await PythonWorker.ensureStarted();

    expect(launches, 1);
  });
}
