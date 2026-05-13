import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../api_service.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart' as app_logger;
import '../utils/network_utils.dart';

Map<String, String> _getWooCommerceAuthQueryParams() {
  return <String, String>{
    'consumer_key': AppConfig.consumerKey,
    'consumer_secret': AppConfig.consumerSecret,
  };
}

/// Engagement Item Type
enum EngagementType {
  banner,
  quiz,
  poll,
  announcement,
  number;

  static EngagementType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'banner':
        return EngagementType.banner;
      case 'quiz':
        return EngagementType.quiz;
      case 'poll':
        return EngagementType.poll;
      case 'announcement':
        return EngagementType.announcement;
      case 'number':
        return EngagementType.number;
      default:
        return EngagementType.banner;
    }
  }
}

/// Quiz/Poll Data Model
class QuizData {
  final String question;
  final List<String> options;
  final int correctIndex;
  final bool isActive;

  /// Poll base cost per option (for polls that deduct points)
  final int pollBaseCost;

  /// Whether user is allowed to choose custom betting Amount (multiple of base cost)
  final bool allowUserAmount;

  /// PNP per one "unit" of the Amount selector in User Amount mode (e.g. 1000 → 1000, 2000, 3000…).
  /// When null, backend/client fall back to [pollBaseCost] then 1000.
  final int? betAmountStep;

  const QuizData({
    required this.question,
    required this.options,
    required this.correctIndex,
    this.isActive = true,
    this.pollBaseCost = 0,
    this.allowUserAmount = true,
    this.betAmountStep,
  });

  /// Resolves step size for User Amount mode (matches WordPress `bet_amount_step` fallbacks).
  int get effectiveAmountStepPnp {
    final s = betAmountStep;
    if (s != null && s > 0) return s;
    if (pollBaseCost > 0) {
      // Back-compat: some legacy polls stored `poll_base_cost` as a small "unit" number
      // when `bet_amount_step` was missing (e.g. 1..5 => 1000..5000 PNP step).
      if (pollBaseCost < 1000) return pollBaseCost * 1000;
      return pollBaseCost;
    }
    return 1000;
  }

  /// PNP actually charged per one betting unit (vote stake), for UI receipts and cost checks.
  /// Does **not** apply win [reward_multiplier] or engagement reward — those are separate.
  /// When [pollBaseCost] equals [engagementRewardPoints], treats that as misconfiguration
  /// (reward stored as base) and falls back to 1000 PNP per unit.
  int spentPerUnitPnpForPoll({int? engagementRewardPoints}) {
    if (allowUserAmount) {
      final s = betAmountStep;
      if (s != null && s > 0) return s;
    }
    if (pollBaseCost > 0 && pollBaseCost < 1000) {
      return pollBaseCost * 1000;
    }
    if (pollBaseCost > 0) {
      final rp = engagementRewardPoints;
      if (rp != null && rp > 0 && pollBaseCost == rp) {
        return 1000;
      }
      return pollBaseCost;
    }
    return 1000;
  }

  factory QuizData.fromJson(Map<String, dynamic> json) {
    int _parseNonNegativeInt(dynamic raw) {
      if (raw == null) return 0;
      if (raw is int) return raw >= 0 ? raw : 0;
      if (raw is num) {
        final n = raw.toInt();
        return n >= 0 ? n : 0;
      }
      final cleaned = raw.toString().trim().replaceAll(',', '');
      final parsed = int.tryParse(cleaned);
      return (parsed != null && parsed >= 0) ? parsed : 0;
    }

    // Determine active/disabled state from multiple possible backend flags
    bool isActive = true;
    if (json.containsKey('is_active')) {
      final value = json['is_active'];
      isActive =
          value == true || value == 1 || value == '1' || value == 'active';
    } else if (json.containsKey('enabled')) {
      final value = json['enabled'];
      isActive = value == true || value == 1 || value == '1';
    } else if (json.containsKey('status')) {
      final status = json['status']?.toString().toLowerCase();
      if (status != null) {
        isActive = status == 'active' || status == 'open';
      }
    }

    // Parse options: can be List<String> or List<Map> with 'text' key
    List<String> options = [];
    final rawOptions = json['options'];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is String) {
          options.add(o);
        } else if (o is Map) {
          final text = o['text'] ?? o[0];
          options.add(text?.toString() ?? '');
        }
      }
    }

    // Note: correct_index is removed by backend for security, so we default to 0
    // This is safe because the backend validates answers server-side
    final pollBaseCost = _parseNonNegativeInt(
      json['poll_base_cost'] ??
          json['pollBaseCost'] ??
          json['unit_value'] ??
          json['pnp_per_vote'] ??
          json['cost'] ??
          json['bet_amount'],
    );

    // Allow user amount selector by default unless explicitly disabled
    bool allowUserAmount = true;
    if (json.containsKey('allow_user_amount')) {
      final v = json['allow_user_amount'];
      allowUserAmount =
          v == true || v == 1 || v == '1' || v == 'true' || v == 'yes';
    }

    final rawStep = json['bet_amount_step'] ?? json['betAmountStep'];
    int? betAmountStep;
    if (rawStep is num) {
      betAmountStep = rawStep.toInt();
    } else if (rawStep != null) {
      betAmountStep = int.tryParse(rawStep.toString());
    }

    return QuizData(
      question: json['question'] ?? '',
      options: options,
      correctIndex:
          json['correct_index'] ?? 0, // Will be 0 since backend removes it
      isActive: isActive,
      pollBaseCost: pollBaseCost,
      allowUserAmount: allowUserAmount,
      betAmountStep: betAmountStep,
    );
  }
}

/// Engagement Item Model
class EngagementItem {
  final int id;
  final EngagementType type;
  final String title;
  final String? mediaUrl;
  final String content;
  final int rewardPoints;
  final QuizData? quizData;
  final bool hasInteracted;
  final String? userAnswer;

  /// User Amount mode: the multiplier (1, 2, 3...) user selected when voting. null = Base Cost mode or not voted.
  final int? userBetAmount;

  /// Optional per-option bet multipliers from API (option index -> units k). When null, UI falls back to [userBetAmount].
  final Map<int, int>? userBetUnitsPerOption;
  final int?
  rotationDurationSeconds; // Rotation duration in seconds (null = use default)
  final int interactionCount; // Total interactions (for corner badge)
  final Map<String, dynamic>?
  pollVotingSchedule; // seconds_until_close, voting_status, result_display_ends_at, etc.
  final Map<String, dynamic>?
  pollResult; // vote_counts, vote_percentages, winning_index (when showing result)
  /// Raw backend payload for deep audit/debug (kept for diagnostics only).
  final Map<String, dynamic>? rawData;

  const EngagementItem({
    required this.id,
    required this.type,
    required this.title,
    this.mediaUrl,
    required this.content,
    required this.rewardPoints,
    this.quizData,
    required this.hasInteracted,
    this.userAnswer,
    this.userBetAmount,
    this.userBetUnitsPerOption,
    this.rotationDurationSeconds,
    this.interactionCount = 0,
    this.pollVotingSchedule,
    this.pollResult,
    this.rawData,
  });

  /// Create a copy with updated fields (for merging lightweight updates without full refresh)
  /// Set [clearPollResult] true when poll resets (e.g. Auto Run new period) to show Vote Now again.
  EngagementItem copyWith({
    int? interactionCount,
    Map<String, dynamic>? pollResult,
    Map<String, dynamic>? pollVotingSchedule,
    bool? hasInteracted,
    int? userBetAmount,
    Map<int, int>? userBetUnitsPerOption,
    bool clearPollResult = false,
  }) => EngagementItem(
    id: id,
    type: type,
    title: title,
    mediaUrl: mediaUrl,
    content: content,
    rewardPoints: rewardPoints,
    quizData: quizData,
    hasInteracted: hasInteracted ?? this.hasInteracted,
    userAnswer: userAnswer,
    userBetAmount: userBetAmount ?? this.userBetAmount,
    userBetUnitsPerOption: userBetUnitsPerOption ?? this.userBetUnitsPerOption,
    rotationDurationSeconds: rotationDurationSeconds,
    interactionCount: interactionCount ?? this.interactionCount,
    pollVotingSchedule: pollVotingSchedule ?? this.pollVotingSchedule,
    pollResult: clearPollResult ? null : (pollResult ?? this.pollResult),
    rawData: rawData,
  );

  Map<String, dynamic> toDebugMap() {
    return <String, dynamic>{
      if (rawData != null) ...rawData!,
      'id': id,
      'type': type.name,
      'title': title,
      'content': content,
      'reward_points': rewardPoints,
      if (quizData != null)
        'quiz_data': <String, dynamic>{
          'question': quizData!.question,
          'options': quizData!.options,
          'correct_index': quizData!.correctIndex,
          'is_active': quizData!.isActive,
          'poll_base_cost': quizData!.pollBaseCost,
          'allow_user_amount': quizData!.allowUserAmount,
          'bet_amount_step': quizData!.betAmountStep,
        },
      if (pollVotingSchedule != null)
        'poll_voting_schedule': pollVotingSchedule,
      if (pollResult != null) 'poll_result': pollResult,
    };
  }

  factory EngagementItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] ?? 'banner';
    final type = EngagementType.fromString(typeStr);

    QuizData? quizData;
    if (json['quiz_data'] != null) {
      try {
        Map<String, dynamic> parsedQuizData = {};
        final raw = json['quiz_data'];
        if (raw is String) {
          if (raw.trim().isEmpty) {
            app_logger.Logger.warning(
              'quiz_data is empty string, skipping',
              tag: 'EngagementService',
            );
          } else {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              parsedQuizData = Map<String, dynamic>.from(decoded);
            }
          }
        } else if (raw is Map) {
          parsedQuizData = Map<String, dynamic>.from(raw);
        }

        if (parsedQuizData.isNotEmpty) {
          quizData = QuizData.fromJson(parsedQuizData);
          app_logger.Logger.info(
            'Parsed quiz_data: question="${quizData.question}", options=${quizData.options.length}',
            tag: 'EngagementService',
          );
        } else if (raw != null) {
          app_logger.Logger.warning(
            'quiz_data is not a valid object: ${raw.runtimeType}',
            tag: 'EngagementService',
          );
        }
      } catch (e) {
        app_logger.Logger.error(
          'Failed to parse quiz_data: $e, data: ${json['quiz_data']}',
          tag: 'EngagementService',
          error: e,
        );
        // Don't fail the entire item if quiz_data parsing fails
      }
    }

    // Handle null/empty media_url
    final mediaUrl = json['media_url'];
    final String? finalMediaUrl =
        (mediaUrl != null && mediaUrl.toString().trim().isNotEmpty)
        ? mediaUrl.toString()
        : null;

    // Parse rotation_duration from backend (in seconds)
    // Backend now always provides rotation_duration (either from item or global setting)
    int? rotationDurationSeconds;
    if (json['rotation_duration'] != null) {
      if (json['rotation_duration'] is int) {
        rotationDurationSeconds = json['rotation_duration'] as int;
      } else if (json['rotation_duration'] is String) {
        rotationDurationSeconds = int.tryParse(json['rotation_duration']);
      } else if (json['rotation_duration'] is num) {
        rotationDurationSeconds = (json['rotation_duration'] as num).toInt();
      }
      // Validate: allow 0 = OFF, clamp only invalid (<0 or >60) back to default.
      if (rotationDurationSeconds != null &&
          (rotationDurationSeconds < 0 || rotationDurationSeconds > 60)) {
        app_logger.Logger.warning(
          'Invalid rotation_duration: $rotationDurationSeconds (must be 0-60 seconds), using default 5',
          tag: 'EngagementService',
        );
        rotationDurationSeconds = 5; // Use default instead of null
      }
    } else {
      // Backend should always send rotation_duration now, but if missing, use default
      app_logger.Logger.warning(
        'rotation_duration not found in response for item ${json['id']}, using default 5 seconds',
        tag: 'EngagementService',
      );
      rotationDurationSeconds = 5; // Use default instead of null
    }

    // Ensure we always have a valid value (backend should provide this, but safety check)
    // IMPORTANT: Allow 0 = OFF to pass through for global/per-item OFF state.
    if (rotationDurationSeconds == null) {
      rotationDurationSeconds = 5;
    }

    /// Parse user_bet_amount from API (User Amount mode: 1, 2, 3...).
    int? _parseUserBetAmount(dynamic v) {
      if (v == null) return null;
      if (v is int && v > 0) return v;
      if (v is num) {
        final i = v.toInt();
        return i > 0 ? i : null;
      }
      final parsed = int.tryParse(v.toString());
      return (parsed != null && parsed > 0) ? parsed : null;
    }

    final interactionCount = (json['interaction_count'] is int)
        ? json['interaction_count'] as int
        : (json['interaction_count'] is num)
        ? (json['interaction_count'] as num).toInt()
        : 0;

    final pollVotingSchedule = json['poll_voting_schedule'] is Map
        ? Map<String, dynamic>.from(json['poll_voting_schedule'] as Map)
        : null;
    /*
    Old Code: [poll_result] only when already a Map — JSON string payloads were dropped.
    final pollResult = json['poll_result'] is Map
        ? Map<String, dynamic>.from(json['poll_result'] as Map)
        : null;
    */
    // New Code: accept Map or JSON-encoded string (same pattern as [quiz_data] above).
    Map<String, dynamic>? pollResult;
    final rawPollResult = json['poll_result'];
    if (rawPollResult is Map) {
      pollResult = Map<String, dynamic>.from(rawPollResult);
    } else if (rawPollResult is String && rawPollResult.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPollResult);
        if (decoded is Map) {
          pollResult = Map<String, dynamic>.from(decoded);
        } else {
          app_logger.Logger.warning(
            'poll_result string did not decode to an object (item ${json['id']})',
            tag: 'EngagementService',
          );
        }
      } catch (e) {
        app_logger.Logger.warning(
          'Failed to decode poll_result string for item ${json['id']}: $e',
          tag: 'EngagementService',
          error: e,
        );
      }
    } else if (rawPollResult != null) {
      app_logger.Logger.warning(
        'poll_result has unexpected type ${rawPollResult.runtimeType} for item ${json['id']}',
        tag: 'EngagementService',
      );
    }

    Map<int, int>? _parseUserBetUnitsPerOption(dynamic raw) {
      if (raw == null) return null;
      Map<String, dynamic>? m;
      if (raw is Map) {
        m = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map) m = Map<String, dynamic>.from(d);
        } catch (_) {}
      }
      if (m == null || m.isEmpty) return null;
      final out = <int, int>{};
      m.forEach((k, v) {
        final ki = int.tryParse(k.toString());
        final vi = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (ki != null && ki >= 0 && vi > 0) out[ki] = vi;
      });
      return out.isEmpty ? null : out;
    }

    return EngagementItem(
      id: json['id'] ?? 0,
      type: type,
      title: json['title'] ?? '',
      mediaUrl: finalMediaUrl,
      content: json['content'] ?? '',
      rewardPoints: (json['reward_points'] is int)
          ? json['reward_points'] as int
          : (json['reward_points'] is String)
          ? int.tryParse(json['reward_points']) ?? 0
          : 0,
      quizData: quizData,
      hasInteracted:
          json['has_interacted'] == true ||
          json['has_interacted'] == 1 ||
          json['has_interacted'] == '1',
      userAnswer: json['user_answer']?.toString(),
      userBetAmount: _parseUserBetAmount(json['user_bet_amount']),
      userBetUnitsPerOption: _parseUserBetUnitsPerOption(
        json['user_bet_amount_per_option'] ?? json['bet_amount_per_option'],
      ),
      rotationDurationSeconds: rotationDurationSeconds,
      interactionCount: interactionCount,
      pollVotingSchedule: pollVotingSchedule,
      pollResult: pollResult,
      rawData: Map<String, dynamic>.from(json),
    );
  }
}

/// Engagement Service for API calls
class EngagementService {
  static String? _lastError;
  static String? get lastError => _lastError;

  /// Get engagement feed for current user
  /// Uses WooCommerce authentication like other services (Point Service pattern)
  static Future<List<EngagementItem>> getFeed({
    required int userId,
    String? token, // Optional - kept for backward compatibility but not used
  }) async {
    _lastError = null;

    try {
      // Use same pattern as Point Service - user_id in path, not query param
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/engagement/feed/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info(
        'Fetching engagement feed for user: $userId',
        tag: 'EngagementService',
      );
      app_logger.Logger.info(
        'Engagement feed URL: $uri',
        tag: 'EngagementService',
      );

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          skipAuth: false,
        ),
        context: 'getEngagementFeed',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(
            response,
          );
          if (data == null) {
            _lastError = 'Failed to parse engagement feed response';
            return [];
          }

          app_logger.Logger.info(
            'Engagement feed response: success=${data['success']}, hasData=${data['data'] != null}, dataType=${data['data']?.runtimeType}',
            tag: 'EngagementService',
          );

          if (data['success'] == true && data['data'] != null) {
            final rawItems = data['data'] as List;
            app_logger.Logger.info(
              'Raw items count: ${rawItems.length}',
              tag: 'EngagementService',
            );

            if (rawItems.isNotEmpty) {
              app_logger.Logger.info(
                'First item sample: ${jsonEncode(rawItems[0])}',
                tag: 'EngagementService',
              );
            }

            final List<EngagementItem> items = [];
            for (var i = 0; i < rawItems.length; i++) {
              try {
                final item = EngagementItem.fromJson(
                  rawItems[i] as Map<String, dynamic>,
                );
                items.add(item);
                app_logger.Logger.info(
                  'Successfully parsed item ${i + 1}: id=${item.id}, type=${item.type}, title=${item.title}',
                  tag: 'EngagementService',
                );
              } catch (e) {
                app_logger.Logger.error(
                  'Failed to parse engagement item ${i + 1}: $e',
                  tag: 'EngagementService',
                  error: e,
                );
                app_logger.Logger.error(
                  'Item data: ${jsonEncode(rawItems[i])}',
                  tag: 'EngagementService',
                );
                // Continue parsing other items even if one fails
              }
            }

            app_logger.Logger.info(
              'Loaded ${items.length} engagement items (${rawItems.length} total, ${rawItems.length - items.length} failed)',
              tag: 'EngagementService',
            );
            return items;
          } else {
            _lastError =
                data['message']?.toString() ?? 'Failed to load engagement feed';
            app_logger.Logger.warning(
              'Engagement feed returned success=false or null data. Response: ${jsonEncode(data)}',
              tag: 'EngagementService',
            );
            return [];
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final String full = ApiService.responseBodyString(response);
          final responsePreview = full.length > 500
              ? '${full.substring(0, 500)}...'
              : full;
          app_logger.Logger.error(
            'Engagement feed JSON parse error: $_lastError',
            tag: 'EngagementService',
            error: e,
            stackTrace: stackTrace,
          );
          app_logger.Logger.error(
            'Response body preview: $responsePreview',
            tag: 'EngagementService',
          );
          return [];
        }
      } else {
        _lastError =
            'Invalid response from server. Status: ${response?.statusCode}';
        app_logger.Logger.error(
          'Engagement feed invalid response: $_lastError',
          tag: 'EngagementService',
        );
        return [];
      }
    } catch (e) {
      _lastError = 'Engagement feed exception: ${e.toString()}';
      app_logger.Logger.error(
        'Engagement feed exception: $_lastError',
        tag: 'EngagementService',
        error: e,
      );
      return [];
    }
  }

  /// Fetch lightweight updates (interaction_count, poll_result) for auto-update without full refresh.
  /// Returns list of {id, interaction_count, poll_result?} for merging into existing items.
  static Future<List<Map<String, dynamic>>> getUpdates({
    required int userId,
    List<int>? itemIds,
  }) async {
    _lastError = null;
    try {
      var uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/engagement/updates/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());
      if (itemIds != null && itemIds.isNotEmpty) {
        uri = uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'item_ids': itemIds.join(','),
          },
        );
      }
      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          skipAuth: false,
        ),
        context: 'getEngagementUpdates',
      );
      if (response == null || !NetworkUtils.isValidDioResponse(response)) {
        return [];
      }
      final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
      if (data == null) {
        return [];
      }
      if (data['success'] != true) return [];
      final raw = data['updates'];
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => {
              'id': e['id'],
              'interaction_count': e['interaction_count'],
              'poll_result': e['poll_result'],
              'poll_voting_schedule': e['poll_voting_schedule'],
              'has_interacted': e['has_interacted'],
            },
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// GET `/twork/v1/poll/state/{pollId}` — requires auth (same as engagement feed).
  /// Returns the full JSON body (`success`, `data`, …) or null on failure.
  static Future<Map<String, dynamic>?> fetchPollState({
    required int pollId,
  }) async {
    _lastError = null;
    if (pollId <= 0) {
      _lastError = 'Invalid poll id';
      return null;
    }
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/poll/state/$pollId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          skipAuth: false,
        ),
        context: 'fetchPollState',
      );

      if (!NetworkUtils.isValidDioResponse(response)) {
        _lastError =
            'Poll state: invalid response (HTTP ${response?.statusCode})';
        return null;
      }

      return ApiService.responseAsJsonMap(response);
    } catch (e) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error(
        'fetchPollState failed: $_lastError',
        tag: 'EngagementService',
        error: e,
      );
      return null;
    }
  }

  /// GET `/twork/v1/poll/results/{pollId}/{sessionId}` — requires auth.
  /// [userId] is sent as `user_id` when > 0 (per-session vote / win resolution).
  static Future<Map<String, dynamic>?> fetchPollResults({
    required int pollId,
    required String sessionId,
    int userId = 0,
  }) async {
    _lastError = null;
    if (pollId <= 0 || sessionId.isEmpty) {
      _lastError = 'Invalid poll id or session';
      return null;
    }
    try {
      final query = <String, String>{
        ..._getWooCommerceAuthQueryParams(),
        if (userId > 0) 'user_id': userId.toString(),
      };
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/poll/results/$pollId/${Uri.encodeComponent(sessionId)}',
      ).replace(queryParameters: query);

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          skipAuth: false,
        ),
        context: 'fetchPollResults',
      );

      if (!NetworkUtils.isValidDioResponse(response)) {
        _lastError =
            'Poll results: invalid response (HTTP ${response?.statusCode})';
        return null;
      }

      return ApiService.responseAsJsonMap(response);
    } catch (e) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error(
        'fetchPollResults failed: $_lastError',
        tag: 'EngagementService',
        error: e,
      );
      return null;
    }
  }

  /// Submit user interaction (quiz answer, poll vote)
  /// Uses WooCommerce authentication like other services (Point Service pattern)
  /// [sessionId] Optional - for AUTO_RUN polls, pass current_session_id from poll-state API.
  /// [selectedOptionIds] Optional - for multi-select polls, pass list of option indices. If provided, used instead of answer.
  /// [betAmount] Optional - for polls, single amount for all options (legacy).
  /// [betAmountPerOption] Optional - for polls, per-option amounts {optionIndex: amount}. Takes precedence over betAmount.
  static Future<Map<String, dynamic>> submitInteraction({
    required int userId,
    String? token, // Optional - kept for backward compatibility but not used
    required int itemId,
    required String answer,
    String? sessionId, // Optional - for poll session scoping (AUTO_RUN mode)
    List<int>? selectedOptionIds, // Optional - for multi-select polls
    int? betAmount, // Optional - poll bet amount (single for all options)
    Map<int, int>? betAmountPerOption, // Optional - per-option amounts
  }) async {
    try {
      _lastError = null;

      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/engagement/interact',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info(
        'Submitting interaction for item: $itemId',
        tag: 'EngagementService',
      );
      app_logger.Logger.info('Interaction URL: $uri', tag: 'EngagementService');

      final bodyMap = <String, dynamic>{
        'user_id': userId,
        'item_id': itemId,
        'answer': answer,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      };
      if (selectedOptionIds != null && selectedOptionIds.isNotEmpty) {
        bodyMap['selected_option_ids'] = selectedOptionIds;
      }
      if (betAmountPerOption != null && betAmountPerOption.isNotEmpty) {
        bodyMap['bet_amount_per_option'] = betAmountPerOption.map(
          (k, v) => MapEntry(k.toString(), v),
        );
      } else if (betAmount != null && betAmount > 0) {
        bodyMap['bet_amount'] = betAmount;
      }
      /*
      Old Code: executeWithRetry re-POSTs on timeout after the server may have already
      applied the vote/deduction → double-transaction risk. No Idempotency-Key on retries.
      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: bodyMap,
        ),
        context: 'submitInteraction',
      );
      */

      // One-shot POST only: single network attempt per user action; backend may dedupe via header.
      final String idempotencyKey =
          'eng_interact_${userId}_${itemId}_${sessionId ?? 'nosess'}_${DateTime.now().microsecondsSinceEpoch}';
      Response<dynamic>? response;
      try {
        response = await ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          skipAuth: false,
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
            'Idempotency-Key': idempotencyKey,
          },
          data: bodyMap,
        ).timeout(AppConfig.networkTimeout);
      } on TimeoutException catch (e) {
        _lastError = 'Request timed out';
        app_logger.Logger.error(
          'Interaction timed out after ${AppConfig.networkTimeout.inSeconds}s',
          tag: 'EngagementService',
          error: e,
        );
        return {'success': false, 'message': _lastError!};
      } on DioException catch (e) {
        response = e.response;
        if (response == null) {
          _lastError = NetworkUtils.getErrorMessage(e);
          app_logger.Logger.error(
            'Interaction failed (no response body): $_lastError',
            tag: 'EngagementService',
            error: e,
          );
          return {'success': false, 'message': _lastError ?? 'Network error'};
        }
      } catch (e, stackTrace) {
        _lastError = NetworkUtils.getErrorMessage(e);
        app_logger.Logger.error(
          'Interaction request failed: $_lastError',
          tag: 'EngagementService',
          error: e,
          stackTrace: stackTrace,
        );
        return {'success': false, 'message': _lastError ?? 'Request failed'};
      }

      // PROFESSIONAL FIX: Parse JSON even on non-2xx responses (e.g. 400 already-voted)
      try {
        Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
        data ??= () {
          try {
            final Object? d = jsonDecode(
              ApiService.responseBodyString(response),
            );
            if (d is Map<String, dynamic>) return d;
            if (d is Map) return Map<String, dynamic>.from(d);
          } catch (_) {}
          return null;
        }();
        if (data == null) {
          throw const FormatException('Response is not JSON object');
        }

        int? parseNumeric(dynamic v) {
          if (v == null) return null;
          if (v is int) return v;
          if (v is num) return v.toInt();
          final s = v.toString().trim().replaceAll(RegExp(r'[^0-9-]'), '');
          if (s.isEmpty || s == '-') return null;
          return int.tryParse(s);
        }

        if (data['success'] == true) {
          // Old Code:
          // final responseData = data['data'] as Map<String, dynamic>?;
          //
          // New Code:
          // Accept dynamic map payload and normalize key numeric fields for callers.
          final rawResponseData = data['data'];
          final responseData = rawResponseData is Map
              ? Map<String, dynamic>.from(rawResponseData)
              : null;
          final isCorrect =
              responseData?['is_correct'] ?? data['is_correct'] ?? false;
          final pointsEarnedRaw =
              responseData?['points_earned'] ??
              data['points_earned'] ??
              data['points_awarded'] ??
              0;

          /*
          Old Code:
          final parsedNewBalance = parseNumeric(
            responseData?['new_balance'] ?? data['new_balance'],
          );
          */
          int? pickFirstBalance() {
            final rd = responseData;
            final candidates = <dynamic>[
              if (rd != null) ...[
                rd['new_balance'],
                rd['current_balance'],
                rd['points_balance'],
                rd['pnp_balance'],
                rd['balance'],
                rd['currentBalance'],
                rd['pointsBalance'],
              ],
              data?['new_balance'],
              data?['current_balance'],
              data?['points_balance'],
              data?['balance'],
            ];
            for (final c in candidates) {
              final v = parseNumeric(c);
              if (v != null) return v;
            }
            return null;
          }

          final parsedNewBalance = pickFirstBalance();

          final parsedRequired = parseNumeric(
            responseData?['required'] ?? data['required'],
          );
          final parsedBalance = parseNumeric(
            responseData?['balance'] ?? data['balance'],
          );

          app_logger.Logger.info(
            'Interaction submitted successfully - Correct: $isCorrect, Points: $pointsEarnedRaw',
            tag: 'EngagementService',
          );
          return {
            'success': true,
            'is_correct': isCorrect,
            'points_earned': pointsEarnedRaw is int
                ? pointsEarnedRaw
                : (pointsEarnedRaw as num).toInt(),
            'message': data['message']?.toString() ?? 'Success',
            'data': responseData,
            if (parsedNewBalance != null) 'new_balance': parsedNewBalance,
            if (parsedNewBalance != null) 'current_balance': parsedNewBalance,
            if (parsedRequired != null) 'required': parsedRequired,
            if (parsedBalance != null) 'balance': parsedBalance,
          };
        }

        _lastError =
            data['message']?.toString() ?? 'Failed to submit interaction';

        // Duplicate detection: prefer explicit flags/codes, fallback to message text
        final code = data['code']?.toString().toLowerCase();
        final isDuplicate =
            data['is_duplicate'] == true ||
            code == 'already_voted' ||
            (_lastError?.toLowerCase().contains('already') ?? false);

        if (isDuplicate) {
          app_logger.Logger.warning(
            'Duplicate interaction detected: $_lastError (code=$code)',
            tag: 'EngagementService',
          );
          final responseData = data['data'] as Map<String, dynamic>?;
          return {
            'success': false,
            'message': _lastError,
            'data': responseData,
            'is_duplicate': true,
            'code': code,
          };
        }

        app_logger.Logger.error(
          'Interaction error: $_lastError (status=${response.statusCode})',
          tag: 'EngagementService',
        );

        // Old Code: return {
        // Old Code:   'success': false,
        // Old Code:   'message': _lastError,
        // Old Code:   'data': data['data'],
        // Old Code:   'code': code,
        // Old Code:   // Pass through balance/required for insufficient_balance (backend puts at top level)
        // Old Code:   if (data['balance'] != null) 'balance': data['balance'],
        // Old Code:   if (data['required'] != null) 'required': data['required'],
        // Old Code: };
        final parsedBalance = parseNumeric(data['balance']);
        final parsedRequired = parseNumeric(data['required']);

        return {
          'success': false,
          'message': _lastError,
          'data': data['data'],
          'code': code,
          // Keep authoritative insufficient payload normalized as int for UI validators/messages.
          if (parsedBalance != null) 'balance': parsedBalance,
          if (parsedRequired != null) 'required': parsedRequired,
        };
      } catch (e, stackTrace) {
        // Not JSON (or unexpected). Fall back to status-based error.
        _lastError =
            'Invalid response from server. Status: ${response.statusCode}';
        final String full = ApiService.responseBodyString(response);
        final responsePreview = full.length > 500
            ? '${full.substring(0, 500)}...'
            : full;
        app_logger.Logger.error(
          'Interaction parse failed: $_lastError',
          tag: 'EngagementService',
          error: e,
          stackTrace: stackTrace,
        );
        app_logger.Logger.error(
          'Response body preview: $responsePreview',
          tag: 'EngagementService',
        );
        return {'success': false, 'message': _lastError};
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error(
        'Interaction exception: $_lastError',
        tag: 'EngagementService',
        error: e,
        stackTrace: stackTrace,
      );
      return {'success': false, 'message': _lastError};
    }
  }
}
