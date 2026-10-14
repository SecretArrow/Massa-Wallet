import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/features/node/node_log_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('classifyNodeLogLevel', () {
    test('massa-node level markers are classified', () {
      expect(
        classifyNodeLogLevel('12:00:00 2024-10-13T12:00:00Z INFO massa-grpc ok'),
        NodeLogLevel.info,
      );
      expect(
        classifyNodeLogLevel('12:00:01 2024-10-13T12:00:01Z WARN massa-db slow io'),
        NodeLogLevel.warn,
      );
      expect(
        classifyNodeLogLevel('12:00:02 2024-10-13T12:00:02Z ERROR massa-exec oops'),
        NodeLogLevel.error,
      );
    });

    test('case-insensitive + free-text runtime failures', () {
      expect(classifyNodeLogLevel('... Warning: config drift ...'), NodeLogLevel.warn);
      expect(classifyNodeLogLevel('panic: runtime error'), NodeLogLevel.error);
      expect(
        classifyNodeLogLevel('CANNOT LINK EXECUTABLE: library libc++_shared.so not found'),
        NodeLogLevel.error,
      );
      expect(classifyNodeLogLevel('12:00:00 node started (pid 4242)'), NodeLogLevel.info);
    });
  });

  group('EmbeddedNodeService log buffer', () {
    late EmbeddedNodeService node;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      node = EmbeddedNodeService(settings: settings);
    });

    test('appendLogLine prefixes a timestamp and stores oldest-first', () {
      node.appendLogLine('first');
      node.appendLogLine('second');
      final logs = node.logs;
      expect(logs.length, 2);
      expect(logs[0], endsWith(' first'));
      expect(logs[1], endsWith(' second'));
      // Timestamp prefix shape: HH:MM:SS.
      expect(RegExp(r'^\d{2}:\d{2}:\d{2} ').hasMatch(logs[0]), isTrue);
    });

    test('buffer is capped at 1000 lines, oldest trimmed', () {
      for (var i = 0; i < 1050; i++) {
        node.appendLogLine('line-$i');
      }
      final logs = node.logs;
      expect(logs.length, 1000);
      expect(logs.first, endsWith(' line-50'));
      expect(logs.last, endsWith(' line-1049'));
    });

    test('clearLogs empties the buffer and listeners are notified', () {
      var notified = 0;
      node.addListener(() => notified++);
      node.appendLogLine('a');
      node.appendLogLine('b');
      expect(node.logs, isNotEmpty);
      node.clearLogs();
      expect(node.logs, isEmpty);
      // append ×2 + clear = 3 notifications.
      expect(notified, 3);
    });
  });
}
