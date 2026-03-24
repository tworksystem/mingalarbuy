import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/engagement_service.dart';
import '../utils/logger.dart' as app_logger;

bool _pollResultEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == b) return true;
  if (a == null || b == null) return false;
  return jsonEncode(a) == jsonEncode(b);
}

bool _scheduleEquals(
    Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == b) return true;
  if (a == null || b == null) return false;
  return jsonEncode(a) == jsonEncode(b);
}

/// Engagement Provider for managing engagement items state
class EngagementProvider with ChangeNotifier {
  List<EngagementItem> _items = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounceTimer;
  Timer? _pollingTimer; // Timer for automatic data refresh
  int? _currentUserId; // Track which user the data belongs to
  bool _hasLoadedForCurrentUser =
      false; // Track if we've loaded for current user
  bool _isAutoPollPaused =
      false; // Temporarily pause auto-poll for poll/result transitions
  /// 2 seconds for near-instant sync on backend create/delete
  static const Duration _pollingInterval = Duration(seconds: 2);

  List<EngagementItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasItems => _items.isNotEmpty;
  bool get isAutoPollPaused => _isAutoPollPaused;

  /// Handle authentication state changes
  /// Automatically loads feed when user becomes authenticated
  /// PROFESSIONAL FIX: Properly handles user account switching by clearing cache
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    int? userId,
  }) async {
    if (isAuthenticated && userId != null) {
      // PROFESSIONAL FIX: If user changed, immediately clear old data and reset flags
      if (_currentUserId != null && _currentUserId != userId) {
        app_logger.Logger.info(
            'User account changed from $_currentUserId to $userId, clearing engagement cache',
            tag: 'EngagementProvider');
        // Stop polling for old user
        _stopPolling();
        // Clear old user's data immediately
        _items = [];
        _error = null;
        _hasLoadedForCurrentUser = false;
        notifyListeners(); // Notify UI immediately that data is cleared
      }

      // Only load if this is a new user or we haven't loaded for this user yet
      if (_currentUserId != userId || !_hasLoadedForCurrentUser) {
        _currentUserId = userId;
        app_logger.Logger.info(
            'User authenticated, loading engagement feed for user: $userId',
            tag: 'EngagementProvider');
        // PROFESSIONAL FIX: Force refresh when user changes to ensure fresh data
        await loadFeed(
          userId: userId,
          forceRefresh:
              _currentUserId != userId, // Force refresh if user changed
        );
        _hasLoadedForCurrentUser = true;
      } else {
        app_logger.Logger.info(
            'Engagement feed already loaded for user $userId, skipping reload',
            tag: 'EngagementProvider');
      }
    } else {
      // User logged out - clear state and stop polling
      final previousUserId = _currentUserId;
      _stopPolling();
      _currentUserId = null;
      _hasLoadedForCurrentUser = false;
      _items = [];
      _error = null;
      notifyListeners();
      app_logger.Logger.info(
          'User logged out (previous user: $previousUserId), cleared engagement data',
          tag: 'EngagementProvider');
    }
  }

  /// Load engagement feed
  /// Token is optional - service now uses WooCommerce auth like other services
  Future<void> loadFeed({
    required int userId,
    String? token, // Optional - kept for backward compatibility
    bool forceRefresh = false,
  }) async {
    // If forcing refresh, always reload even if loading
    if (_isLoading && !forceRefresh) {
      app_logger.Logger.info('Engagement feed already loading, skipping',
          tag: 'EngagementProvider');
      return;
    }

    // PROFESSIONAL FIX: Check if userId matches before skipping
    // If userId changed, we need to reload even if items exist
    // CRITICAL: Always reload if userId doesn't match, even if items exist
    if (_items.isNotEmpty && !forceRefresh) {
      if (_currentUserId == userId) {
        app_logger.Logger.info(
            'Engagement feed already loaded for user $userId, skipping',
            tag: 'EngagementProvider');
        return;
      } else {
        // User ID mismatch - this should not happen if handleAuthStateChange is called correctly
        // But handle it gracefully by clearing and reloading
        app_logger.Logger.warning(
            'User ID mismatch detected: current=$_currentUserId, requested=$userId. Clearing and reloading.',
            tag: 'EngagementProvider');
        _items = [];
        _error = null;
        _hasLoadedForCurrentUser = false;
      }
    }

    // If userId changed, clear old data first (defensive check)
    if (_currentUserId != null && _currentUserId != userId) {
      app_logger.Logger.info(
          'User changed from $_currentUserId to $userId, clearing old engagement data',
          tag: 'EngagementProvider');
      _items = [];
      _error = null;
      _hasLoadedForCurrentUser = false;
    }

    // Update current user ID
    _currentUserId = userId;

    _setLoading(true);
    _error = null;

    try {
      app_logger.Logger.info('Loading engagement feed for user: $userId',
          tag: 'EngagementProvider');

      final items = await EngagementService.getFeed(
        userId: userId,
        token: token,
      );

      _items = items;
      _error = EngagementService.lastError;

      if (_error != null) {
        app_logger.Logger.error(
            'Failed to load engagement feed: $_error, items count: ${_items.length}',
            tag: 'EngagementProvider');
      } else if (_items.isEmpty) {
        app_logger.Logger.warning(
            'Engagement feed loaded successfully but no items returned. This could mean: 1) No active items in database, 2) All items are outside date range, 3) All items are inactive.',
            tag: 'EngagementProvider');
      } else {
        app_logger.Logger.info(
            'Successfully loaded ${_items.length} engagement items',
            tag: 'EngagementProvider');
      }

      // Start automatic polling after successful load
      _startPolling(userId: userId, token: token);
    } catch (e) {
      _error = 'Failed to load engagement feed: ${e.toString()}';
      app_logger.Logger.error('Engagement feed exception',
          tag: 'EngagementProvider', error: e);
      _items = []; // Ensure items is empty on error
    } finally {
      _setLoading(false);
    }
  }

  /// Apply interaction update locally (fallback when backend does not return updated_item).
  void _applyLocalInteractionUpdate(int itemId, String answer, {int? betAmount, Map<int, int>? betAmountPerOption}) {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      app_logger.Logger.warning(
          'Item $itemId not found in local items list after successful submission',
          tag: 'EngagementProvider');
      return;
    }
    final existing = _items[index];
    final updatedItem = EngagementItem(
      id: existing.id,
      type: existing.type,
      title: existing.title,
      mediaUrl: existing.mediaUrl,
      content: existing.content,
      rewardPoints: existing.rewardPoints,
      quizData: existing.quizData,
      hasInteracted: true,
      userAnswer: answer,
      userBetAmount: betAmount ?? existing.userBetAmount,
      rotationDurationSeconds: existing.rotationDurationSeconds,
      interactionCount: existing.interactionCount + 1,
    );
    _items[index] = updatedItem;
    notifyListeners();
    app_logger.Logger.info(
        'Updated item $itemId interaction status locally (hasInteracted=true)',
        tag: 'EngagementProvider');
  }

  /// Submit interaction (quiz answer, poll vote)
  /// Token is optional - service now uses WooCommerce auth like other services
  /// PROFESSIONAL FIX: Validates user ID before submission to prevent cross-user submissions
  /// Auto-update: when backend returns updated_item, feed is merged without refresh
  Future<Map<String, dynamic>> submitInteraction({
    required int userId,
    String? token, // Optional - kept for backward compatibility
    required int itemId,
    required String answer,
    String? sessionId, // Optional - for poll session scoping (AUTO_RUN mode)
    List<int>? selectedOptionIds, // Optional - for multi-select polls
    int? betAmount, // Optional - for polls: single amount for all options
    Map<int, int>? betAmountPerOption, // Optional - for polls: per-option amounts
  }) async {
    // PROFESSIONAL FIX: Validate that userId matches current user
    // This prevents submitting interactions for wrong user after account switch
    if (_currentUserId != null && _currentUserId != userId) {
      app_logger.Logger.error(
          'User ID mismatch in submitInteraction: current=$_currentUserId, requested=$userId. This should not happen.',
          tag: 'EngagementProvider');
      return {
        'success': false,
        'message': 'User account mismatch. Please refresh the page.',
      };
    }

    try {
      app_logger.Logger.info(
          'Submitting interaction: userId=$userId, itemId=$itemId, answer=$answer',
          tag: 'EngagementProvider');

      final result = await EngagementService.submitInteraction(
        userId: userId,
        token: token,
        itemId: itemId,
        answer: answer,
        sessionId: sessionId,
        selectedOptionIds: selectedOptionIds,
        betAmount: betAmount,
        betAmountPerOption: betAmountPerOption,
      );

      if (result['success'] == true) {
        // Auto-update: prefer backend's updated_item so UI updates without refresh
        final data = result['data'];
        final rawUpdated = data is Map ? data['updated_item'] : null;
        final Map<String, dynamic>? updatedItemMap =
            rawUpdated is Map<String, dynamic> ? rawUpdated : null;

        if (updatedItemMap != null && updatedItemMap['id'] != null) {
          try {
            final parsed = EngagementItem.fromJson(updatedItemMap);
            final index = _items.indexWhere((item) => item.id == parsed.id);
            if (index != -1) {
              _items[index] = parsed;
              notifyListeners();
              app_logger.Logger.info(
                  'Auto-updated item ${parsed.id} from backend updated_item (no refresh needed)',
                  tag: 'EngagementProvider');
            } else {
              _items.add(parsed);
              notifyListeners();
              app_logger.Logger.info(
                  'Added new item ${parsed.id} from backend updated_item',
                  tag: 'EngagementProvider');
            }
          } catch (e, st) {
            app_logger.Logger.warning(
                'Failed to parse updated_item, falling back to local update: $e',
                tag: 'EngagementProvider',
                error: e,
                stackTrace: st);
            _applyLocalInteractionUpdate(itemId, answer, betAmount: betAmount, betAmountPerOption: betAmountPerOption);
          }
        } else {
          _applyLocalInteractionUpdate(itemId, answer, betAmount: betAmount, betAmountPerOption: betAmountPerOption);
        }
      } else {
        final message = result['message']?.toString() ?? '';
        app_logger.Logger.warning(
            'Interaction submission returned success=false: $message',
            tag: 'EngagementProvider');

        // PROFESSIONAL FIX: If backend reports a duplicate (already voted),
        // sync local state to the server's existing interaction (do NOT overwrite with attempted answer).
        final isDuplicate = result['is_duplicate'] == true ||
            (result['code']?.toString().toLowerCase() == 'already_voted');
        final index = _items.indexWhere((item) => item.id == itemId);
        if (index != -1 && isDuplicate) {
          final data = result['data'];
          final serverAnswer =
              data?['user_answer']?.toString() ?? _items[index].userAnswer;
          final serverBetAmount = data?['user_bet_amount'];
          final int? parsedBetAmount = (serverBetAmount is int && serverBetAmount > 0)
              ? serverBetAmount
              : (serverBetAmount is num
                  ? (serverBetAmount).toInt()
                  : int.tryParse(serverBetAmount?.toString() ?? ''));
          final updatedItem = EngagementItem(
            id: _items[index].id,
            type: _items[index].type,
            title: _items[index].title,
            mediaUrl: _items[index].mediaUrl,
            content: _items[index].content,
            rewardPoints: _items[index].rewardPoints,
            quizData: _items[index].quizData,
            hasInteracted: true,
            userAnswer: serverAnswer,
            userBetAmount: (parsedBetAmount != null && parsedBetAmount > 0)
                ? parsedBetAmount
                : _items[index].userBetAmount,
            rotationDurationSeconds: _items[index].rotationDurationSeconds,
            interactionCount: _items[index].interactionCount,
          );
          _items[index] = updatedItem;
          notifyListeners();
        }
      }

      return result;
    } catch (e) {
      app_logger.Logger.error('Submit interaction exception',
          tag: 'EngagementProvider', error: e);
      return {
        'success': false,
        'message': 'Failed to submit interaction',
      };
    }
  }

  /// Refresh feed
  /// Token is optional - service now uses WooCommerce auth like other services
  Future<void> refresh({
    required int userId,
    String? token, // Optional - kept for backward compatibility
  }) async {
    await loadFeed(
      userId: userId,
      token: token,
      forceRefresh: true,
    );
  }

  /// Immediately refresh feed (for app resume, etc.)
  /// This triggers an instant refresh without waiting for polling interval
  Future<void> refreshImmediately({
    required int userId,
    String? token,
  }) async {
    app_logger.Logger.info('Immediate refresh triggered for engagement feed',
        tag: 'EngagementProvider');
    await loadFeed(
      userId: userId,
      token: token,
      forceRefresh: true,
    );
  }

  /// Clear all data
  void clear() {
    _stopPolling();
    _items = [];
    _error = null;
    _isLoading = false;
    _isAutoPollPaused = false;
    _currentUserId = null;
    _hasLoadedForCurrentUser = false;
    _notifyListenersDebounced();
  }

  /// Start automatic polling for data updates
  void _startPolling({required int userId, String? token}) {
    // Stop any existing polling first
    _stopPolling();

    // Only start polling if user is authenticated
    if (_currentUserId == null || _currentUserId != userId) {
      app_logger.Logger.warning(
          'Cannot start polling: user ID mismatch or not authenticated',
          tag: 'EngagementProvider');
      return;
    }

    app_logger.Logger.info(
        'Starting automatic polling for engagement feed (interval: ${_pollingInterval.inSeconds}s)',
        tag: 'EngagementProvider');

    _pollingTimer = Timer.periodic(_pollingInterval, (timer) async {
      if (_isAutoPollPaused) {
        app_logger.Logger.info(
          'Auto-poll is currently PAUSED for poll transitions.',
          tag: 'EngagementProvider',
        );
        return;
      }

      // Check if user is still the same
      if (_currentUserId != userId) {
        app_logger.Logger.info(
            'User changed during polling, stopping poll timer',
            tag: 'EngagementProvider');
        _stopPolling();
        return;
      }

      // Don't poll if already loading
      if (_isLoading) {
        app_logger.Logger.info('Skipping poll: feed is already loading',
            tag: 'EngagementProvider');
        return;
      }

      // Full feed refresh: poll even when empty (detects create after delete-all)
      try {
        final items = await EngagementService.getFeed(
          userId: userId,
          token: token,
        );

        // Full feed sync — detects create + delete and field updates
        final oldIds = _items.map((i) => i.id).toSet();
        final newIds = items.map((i) => i.id).toSet();
        final structureChanged = oldIds.length != newIds.length ||
            !oldIds.containsAll(newIds) ||
            !newIds.containsAll(oldIds);

        if (structureChanged) {
          _items = items;
          notifyListeners();
        } else {
          bool contentChanged = false;
          final byId = {for (var i in items) i.id: i};
          for (final a in _items) {
            final b = byId[a.id];
            if (b == null) continue;
            if (a.interactionCount != b.interactionCount ||
                !_pollResultEquals(a.pollResult, b.pollResult) ||
                !_scheduleEquals(a.pollVotingSchedule, b.pollVotingSchedule) ||
                a.hasInteracted != b.hasInteracted ||
                a.rotationDurationSeconds != b.rotationDurationSeconds) {
              contentChanged = true;
              break;
            }
          }
          if (contentChanged) {
            _items = items;
            notifyListeners();
          }
        }
      } catch (e) {
        app_logger.Logger.warning('Error during engagement updates poll: $e',
            tag: 'EngagementProvider', error: e);
      }
    });
  }

  /// Stop automatic polling
  void _stopPolling() {
    if (_pollingTimer != null) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      app_logger.Logger.info('Stopped automatic polling for engagement feed',
          tag: 'EngagementProvider');
    }
  }

  /// Public control: pause auto-polling (used by Auto-Run Poll result/countdown).
  void pauseAutoPoll() {
    if (_isAutoPollPaused) return;
    _isAutoPollPaused = true;
    app_logger.Logger.info(
      'Auto-polling PAUSED for poll transitions.',
      tag: 'EngagementProvider',
    );
  }

  /// Public control: resume auto-polling and immediately refresh the feed.
  Future<void> resumeAndFetchFeed() async {
    _isAutoPollPaused = false;
    final userId = _currentUserId;
    if (userId == null) {
      app_logger.Logger.warning(
        'resumeAndFetchFeed called but no current user is set.',
        tag: 'EngagementProvider',
      );
      return;
    }

    app_logger.Logger.info(
      'Resuming auto-polling and fetching engagement feed immediately.',
      tag: 'EngagementProvider',
    );
    await loadFeed(
      userId: userId,
      forceRefresh: true,
    );
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    // Immediate notification for loading state changes
    notifyListeners();
  }

  /// Debounced notify listeners to prevent excessive rebuilds
  void _notifyListenersDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!_isLoading) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _stopPolling();
    super.dispose();
  }
}
