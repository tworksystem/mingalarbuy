/// JS Number exact integer upper bound: 2^53 - 1.
final BigInt kMaxSafeJsInteger = BigInt.from(9007199254740991);

/// Parses sequence/transaction ids without silent precision loss.
///
/// - `String` payloads are parsed as full-precision [BigInt].
/// - `int` payloads are promoted directly.
/// - `double` payloads are accepted only when they are integral and safe.
/// - On web, unsafe numeric payloads are rejected (must be sent as string).
BigInt? tryParseBigIntId(Object? raw) {
  if (raw == null) return null;
  if (raw is BigInt) return raw;
  if (raw is int) return BigInt.from(raw);
  if (raw is String) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    return BigInt.tryParse(s);
  }
  if (raw is num) {
    final double d = raw.toDouble();
    if (!d.isFinite || d.truncateToDouble() != d) {
      return null;
    }
    final BigInt parsed = BigInt.from(raw.toInt());
    if (parsed.abs() > kMaxSafeJsInteger) {
      // Numeric JSON transport above 2^53-1 may be lossy in JS runtimes.
      // Require string ids for cross-platform safety.
      return null;
    }
    return parsed;
  }
  return BigInt.tryParse(raw.toString().trim());
}
