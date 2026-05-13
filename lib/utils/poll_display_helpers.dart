import 'dart:convert' show jsonDecode;

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

dynamic _decodeMaybeJson(dynamic raw) {
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return raw;
    try {
      return jsonDecode(t);
    } catch (_) {
      return raw;
    }
  }
  return raw;
}

/// Unwraps API values that may be a plain number or a small object
/// (`amount`, `total`, `votes`, …).
num? _unwrapAmountish(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.isFinite ? raw : null;
  if (raw is Map) {
    final m = Map<dynamic, dynamic>.from(raw);
    for (final k in [
      'amount',
      'total',
      'pnp',
      'total_pnp',
      'value',
      'vote_pnp',
      'votes',
      'vote_count',
      'count',
    ]) {
      if (m.containsKey(k)) {
        final inner = _unwrapAmountish(m[k]);
        if (inner != null) return inner;
      }
    }
    return null;
  }
  return _parseLooseNum(raw);
}

int? _resolveEffectivePollUnit(
  EngagementItem item,
  Map<String, dynamic>? pr,
  int? unitValue,
) {
  if (unitValue != null && unitValue > 0) return unitValue;
  if (pr != null) {
    for (final k in [
      'pnp_per_vote',
      'unit_value',
      'vote_unit_value',
      'poll_base_cost',
      'cost_per_vote',
      'per_vote_pnp',
      'per_vote_cost',
      'vote_cost',
    ]) {
      final n = _parseLooseNum(pr[k]);
      if (n != null && n > 0) return n.toInt();
    }
  }
  final bc = item.quizData?.pollBaseCost;
  if (bc != null && bc > 0) return bc;
  final step = item.quizData?.betAmountStep;
  if (step != null && step > 0) return step;
  return null;
}

List<PollOptionAmount>? _rowsFromVoteCountsMap(
  List<dynamic> options,
  Map<dynamic, dynamic> countsMap,
  int unit,
) {
  final out = <PollOptionAmount>[];
  for (var i = 0; i < options.length; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    dynamic raw = countsMap[i] ?? countsMap[i.toString()];
    if (raw == null) {
      for (final prefix in ['opt_', 'option_', 'o']) {
        raw = countsMap['$prefix$i'] ?? countsMap['$prefix${i.toString()}'];
        if (raw != null) break;
      }
    }
    final count = _toNonNegativeInt(_unwrapAmountish(raw) ?? raw);
    out.add(PollOptionAmount(label: label, amount: count * unit));
  }
  return out;
}

List<PollOptionAmount>? _rowsFromVoteCountsList(
  List<dynamic> options,
  List<dynamic> countsList,
  int unit,
) {
  if (countsList.length < options.length) return null;
  final out = <PollOptionAmount>[];
  for (var i = 0; i < options.length; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    final raw = countsList[i];
    final count = _toNonNegativeInt(_unwrapAmountish(raw) ?? raw);
    out.add(PollOptionAmount(label: label, amount: count * unit));
  }
  return out;
}

List<PollOptionAmount>? _rowsFromObjectList(
  List<dynamic> options,
  List<dynamic> rows,
) {
  final byIndex = <int, num>{};
  for (final entry in rows) {
    if (entry is! Map) continue;
    final m = Map<dynamic, dynamic>.from(entry);
    final idxRaw = m['index'] ?? m['option_index'] ?? m['i'] ?? m['id'];
    final idx = idxRaw is int ? idxRaw : int.tryParse(idxRaw?.toString() ?? '');
    if (idx == null || idx < 0 || idx >= options.length) continue;
    final rawAmt =
        m['amount'] ?? m['total'] ?? m['pnp'] ?? m['total_pnp'] ?? m['value'];
    final amt = _unwrapAmountish(rawAmt) ?? _parseLooseNum(rawAmt);
    if (amt != null) byIndex[idx] = amt;
  }
  if (byIndex.isEmpty) return null;
  final out = <PollOptionAmount>[];
  for (var i = 0; i < options.length; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    final n = byIndex[i];
    if (n == null) return null;
    out.add(PollOptionAmount(label: label, amount: n));
  }
  return out;
}

List<PollOptionAmount>? _optionAmountsFromIndexMap(
  List<dynamic> options,
  Map<dynamic, dynamic> m,
) {
  if (m.isEmpty) return null;
  final out = <PollOptionAmount>[];
  for (var i = 0; i < options.length; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    dynamic raw = m[i] ?? m[i.toString()];
    if (raw == null) {
      for (final prefix in ['opt_', 'option_', 'o']) {
        raw = m['$prefix$i'] ?? m['$prefix${i.toString()}'];
        if (raw != null) break;
      }
    }
    final n = _unwrapAmountish(raw) ?? _parseLooseNum(raw);
    if (n != null) {
      out.add(PollOptionAmount(label: label, amount: n));
    } else if (raw == null && m.isNotEmpty) {
      out.add(PollOptionAmount(label: label, amount: 0));
    } else {
      return null;
    }
  }
  return out.length == options.length ? out : null;
}

List<PollOptionAmount>? _optionAmountsFromParallelList(
  List<dynamic> options,
  List<dynamic> amountsList,
) {
  if (amountsList.length < options.length) return null;
  final out = <PollOptionAmount>[];
  for (var i = 0; i < options.length; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    final n =
        _unwrapAmountish(amountsList[i]) ?? _parseLooseNum(amountsList[i]);
    if (n != null) {
      out.add(PollOptionAmount(label: label, amount: n));
    } else {
      return null;
    }
  }
  return out;
}

/// Heuristic: backend-specific keys that still hold an index→amount (or amount-ish) map.
List<PollOptionAmount>? _optionAmountsFromDynamicPollKeys(
  List<dynamic> options,
  Map<String, dynamic> pr,
) {
  for (final entry in pr.entries) {
    final key = entry.key;
    final value = entry.value;
    final lk = key.toLowerCase();
    if (lk == 'vote_percentages' ||
        lk == 'winning_index' ||
        lk == 'winner' ||
        lk == 'message' ||
        lk == 'meta' ||
        lk == 'raw' ||
        lk == 'debug' ||
        lk == 'vote_counts' ||
        lk == 'votes' ||
        lk == 'vote_tally' ||
        lk == 'counts' ||
        lk == 'tally' ||
        lk == 'votecountbyoption') {
      continue;
    }
    if (!(lk.contains('option') ||
        lk.contains('total') ||
        lk.contains('pnp') ||
        lk.contains('stake') ||
        lk.contains('amount') ||
        lk.contains('tally'))) {
      continue;
    }
    final decoded = value is String ? _decodeMaybeJson(value) : value;
    if (decoded is Map) {
      final parsed = _optionAmountsFromIndexMap(
        options,
        Map<dynamic, dynamic>.from(decoded),
      );
      if (parsed != null) return parsed;
    }
  }
  return null;
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
  final effectiveUnit = _resolveEffectivePollUnit(item, pr, unitValue);

  if (pr != null) {
    dynamic optionTotals =
        pr['option_totals'] ??
        pr['option_total_pnp'] ??
        pr['totals_by_option'] ??
        pr['per_option_totals'] ??
        pr['option_totals_pnp'] ??
        pr['pnp_totals'] ??
        pr['pnp_by_option'] ??
        pr['amounts_by_option'] ??
        pr['weighted_option_totals'] ??
        pr['options_totals'] ??
        pr['optionTotals'] ??
        pr['option_pnps'] ??
        pr['stakes_by_option'] ??
        pr['stake_by_option'] ??
        pr['totals'];

    if (optionTotals is String && optionTotals.trim().isNotEmpty) {
      optionTotals = _decodeMaybeJson(optionTotals);
    }

    if (pr['totals'] is Map && optionTotals == null) {
      final t = Map<String, dynamic>.from(pr['totals'] as Map);
      optionTotals =
          t['option_totals'] ??
          t['option_total_pnp'] ??
          t['by_option'] ??
          t['per_option'] ??
          t['pnp_by_option'];
    }

    if (optionTotals is Map) {
      var m = Map<dynamic, dynamic>.from(optionTotals);
      var parsed = _optionAmountsFromIndexMap(options, m);
      if (parsed != null) return parsed;
      for (final innerKey in [
        'option_totals',
        'option_total_pnp',
        'by_option',
        'per_option',
        'pnp_by_option',
      ]) {
        final inner = m[innerKey];
        if (inner is Map) {
          parsed = _optionAmountsFromIndexMap(
            options,
            Map<dynamic, dynamic>.from(inner),
          );
          if (parsed != null) return parsed;
        }
      }
    }

    for (final listKey in [
      'option_amounts',
      'option_pnp_amounts',
      'pnp_amounts_by_option',
      'option_totals_list',
      'totals_list',
    ]) {
      final amountsList = pr[listKey];
      if (amountsList is List) {
        final parsed = _optionAmountsFromParallelList(options, amountsList);
        if (parsed != null) return parsed;
      }
    }

    for (final listKey in [
      'option_breakdown',
      'options_pnp',
      'per_option_breakdown',
      'option_results',
      'options_breakdown',
      'per_option_results',
    ]) {
      final rows = pr[listKey];
      if (rows is List) {
        final parsed = _rowsFromObjectList(options, rows);
        if (parsed != null) return parsed;
      }
    }

    final dynamicHeuristic = _optionAmountsFromDynamicPollKeys(options, pr);
    if (dynamicHeuristic != null) return dynamicHeuristic;
  }

  if (effectiveUnit != null && effectiveUnit > 0 && pr != null) {
    final voteCountsRaw =
        _decodeMaybeJson(pr['vote_counts']) ??
        _decodeMaybeJson(pr['votes']) ??
        _decodeMaybeJson(pr['vote_tally']) ??
        _decodeMaybeJson(pr['counts']) ??
        _decodeMaybeJson(pr['tally']) ??
        _decodeMaybeJson(pr['voteCountByOption']);
    if (voteCountsRaw is Map) {
      final countsMap = Map<dynamic, dynamic>.from(voteCountsRaw);
      final rows = _rowsFromVoteCountsMap(options, countsMap, effectiveUnit);
      if (rows != null) return rows;
    }
    if (voteCountsRaw is List) {
      final rows = _rowsFromVoteCountsList(
        options,
        voteCountsRaw,
        effectiveUnit,
      );
      if (rows != null) return rows;
    }
  }

  return const [];
}

/// Single-line compact summary: `"Option A : 50000, Option B : 12000"`.
/// When every resolved amount is `0`, joins zero rows (avoids hiding labels).
/// When [resolveOptionAmounts] is empty, uses participation or `'Option totals: pending'`.
String formatPollOptionAmountsSummaryLine(
  EngagementItem item, {
  int? unitValue,
}) {
  final rows = resolveOptionAmounts(item, unitValue: unitValue);
  /*
  Old Code: bare placeholder when nothing parsed.
  if (rows.isEmpty) return '--';
  */
  if (rows.isEmpty) {
    final participation = resolvePollParticipationCount(item);
    if (participation != null && participation > 0) {
      return 'Total votes: $participation';
    }
    return 'Option totals: pending';
  }

  final nonZero = rows.where((r) => r.amount > 0).toList();
  if (nonZero.isNotEmpty) {
    return nonZero.map((r) => '${r.label} : ${r.amount}').join(', ');
  }

  return rows.map((r) => '${r.label} : ${r.amount}').join(', ');
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

  final vcDecoded = _decodeMaybeJson(pr['vote_counts']);
  if (vcDecoded is Map) {
    var sum = 0;
    vcDecoded.forEach((_, value) {
      sum += _toNonNegativeInt(_unwrapAmountish(value) ?? value);
    });
    if (sum > 0) return sum;
  }
  if (vcDecoded is List) {
    var sum = 0;
    for (final e in vcDecoded) {
      sum += _toNonNegativeInt(_unwrapAmountish(e) ?? e);
    }
    if (sum > 0) return sum;
  }

  return null;
}
