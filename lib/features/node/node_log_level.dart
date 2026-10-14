/// Severity classifier for embedded-node log lines (pure, unit-tested).
///
/// Massa-node prints its own levels (INFO / WARN / ERROR …) inside the
/// line body, and dynamic-linker / runtime failures surface as free text
/// ("CANNOT LINK EXECUTABLE", "panic", …). The log viewer colors lines by
/// this classification so problems stand out without parsing details.
library;

/// Severity levels used by the node log viewer.
enum NodeLogLevel { info, warn, error }

/// Classifies a single (timestamp-prefixed) log line, case-insensitively.
NodeLogLevel classifyNodeLogLevel(String line) {
  final l = line.toLowerCase();
  if (l.contains('error') ||
      l.contains('fatal') ||
      l.contains('panic') ||
      l.contains('cannot link')) {
    return NodeLogLevel.error;
  }
  if (l.contains('warn')) {
    return NodeLogLevel.warn;
  }
  return NodeLogLevel.info;
}
