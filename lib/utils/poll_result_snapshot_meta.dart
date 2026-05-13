import 'large_int_codec.dart';
import 'logger.dart';

/// Snapshot sequence from `/poll/results` payload keys (canonical sync).
BigInt? pollResultSnapshotSequenceFromMap(Map<String, dynamic> rd) {
  for (final k in const ['sequence_id', 'snapshot_sequence', 'seq']) {
    if (!rd.containsKey(k)) continue;
    final v = tryParseBigIntId(rd[k]);
    if (v == null && rd[k] is num) {
      Logger.warning(
        'Poll result key "$k" has unsafe numeric precision; '
        'backend should send sequence as string',
        tag: 'PollResultSnapshotMeta',
      );
    }
    if (v != null) return v;
  }
  return null;
}

/// Observation time from `/poll/results` for canonical sync metadata.
DateTime? pollResultSnapshotObservedAtFromMap(Map<String, dynamic> rd) {
  for (final k in const ['balance_updated_at', 'awarded_at', 'updated_at']) {
    if (!rd.containsKey(k)) continue;
    final d = DateTime.tryParse(rd[k].toString().trim());
    if (d != null) return d;
  }
  return null;
}
