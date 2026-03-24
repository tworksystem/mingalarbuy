import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';
import '../utils/logger.dart' as app_logger;
import '../utils/network_utils.dart';

/// Get WooCommerce authentication query parameters
/// Same as other services (point_service, wallet_service, etc.)
Map<String, String> _getWooCommerceAuthQueryParams() {
  return {
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

  factory QuizData.fromJson(Map<String, dynamic> json) {
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
    final pollBaseCost = (json['poll_base_cost'] as num?)?.toInt() ??
        (json['pollBaseCost'] as num?)?.toInt() ??
        0;

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
  final int?
      rotationDurationSeconds; // Rotation duration in seconds (null = use default)
  final int interactionCount; // Total interactions (for corner badge)
  final Map<String, dynamic>? pollVotingSchedule; // seconds_until_close, voting_status, result_display_ends_at, etc.
  final Map<String, dynamic>? pollResult; // vote_counts, vote_percentages, winning_index (when showing result)

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
    this.rotationDurationSeconds,
    this.interactionCount = 0,
    this.pollVotingSchedule,
    this.pollResult,
  });

  /// Create a copy with updated fields (for merging lightweight updates without full refresh)
  /// Set [clearPollResult] true when poll resets (e.g. Auto Run new period) to show Vote Now again.
  EngagementItem copyWith({
    int? interactionCount,
    Map<String, dynamic>? pollResult,
    Map<String, dynamic>? pollVotingSchedule,
    bool? hasInteracted,
    int? userBetAmount,
    bool clearPollResult = false,
  }) =>
      EngagementItem(
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
        rotationDurationSeconds: rotationDurationSeconds,
        interactionCount: interactionCount ?? this.interactionCount,
        pollVotingSchedule: pollVotingSchedule ?? this.pollVotingSchedule,
        pollResult: clearPollResult ? null : (pollResult ?? this.pollResult),
      );

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
            app_logger.Logger.warning('quiz_data is empty string, skipping',
                tag: 'EngagementService');
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
              tag: 'EngagementService');
        } else if (raw != null) {
          app_logger.Logger.warning(
              'quiz_data is not a valid object: ${raw.runtimeType}',
              tag: 'EngagementService');
        }
      } catch (e) {
        app_logger.Logger.error(
            'Failed to parse quiz_data: $e, data: ${json['quiz_data']}',
            tag: 'EngagementService',
            error: e);
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
            tag: 'EngagementService');
        rotationDurationSeconds = 5; // Use default instead of null
      }
    } else {
      // Backend should always send rotation_duration now, but if missing, use default
      app_logger.Logger.warning(
          'rotation_duration not found in response for item ${json['id']}, using default 5 seconds',
          tag: 'EngagementService');
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

    final pollVotingSchedule = json['poll_voting_schedule'] is Map<String, dynamic>
        ? json['poll_voting_schedule'] as Map<String, dynamic>
        : null;
    final pollResult = json['poll_result'] is Map<String, dynamic>
        ? json['poll_result'] as Map<String, dynamic>
        : null;

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
      hasInteracted: json['has_interacted'] == true ||
          json['has_interacted'] == 1 ||
          json['has_interacted'] == '1',
      userAnswer: json['user_answer']?.toString(),
      userBetAmount: _parseUserBetAmount(json['user_bet_amount']),
      rotationDurationSeconds: rotationDurationSeconds,
      interactionCount: interactionCount,
      pollVotingSchedule: pollVotingSchedule,
      pollResult: pollResult,
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

      app_logger.Logger.info('Fetching engagement feed for user: $userId',
          tag: 'EngagementService');
      app_logger.Logger.info('Engagement feed URL: $uri',
          tag: 'EngagementService');

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'getEngagementFeed',
      );

      if (NetworkUtils.isValidResponse(response)) {
        try {
          final data = jsonDecode(response!.body) as Map<String, dynamic>;

          app_logger.Logger.info(
              'Engagement feed response: success=${data['success']}, hasData=${data['data'] != null}, dataType=${data['data']?.runtimeType}',
              tag: 'EngagementService');

          if (data['success'] == true && data['data'] != null) {
            final rawItems = data['data'] as List;
            app_logger.Logger.info('Raw items count: ${rawItems.length}',
                tag: 'EngagementService');

            if (rawItems.isNotEmpty) {
              app_logger.Logger.info(
                  'First item sample: ${jsonEncode(rawItems[0])}',
                  tag: 'EngagementService');
            }

            final List<EngagementItem> items = [];
            for (var i = 0; i < rawItems.length; i++) {
              try {
                final item = EngagementItem.fromJson(
                    rawItems[i] as Map<String, dynamic>);
                items.add(item);
                app_logger.Logger.info(
                    'Successfully parsed item ${i + 1}: id=${item.id}, type=${item.type}, title=${item.title}',
                    tag: 'EngagementService');
              } catch (e) {
                app_logger.Logger.error(
                    'Failed to parse engagement item ${i + 1}: $e',
                    tag: 'EngagementService',
                    error: e);
                app_logger.Logger.error('Item data: ${jsonEncode(rawItems[i])}',
                    tag: 'EngagementService');
                // Continue parsing other items even if one fails
              }
            }

            app_logger.Logger.info(
                'Loaded ${items.length} engagement items (${rawItems.length} total, ${rawItems.length - items.length} failed)',
                tag: 'EngagementService');
            return items;
          } else {
            _lastError =
                data['message']?.toString() ?? 'Failed to load engagement feed';
            app_logger.Logger.warning(
                'Engagement feed returned success=false or null data. Response: ${jsonEncode(data)}',
                tag: 'EngagementService');
            return [];
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final responsePreview = response!.body.length > 500
              ? '${response.body.substring(0, 500)}...'
              : response.body;
          app_logger.Logger.error(
              'Engagement feed JSON parse error: $_lastError',
              tag: 'EngagementService',
              error: e,
              stackTrace: stackTrace);
          app_logger.Logger.error('Response body preview: $responsePreview',
              tag: 'EngagementService');
          return [];
        }
      } else {
        _lastError =
            'Invalid response from server. Status: ${response?.statusCode}';
        app_logger.Logger.error('Engagement feed invalid response: $_lastError',
            tag: 'EngagementService');
        return [];
      }
    } catch (e) {
      _lastError = 'Engagement feed exception: ${e.toString()}';
      app_logger.Logger.error('Engagement feed exception: $_lastError',
          tag: 'EngagementService', error: e);
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
          queryParameters: {
            ...uri.queryParameters,
            'item_ids': itemIds.join(','),
          },
        );
      }
      final response = await NetworkUtils.executeRequest(
        () => http.get(uri, headers: const {'Content-Type': 'application/json'}),
        context: 'getEngagementUpdates',
      );
      if (response == null || !NetworkUtils.isValidResponse(response)) {
        return [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) return [];
      final raw = data['updates'];
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => {
                'id': e['id'],
                'interaction_count': e['interaction_count'],
                'poll_result': e['poll_result'],
                'poll_voting_schedule': e['poll_voting_schedule'],
                'has_interacted': e['has_interacted'],
              })
          .toList();
    } catch (e) {
      return [];
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

      // Use same pattern as Point Service - WooCommerce auth in query params
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/engagement/interact',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info('Submitting interaction for item: $itemId',
          tag: 'EngagementService');
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
      final body = jsonEncode(bodyMap);

      final response = await NetworkUtils.executeRequest(
        () => http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: body,
        ),
        context: 'submitInteraction',
      );

      if (response == null) {
        _lastError = 'No response from server';
        app_logger.Logger.error('Interaction failed: $_lastError',
            tag: 'EngagementService');
        return {
          'success': false,
          'message': _lastError,
        };
      }

      // PROFESSIONAL FIX: Parse JSON even on non-2xx responses (e.g. 400 already-voted)
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          // Handle new response format with nested 'data' object
          final responseData = data['data'] as Map<String, dynamic>?;
          final isCorrect =
              responseData?['is_correct'] ?? data['is_correct'] ?? false;
          final pointsEarned = responseData?['points_earned'] ??
              data['points_earned'] ??
              data['points_awarded'] ??
              0;

          app_logger.Logger.info(
              'Interaction submitted successfully - Correct: $isCorrect, Points: $pointsEarned',
              tag: 'EngagementService');
          return {
            'success': true,
            'is_correct': isCorrect,
            'points_earned': pointsEarned is int
                ? pointsEarned
                : (pointsEarned as num).toInt(),
            'message': data['message']?.toString() ?? 'Success',
            'data': responseData,
          };
        }

        _lastError =
            data['message']?.toString() ?? 'Failed to submit interaction';

        // Duplicate detection: prefer explicit flags/codes, fallback to message text
        final code = data['code']?.toString().toLowerCase();
        final isDuplicate = data['is_duplicate'] == true ||
            code == 'already_voted' ||
            (_lastError?.toLowerCase().contains('already') ?? false);

        if (isDuplicate) {
          app_logger.Logger.warning(
              'Duplicate interaction detected: $_lastError (code=$code)',
              tag: 'EngagementService');
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
            tag: 'EngagementService');
        return {
          'success': false,
          'message': _lastError,
          'data': data['data'],
          'code': code,
          // Pass through balance/required for insufficient_balance (backend puts at top level)
          if (data['balance'] != null) 'balance': data['balance'],
          if (data['required'] != null) 'required': data['required'],
        };
      } catch (e, stackTrace) {
        // Not JSON (or unexpected). Fall back to status-based error.
        _lastError =
            'Invalid response from server. Status: ${response.statusCode}';
        final responsePreview = response.body.length > 500
            ? '${response.body.substring(0, 500)}...'
            : response.body;
        app_logger.Logger.error('Interaction parse failed: $_lastError',
            tag: 'EngagementService', error: e, stackTrace: stackTrace);
        app_logger.Logger.error('Response body preview: $responsePreview',
            tag: 'EngagementService');
        return {
          'success': false,
          'message': _lastError,
        };
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error('Interaction exception: $_lastError',
          tag: 'EngagementService', error: e, stackTrace: stackTrace);
      return {
        'success': false,
        'message': _lastError,
      };
    }
  }
}
