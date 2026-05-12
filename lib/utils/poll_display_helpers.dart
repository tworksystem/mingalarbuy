import '../services/engagement_service.dart';

/// Per-option row for compact poll summary (Option label → total PNP / amount).
class PollOptionAmount {
  const PollOptionAmount({required this.label, required this.amount});

  final String label;
  final num amount;
}

/// Parses poll option to display label (aligned with engagement_carousel `_parsePollOption`).
String pollOptionDisplayLabel(dynamic opt) {
  if (opt == null) return 'Option';
  if (opt is Map) {
    final m = Map<String, dynamic>.from(opt);
    final textStr = (m['text'] ?? '').toString().trim();
    return textStr.isNotEmpty ? textStr : 'Option';
  }
  final s = opt.toString().trim();
  return s.isNotEmpty ? s : 'Option';
}

int _toNonNegativeInt(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw >= 0 ? raw : 0;
  if (raw is num) {
    final v = raw.toInt();
    return v >= 0 ? v : 0;
  }
  final parsed = int.tryParse(raw.toString().trim().replaceAll(',', ''));
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}

num? _parseLooseNum(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.isFinite ? raw : null;
  final normalized = raw.toString().trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  final parsed = num.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

/// Resolves per-option monetary / PNP totals for display.
///
/// Priority:
/// 1) `poll_result.option_totals` / `option_total_pnp` / `totals_by_option` (index → amount)
/// 2) `poll_result.option_amounts` as a [List] parallel to options
/// 3) `vote_counts` × [unitValue] when [unitValue] is positive
List<PollOptionAmount> resolveOptionAmounts(
  EngagementItem item, {
  int? unitValue,
}) {
  final options = item.quizData?.options;
  if (options == null || options.isEmpty) return const [];

  final pr = item.pollResult;
  if (pr != null) {
    dynamic optionTotals =
        pr['option_totals'] ??
        pr['option_total_pnp'] ??
        pr['totals_by_option'] ??
        pr['per_option_totals'];
    if (optionTotals is Map) {
      final m = Map<dynamic, dynamic>.from(optionTotals);
      final out = <PollOptionAmount>[];
      for (var i = 0; i < options.length; i++) {
        final label = pollOptionDisplayLabel(options[i]);
        final raw = m[i] ?? m[i.toString()];
        final n = _parseLooseNum(raw);
        if (n != null) {
          out.add(PollOptionAmount(label: label, amount: n));
        }
      }
      if (out.length == options.length) return out;
    }

    final amountsList = pr['option_amounts'] ?? pr['option_pnp_amounts'];
    if (amountsList is List && amountsList.length >= options.length) {
      final out = <PollOptionAmount>[];
      for (var i = 0; i < options.length; i++) {
        final label = pollOptionDisplayLabel(options[i]);
        final n = _parseLooseNum(amountsList[i]);
        if (n != null) {
          out.add(PollOptionAmount(label: label, amount: n));
        }
      }
      if (out.length == options.length) return out;
    }
  }

  if (unitValue != null && unitValue > 0 && pr != null) {
    final voteCountsRaw = pr['vote_counts'];
    if (voteCountsRaw is Map) {
      final countsMap = Map<dynamic, dynamic>.from(voteCountsRaw);
      final out = <PollOptionAmount>[];
      for (var i = 0; i < options.length; i++) {
        final label = pollOptionDisplayLabel(options[i]);
        dynamic raw = countsMap[i];
        raw ??= countsMap[i.toString()];
        final count = _toNonNegativeInt(raw);
        out.add(PollOptionAmount(label: label, amount: count * unitValue));
      }
      return out;
    }
  }

  return const [];
}

/// Single-line compact summary: `"Option A : 50000, Option B : 12000"`.
/// When every resolved amount is `0`, returns `'--'` (avoids `Label : 0` noise).
String formatPollOptionAmountsSummaryLine(
  EngagementItem item, {
  int? unitValue,
}) {
  final rows = resolveOptionAmounts(item, unitValue: unitValue);
  if (rows.isEmpty) return '--';

  final nonZero = rows.where((r) => r.amount > 0).toList();
  if (nonZero.isEmpty) {
    return '--';
  }
  return nonZero.map((r) => '${r.label} : ${r.amount}').join(', ');
}

DateTime? resolvePollEndsAtUtc(Map<String, dynamic>? schedule) {
  if (schedule == null) return null;
  final raw =
      schedule['ends_at'] ??
      schedule['poll_actual_end_at'] ??
      schedule['end_time'] ??
      schedule['voting_closes_at'] ??
      schedule['closes_at'];
  final text = raw?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.toUtc();
}

/// Seconds until poll closes — prefers API `seconds_until_close`, then alternate keys,
/// then wall-clock from [endsAtUtc].
int resolvePollSecondsRemaining({
  required Map<String, dynamic>? schedule,
  required DateTime? endsAtUtc,
}) {
  final rawSeconds = schedule?['seconds_until_close'];
  if (rawSeconds is int) {
    return rawSeconds < 0 ? 0 : rawSeconds;
  }
  if (rawSeconds is num) {
    final v = rawSeconds.toInt();
    return v < 0 ? 0 : v;
  }

  // လိုအပ်ပါက အဟောင်းပြန်ကြည့်ရန် — schedule-only fallbacks were not used before.
  final alt =
      schedule?['remaining_seconds'] ??
      schedule?['time_left_seconds'] ??
      schedule?['seconds_remaining'] ??
      schedule?['countdown_seconds'];
  if (alt is int && alt >= 0) return alt;
  if (alt is num) {
    final v = alt.toInt();
    if (v >= 0) return v;
  }

  if (endsAtUtc != null) {
    final diff = endsAtUtc.difference(DateTime.now().toUtc()).inSeconds;
    return diff < 0 ? 0 : diff;
  }
  return 0;
}

/// Participation count for poll badge: [EngagementItem.interactionCount], then
/// `poll_result.total_votes`, then sum of `vote_counts` values.
int? resolvePollParticipationCount(EngagementItem item) {
  if (item.interactionCount > 0) return item.interactionCount;

  final pr = item.pollResult;
  if (pr == null) return null;

  final tv =
      pr['total_votes'] ?? pr['participant_count'] ?? pr['total_participants'];
  final parsedTv = _toNonNegativeInt(tv);
  if (parsedTv > 0) return parsedTv;

  final vc = pr['vote_counts'];
  if (vc is Map) {
    var sum = 0;
    vc.forEach((_, value) {
      sum += _toNonNegativeInt(value);
    });
    if (sum > 0) return sum;
  }

  return null;
}
