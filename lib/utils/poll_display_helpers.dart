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

List<PollOptionAmount> _rowsFromVoteCountsList(
  List<dynamic> options,
  List<dynamic> countsList,
  int unit,
) {
  final n = options.length;
  final out = <PollOptionAmount>[];
  for (var i = 0; i < n; i++) {
    final label = pollOptionDisplayLabel(options[i]);
    // Old Code: required countsList.length >= options.length, else returned null.
    // if (countsList.length < options.length) return null;
    final raw = i < countsList.length ? countsList[i] : null;
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

/// Same key order as vote-count consumers: first match wins after JSON decode.
dynamic _decodePollResultVoteTallyRaw(Map<String, dynamic>? pr) {
  if (pr == null) return null;
  return _decodeMaybeJson(pr['vote_counts']) ??
      _decodeMaybeJson(pr['votes']) ??
      _decodeMaybeJson(pr['vote_tally']) ??
      _decodeMaybeJson(pr['counts']) ??
      _decodeMaybeJson(pr['tally']) ??
      _decodeMaybeJson(pr['voteCountByOption']);
}

/// Per-option **vote counts** (not × unit), length always [options.length], missing indices → 0.
List<PollOptionAmount>? _voteOnlyRowsFromTallyDecoded(
  List<dynamic> options,
  dynamic decoded,
) {
  final n = options.length;
  if (n == 0) return const [];
  if (decoded is Map) {
    final m = Map<dynamic, dynamic>.from(decoded);
    final out = <PollOptionAmount>[];
    for (var i = 0; i < n; i++) {
      final label = pollOptionDisplayLabel(options[i]);
      dynamic raw = m[i] ?? m[i.toString()];
      if (raw == null) {
        for (final prefix in ['opt_', 'option_', 'o']) {
          raw = m['$prefix$i'] ?? m['$prefix${i.toString()}'];
          if (raw != null) break;
        }
      }
      final votes = _toNonNegativeInt(_unwrapAmountish(raw) ?? raw);
      out.add(PollOptionAmount(label: label, amount: votes));
    }
    return out;
  }
  if (decoded is List) {
    final out = <PollOptionAmount>[];
    for (var i = 0; i < n; i++) {
      final label = pollOptionDisplayLabel(options[i]);
      final raw = i < decoded.length ? decoded[i] : null;
      final votes = _toNonNegativeInt(_unwrapAmountish(raw) ?? raw);
      out.add(PollOptionAmount(label: label, amount: votes));
    }
    return out;
  }
  return null;
}

/// Raw vote tally fields present and decode to a Map/List → padded per-option vote rows.
List<PollOptionAmount>? _tryVoteOnlyRowsFromPollResult(
  List<dynamic> options,
  Map<String, dynamic> pr,
) {
  const tallyKeys = [
    'vote_counts',
    'votes',
    'vote_tally',
    'counts',
    'tally',
    'voteCountByOption',
  ];
  var anyKeyPresent = false;
  for (final k in tallyKeys) {
    if (pr.containsKey(k)) {
      anyKeyPresent = true;
      break;
    }
  }
  if (!anyKeyPresent) return null;

  final decoded = _decodePollResultVoteTallyRaw(pr);
  if (decoded == null) return null;
  return _voteOnlyRowsFromTallyDecoded(options, decoded);
}

/// Resolves per-option monetary / PNP totals for display.
///
/// Priority:
/// 1) `poll_result.option_totals` / `option_total_pnp` / `totals_by_option` (index → amount)
/// 2) `poll_result.option_amounts` as a [List] parallel to options
/// 3) `vote_counts` × [unitValue] when [unitValue] is positive
/// 4) `vote_counts` (and aliases) as **raw vote counts** per option, padded to [options.length]
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
    final voteCountsRaw = _decodePollResultVoteTallyRaw(pr);
    if (voteCountsRaw is Map) {
      final countsMap = Map<dynamic, dynamic>.from(voteCountsRaw);
      final rows = _rowsFromVoteCountsMap(options, countsMap, effectiveUnit);
      if (rows != null) return rows;
    }
    if (voteCountsRaw is List) {
      return _rowsFromVoteCountsList(
        options,
        voteCountsRaw,
        effectiveUnit,
      );
    }
  }

  if (pr != null) {
    final voteOnly = _tryVoteOnlyRowsFromPollResult(options, pr);
    if (voteOnly != null) return voteOnly;
  }

  return const [];
}

/// Single-line compact summary: each [PollOptionAmount.label] with amount, e.g.
/// `"Yes : 12, No : 0, Maybe : 4"`. All rows from [resolveOptionAmounts] are included (zeros kept).
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

  /*
  Old Code: dropped zero-amount options from the summary line.
  final nonZero = rows.where((r) => r.amount > 0).toList();
  if (nonZero.isNotEmpty) {
    return nonZero.map((r) => '${r.label} : ${r.amount}').join(', ');
  }
  return rows.map((r) => '${r.label} : ${r.amount}').join(', ');

  Ordinal labels ("Option 1 : …") via loop + _formatPollSummaryAmount was also retired:
  final parts = <String>[];
  for (var i = 0; i < rows.length; i++) {
    parts.add('Option ${i + 1} : ${_formatPollSummaryAmount(rows[i].amount)}');
  }
  return parts.join(', ');
  */

  return rows.map((r) => '${r.label} : ${r.amount}').join(', ');
}

/// PHP/json_encode often turns numeric keys into a JSON **array** `[6000,7000,...]`.
/// Flutter must accept both List and Map for [amount_by_option].
Map<String, dynamic>? normalizePollAmountByOption(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is List) {
    final out = <String, dynamic>{};
    for (var i = 0; i < raw.length; i++) {
      out[i.toString()] = raw[i];
    }
    // ignore: avoid_print
    print(
      '⚠️ 📊 poll_option_totals normalized amount_by_option from JSON List '
      '→ Map (server sent array form)',
    );
    return out.isEmpty ? null : out;
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      return normalizePollAmountByOption(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Ensures [poll_option_totals] is safe for timer strip + provider merge.
Map<String, dynamic>? normalizePollOptionTotalsPayload(
  Map<String, dynamic>? totals,
) {
  if (totals == null) return null;
  final copy = Map<String, dynamic>.from(totals);
  final amounts = normalizePollAmountByOption(copy['amount_by_option']);
  if (amounts == null) return null;
  copy['amount_by_option'] = amounts;
  final voteCounts = copy['vote_counts'];
  if (voteCounts is List) {
    final vc = <String, dynamic>{};
    for (var i = 0; i < voteCounts.length; i++) {
      vc[i.toString()] = voteCounts[i];
    }
    copy['vote_counts'] = vc;
  }
  return copy;
}

/// Resolves PNP per betting unit (matches WordPress `bet_step` / [QuizData.effectiveAmountStepPnp]).
int resolvePollBetStepPnp(EngagementItem item) {
  final q = item.quizData;
  if (q != null) return q.effectiveAmountStepPnp;
  final fromResult = _resolveEffectivePollUnit(item, item.pollResult, null);
  return fromResult ?? 1000;
}

/// PNP total → user-facing unit count (Your choice lane): 6000 PNP @ step 1000 → `6`.
int pollPnpAmountToDisplayUnits(int pnpAmount, EngagementItem item) {
  if (pnpAmount <= 0) return 0;
  final step = resolvePollBetStepPnp(item);
  if (step <= 0) return pnpAmount;
  return pnpAmount ~/ step;
}

/// Per-option `"label : amount"` segments for timer strip (Wrap layout).
/// Returns `null` when server tally is pending/unavailable.
List<String>? pollGlobalOptionTotalsParts(EngagementItem item) {
  final options = item.quizData?.options;
  if (options == null || options.isEmpty) return null;
  final optionCount = options.length;

  final totalsRoot = item.pollOptionTotals;
  if (totalsRoot == null) return null;

  final amountsMap = normalizePollAmountByOption(
    totalsRoot['amount_by_option'],
  );
  if (amountsMap == null) return null;

  final parts = <String>[];
  for (var i = 0; i < optionCount; i++) {
    dynamic raw = amountsMap[i] ?? amountsMap[i.toString()];
    if (raw == null) {
      for (final prefix in ['opt_', 'option_', 'o']) {
        raw = amountsMap['$prefix$i'] ?? amountsMap['$prefix${i.toString()}'];
        if (raw != null) break;
      }
    }
    final pnpAmount = _toNonNegativeInt(_unwrapAmountish(raw) ?? raw);
    final label = pollOptionDisplayLabel(options[i]);
    final displayUnits = pollPnpAmountToDisplayUnits(pnpAmount, item);
    parts.add('$label : $displayUnits');
  }

  return parts.isEmpty ? null : parts;
}

/// Global all-users per-option totals for timer strip (not "Your choice").
/// Converts server PNP [amount_by_option] to unit counts (6000 PNP → `6` when step is 1000).
/// (never cached locally — provider strips disk cache for this field).
/// Returns `'Option totals: pending'` when server tally is absent.
String formatPollGlobalOptionTotalsLine(EngagementItem item) {
  final parts = pollGlobalOptionTotalsParts(item);
  return parts == null ? 'Option totals: pending' : parts.join(', ');
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

  final vcDecoded = _decodePollResultVoteTallyRaw(pr);
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

const Set<String> kPollResultLikeVotingStatuses = <String>{
  'showing_result',
  'showing_results',
  'ended',
  'result',
  'results',
};

bool isPollResultLikeVotingStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  return kPollResultLikeVotingStatuses.contains(status.toLowerCase());
}

/// Voting window open (AUTO_RUN next round) — not result/ended.
bool isPollVotingOpenLikeStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  switch (status.toLowerCase()) {
    case 'open':
    case 'countdown':
    case 'active':
    case 'voting':
      return true;
    default:
      return false;
  }
}

/// True after [result_display_ends_at] (or legacy end + display duration) has passed.
bool pollResultDisplayWindowEnded(Map<String, dynamic>? schedule) {
  if (schedule == null) return false;
  final raw =
      schedule['result_display_ends_at'] ??
      schedule['result_display_end_at'] ??
      schedule['results_end_at'];
  final text = raw?.toString().trim();
  if (text != null && text.isNotEmpty) {
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return DateTime.now().toUtc().isAfter(parsed.toUtc());
    }
  }
  final endsAt = resolvePollEndsAtUtc(schedule);
  if (endsAt == null) return false;
  final displaySec =
      (schedule['result_display_duration_seconds'] as num?)?.toInt() ??
      (schedule['result_display_seconds'] as num?)?.toInt() ??
      15;
  final resultEnds = endsAt.add(Duration(seconds: displaySec.clamp(0, 3600)));
  return DateTime.now().toUtc().isAfter(resultEnds);
}

/// Server started a new voting window — do not keep stale [poll_result] / result UI.
bool pollFeedIndicatesNewVotingRound({
  required EngagementItem previous,
  required EngagementItem fresh,
}) {
  if (fresh.type != EngagementType.poll) return false;
  final freshSched = fresh.pollVotingSchedule;
  if (freshSched == null) return false;

  if (previous.hasInteracted && !fresh.hasInteracted) return true;

  final freshStatus = (freshSched['voting_status'] ?? '').toString();
  if (isPollVotingOpenLikeStatus(freshStatus)) {
    final seconds = resolvePollSecondsRemaining(
      schedule: freshSched,
      endsAtUtc: resolvePollEndsAtUtc(freshSched),
    );
    if (seconds > 15) return true;
  }

  final prevSched = previous.pollVotingSchedule;
  if (prevSched != null) {
    for (final key in const [
      'end_time',
      'ends_at',
      'poll_actual_start_at',
      'started_at',
      'poll_voting_end_time',
    ]) {
      final a = prevSched[key]?.toString().trim() ?? '';
      final b = freshSched[key]?.toString().trim() ?? '';
      if (a.isNotEmpty && b.isNotEmpty && a != b) return true;
    }
    final prevSec = resolvePollSecondsRemaining(
      schedule: prevSched,
      endsAtUtc: resolvePollEndsAtUtc(prevSched),
    );
    final freshSec = resolvePollSecondsRemaining(
      schedule: freshSched,
      endsAtUtc: resolvePollEndsAtUtc(freshSched),
    );
    if (freshSec > prevSec + 30) return true;
  }

  if (isPollResultLikeVotingStatus(
        previous.pollVotingSchedule?['voting_status']?.toString(),
      ) &&
      isPollVotingOpenLikeStatus(freshStatus)) {
    return pollResultDisplayWindowEnded(previous.pollVotingSchedule);
  }

  return false;
}

/// Carousel should show vote UI (not result card) when schedule says voting is open.
/// Spectators ([hasInteracted] false) still see the result card during `showing_result`.
bool engagementItemShouldShowPollVotingUi(EngagementItem item) {
  if (item.type != EngagementType.poll) return false;
  final schedule = item.pollVotingSchedule;
  final status = schedule?['voting_status']?.toString();

  if (!isPollResultLikeVotingStatus(status)) {
    return true;
  }

  if (isPollVotingOpenLikeStatus(status)) {
    final seconds = resolvePollSecondsRemaining(
      schedule: schedule,
      endsAtUtc: resolvePollEndsAtUtc(schedule),
    );
    if (seconds > 15) return true;
  }

  final seconds = resolvePollSecondsRemaining(
    schedule: schedule,
    endsAtUtc: resolvePollEndsAtUtc(schedule),
  );
  if (seconds > 0) return true;

  final mode = (schedule?['poll_mode'] ?? '').toString().toLowerCase();
  if (mode == 'auto_run' && pollResultDisplayWindowEnded(schedule)) {
    return true;
  }

  return false;
}

/// True when [poll_result] has enough data to render the in-feed winner card.
bool pollResultMapReadyForFeedCard(Map<String, dynamic> r) {
  if (_toNonNegativeInt(r['total_votes']) > 0) return true;
  if (r['winning_option'] != null) return true;
  final wi = r['winning_index'];
  if (wi is num && wi >= 0) return true;
  final options = r['options'];
  if (options is List && options.isNotEmpty) return true;
  final voteCounts = r['vote_counts'];
  if (voteCounts is Map && voteCounts.isNotEmpty) return true;
  if (voteCounts is List && voteCounts.isNotEmpty) return true;
  return false;
}

/// In-feed poll result card (spectators + voters) once server sends result phase + payload.
bool engagementItemShowsPollResultCard(EngagementItem item) {
  if (item.type != EngagementType.poll) return false;
  final status = item.pollVotingSchedule?['voting_status']?.toString();
  if (!isPollResultLikeVotingStatus(status)) return false;
  final r = item.pollResult;
  if (r == null) return false;
  return pollResultMapReadyForFeedCard(r);
}

/// Result phase declared but [poll_result] not on the feed yet — show calculating shell.
bool engagementItemAwaitingPollResultPayload(EngagementItem item) {
  if (item.type != EngagementType.poll) return false;
  final status = item.pollVotingSchedule?['voting_status']?.toString();
  if (!isPollResultLikeVotingStatus(status)) return false;
  return item.pollResult == null;
}
