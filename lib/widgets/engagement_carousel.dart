import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../providers/engagement_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/point_provider.dart';
import '../services/engagement_service.dart';
import '../services/poll_winner_popup_service.dart';
import '../services/canonical_point_balance_sync.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart' as app_logger;

/// Interactive Engagement Carousel Widget
class EngagementCarousel extends StatefulWidget {
  final VoidCallback? onRefresh;
  final int?
      initialItemId; // PROFESSIONAL FIX: Support navigation to specific item

  const EngagementCarousel({
    super.key,
    this.onRefresh,
    this.initialItemId, // Optional: scroll to specific item when provided
  });

  @override
  State<EngagementCarousel> createState() => _EngagementCarouselState();
}

class _EngagementCarouselState extends State<EngagementCarousel> {
  // Use viewportFraction 1.0 to match button width exactly
  // Buttons: parent padding (16) + container padding (4) + button padding (20) = 40 per side
  // Engagement: parent padding (16) + container padding (4) + card margin (0) + card padding (20) = 40 per side
  final PageController _pageController = PageController(viewportFraction: 1.0);
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  int? _lastUserId; // Track last user ID to detect user changes
  int? _lastRotationSeconds; // Track last applied rotation to restart auto-scroll when it changes
  String _lastWinnerScanSignature = '';
  final Set<String> _forcedOverlaySessionKeys = <String>{};
  final Map<String, DateTime> _handoverTriggeredAt = <String, DateTime>{};

  String _pollSessionKey(EngagementItem item) {
    final schedule = item.pollVotingSchedule;
    final dynamic rawSessionId = schedule?['current_session_id'];
    final dynamic rawStartedAt = schedule?['poll_actual_start_at'];
    final dynamic rawVotingStatus = schedule?['voting_status'];
    final sessionId = (rawSessionId == null || rawSessionId.toString().isEmpty)
        ? 'nosession'
        : rawSessionId.toString();
    final startedAt = (rawStartedAt == null || rawStartedAt.toString().isEmpty)
        ? 'nostart'
        : rawStartedAt.toString();
    final votingStatus = (rawVotingStatus == null || rawVotingStatus.toString().isEmpty)
        ? 'unknown'
        : rawVotingStatus.toString().toLowerCase();
    return '${item.id}_${sessionId}_${startedAt}_${votingStatus}';
  }

  bool _isInHandoverBuffer(String key) {
    final triggeredAt = _handoverTriggeredAt[key];
    if (triggeredAt == null) return false;
    const buffer = Duration(seconds: 2);
    return DateTime.now().difference(triggeredAt) <= buffer;
  }

  void _pruneForcedOverlaySessionKeys(List<EngagementItem> items) {
    final validKeys = <String>{};
    for (final item in items) {
      if (item.type != EngagementType.poll) continue;
      final schedule = item.pollVotingSchedule;
      final seconds = schedule != null && schedule['seconds_until_close'] is int
          ? (schedule['seconds_until_close'] as int)
          : (schedule != null && schedule['seconds_until_close'] is num
              ? (schedule['seconds_until_close'] as num).toInt()
              : 0);
      if (seconds > 0 && seconds <= 10) {
        validKeys.add(_pollSessionKey(item));
      }
    }
    _forcedOverlaySessionKeys.removeWhere((key) => !validKeys.contains(key));
    _handoverTriggeredAt.removeWhere((key, _) => !validKeys.contains(key));
  }

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageChanged);
    // Delay loading to ensure auth is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEngagementFeed();
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentPage) {
      setState(() {
        _currentPage = page;
      });
    }
  }

  Future<void> _loadEngagementFeed() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);

    // Wait a bit for auth to be ready
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final token = await authProvider.token;
    if (authProvider.user == null || token == null) {
      app_logger.Logger.warning(
          'User not authenticated, skipping engagement feed',
          tag: 'EngagementCarousel');
      _lastUserId = null;
      return;
    }

    final currentUserId = authProvider.user!.id;

    // PROFESSIONAL FIX: Check if user changed - if so, reload
    // This ensures Engagement HUB shows for new user even if widget was already built
    final userChanged = _lastUserId != null && _lastUserId != currentUserId;
    _lastUserId = currentUserId;
    if (userChanged) {
      _forcedOverlaySessionKeys.clear();
      _handoverTriggeredAt.clear();
    }

    app_logger.Logger.info(
        'Loading engagement feed for user: $currentUserId (userChanged: $userChanged)',
        tag: 'EngagementCarousel');

    try {
      // Force refresh if user changed, otherwise use normal refresh
      await engagementProvider.loadFeed(
        userId: currentUserId,
        token: token,
        forceRefresh: userChanged, // Force refresh if user changed
      );

      // Log the result
      if (!mounted) return;

      if (engagementProvider.hasItems) {
        _pruneForcedOverlaySessionKeys(engagementProvider.items);
        app_logger.Logger.info(
            'Engagement feed loaded: ${engagementProvider.items.length} items',
            tag: 'EngagementCarousel');

        // PROFESSIONAL FIX: Scroll to specific item if initialItemId is provided
        if (widget.initialItemId != null) {
          _scrollToItem(widget.initialItemId!);
        }

        // Start auto-scroll if items are loaded
        if (mounted) {
          _startAutoScroll();
        }
      } else {
        _forcedOverlaySessionKeys.clear();
        _handoverTriggeredAt.clear();
        app_logger.Logger.warning(
            'Engagement feed is empty. Error: ${engagementProvider.error}',
            tag: 'EngagementCarousel');
      }
    } catch (e) {
      app_logger.Logger.error('Error loading engagement feed: $e',
          tag: 'EngagementCarousel', error: e);
    }
  }

  /// PROFESSIONAL FIX: Scroll to specific engagement item by ID
  /// Used for deep linking from notifications
  void _scrollToItem(int itemId) {
    if (!mounted) return;

    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    if (!engagementProvider.hasItems) {
      app_logger.Logger.warning(
          'Cannot scroll to item $itemId: no items loaded',
          tag: 'EngagementCarousel');
      return;
    }

    // Find the index of the item with matching ID
    final itemIndex = engagementProvider.items.indexWhere(
      (item) => item.id == itemId,
    );

    if (itemIndex == -1) {
      app_logger.Logger.warning('Item $itemId not found in engagement feed',
          tag: 'EngagementCarousel');
      return;
    }

    app_logger.Logger.info(
        'Scrolling to engagement item $itemId at index $itemIndex',
        tag: 'EngagementCarousel');

    // Wait for page controller to be ready, then scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          itemIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else {
        // If controller not ready, wait a bit more
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _pageController.hasClients) {
            _pageController.animateToPage(
              itemIndex,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();

    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    if (!engagementProvider.hasItems) {
      return;
    }

    // Get rotation duration from current item (backend-managed)
    // Backend always provides rotation_duration (either from item or global setting)
    final currentItem = engagementProvider.items.isNotEmpty
        ? engagementProvider
            .items[_currentPage % engagementProvider.items.length]
        : null;

    // Use rotation_duration from backend (always provided by backend now)
    // Backend sends global setting if item doesn't have individual setting
    final rotationSeconds = currentItem?.rotationDurationSeconds;
    _lastRotationSeconds = rotationSeconds;

    // OFF state: rotationSeconds <= 0 or null means no auto-scroll.
    if (rotationSeconds == null || rotationSeconds <= 0) {
      app_logger.Logger.info(
        'Auto-scroll disabled for current item (rotation_duration = ${rotationSeconds ?? "null"})',
        tag: 'EngagementCarousel',
      );
      return;
    }

    // Validate rotation duration (must be between 1-60 seconds)
    final validRotationSeconds = rotationSeconds.clamp(1, 60);

    app_logger.Logger.info(
        'Starting auto-scroll with rotation duration: ${validRotationSeconds}s (from backend: ${currentItem?.rotationDurationSeconds ?? "default"})',
        tag: 'EngagementCarousel');

    _autoScrollTimer = Timer.periodic(
      Duration(seconds: validRotationSeconds),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final engagementProvider =
            Provider.of<EngagementProvider>(context, listen: false);
        if (!engagementProvider.hasItems) {
          timer.cancel();
          return;
        }

        final nextPage = (_currentPage + 1) % engagementProvider.items.length;

        // Get rotation duration for next page item
        final nextItem = engagementProvider.items[nextPage];
        final nextRotationSeconds = nextItem.rotationDurationSeconds;

        // OFF for next item: stop auto-scroll and just animate once into that item.
        if (nextRotationSeconds == null || nextRotationSeconds <= 0) {
          timer.cancel();
          _currentPage = nextPage;
          _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
          app_logger.Logger.info(
            'Auto-scroll stopped on next item (rotation_duration = ${nextRotationSeconds ?? "null"})',
            tag: 'EngagementCarousel',
          );
          return;
        }

        final validNextRotationSeconds = nextRotationSeconds.clamp(1, 60);

        // If next item has different rotation duration, restart timer with new duration
        if (validNextRotationSeconds != validRotationSeconds) {
          timer.cancel();
          _currentPage = nextPage;
          _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
          // Restart timer with new duration
          _startAutoScroll();
          return;
        }

        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  bool _isPollResultEligibleForWinnerCheck(EngagementItem item) {
    if (item.type != EngagementType.poll || !item.hasInteracted) return false;
    final schedule = item.pollVotingSchedule;
    final status = (schedule?['voting_status']?.toString() ?? '').toLowerCase();
    final result = item.pollResult;
    if (result == null) return false;
    final hasWinning = result['winning_option'] != null ||
        (result['winning_index'] != null && result['winning_index'] >= 0) ||
        ((result['options'] as List?)?.isNotEmpty ?? false);
    final isResultLikeStatus = status == 'showing_result' ||
        status == 'showing_results' ||
        status == 'ended' ||
        status == 'result' ||
        status == 'results';
    return isResultLikeStatus && (((result['total_votes'] ?? 0) > 0) || hasWinning);
  }

  String _winnerScanSignature(List<EngagementItem> items) {
    final parts = <String>[];
    for (final item in items) {
      if (!_isPollResultEligibleForWinnerCheck(item)) continue;
      final r = item.pollResult;
      final sch = item.pollVotingSchedule;
      parts.add(
        '${item.id}:${item.hasInteracted ? 1 : 0}:'
        '${sch?['voting_status'] ?? ''}:'
        '${r?['winning_index'] ?? ''}:${r?['total_votes'] ?? ''}:'
        '${r?['vote_counts'] ?? ''}:${sch?['result_display_ends_at'] ?? ''}',
      );
    }
    return parts.join('|');
  }

  /// Non-blocking: each poll sync runs independently so My PNP is not serialized
  /// behind slow `/poll/state` + `/poll/results` chains.
  void _triggerWinnerChecksForVisibleFeedPolls(List<EngagementItem> items) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user?.id ?? 0;
    if (uid <= 0) return;
    for (final item in items) {
      if (!mounted) return;
      if (!_isPollResultEligibleForWinnerCheck(item)) continue;
      final schedule = item.pollVotingSchedule;
      final feedSessionId = schedule?['current_session_id']?.toString();
      unawaited(
        PollWinnerPopupService.checkAndShowPollWinnerPopup(
          context: context,
          pollId: item.id,
          userId: uid,
          itemTitle: item.title.isNotEmpty ? item.title : null,
          feedSessionId: feedSessionId,
          feedPollResult: item.pollResult,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // PROFESSIONAL FIX: Also listen to auth changes to reload when user changes
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        // Check if user changed and reload if needed
        final currentUserId = authProvider.user?.id;
        if (currentUserId != null && currentUserId != _lastUserId) {
          // User changed - reload feed
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadEngagementFeed();
            }
          });
        }

        return Consumer<EngagementProvider>(
          builder: (context, engagementProvider, child) {
            // Show loading state
            if (engagementProvider.isLoading) {
              return _buildLoadingState();
            }

            // If there's an error but we have cached items, still show them
            if (engagementProvider.error != null &&
                !engagementProvider.hasItems) {
              app_logger.Logger.error(
                  'Engagement feed error: ${engagementProvider.error}',
                  tag: 'EngagementCarousel');
              // Show error state instead of hiding completely
              return _buildErrorState(engagementProvider.error!);
            }

            // If no items, show empty state
            if (!engagementProvider.hasItems) {
              app_logger.Logger.info(
                  'No engagement items available. Error: ${engagementProvider.error}',
                  tag: 'EngagementCarousel');
              return const SizedBox.shrink();
            }

            // Silent poll-win balance sync for every eligible result card (no popup UI).
            final winnerSig = _winnerScanSignature(engagementProvider.items);
            if (winnerSig.isNotEmpty && winnerSig != _lastWinnerScanSignature) {
              _lastWinnerScanSignature = winnerSig;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _triggerWinnerChecksForVisibleFeedPolls(
                    engagementProvider.items);
              });
            } else if (winnerSig.isEmpty) {
              _lastWinnerScanSignature = '';
            }

            // If rotationDurationSeconds changed for current item (e.g. Global Rotation Settings updated),
            // restart auto-scroll with new value so changes apply instantly.
            final currentItem = engagementProvider.items[
                _currentPage % engagementProvider.items.length];
            final currentRotation = currentItem.rotationDurationSeconds;
            if (currentRotation != _lastRotationSeconds) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _startAutoScroll();
                }
              });
            }

            // Show engagement items - wrapped in container to match button width exactly
            // Buttons structure: parent padding (16) + container padding (4) + button padding (20) = 40 per side
            // Engagement structure: parent padding (16) + container padding (4) + card margin (0) + card padding (20) = 40 per side
            // This ensures perfect width alignment with action buttons above
            // PROFESSIONAL FIX: Use taller aspect ratio (height = width * 1.15 for larger display while keeping pagination visible)
            return LayoutBuilder(
              builder: (context, constraints) {
                // Calculate available width: screen width - parent padding (16*2) - container padding (4*2) = width - 40
                final availableWidth = constraints.maxWidth - 40;
                // Set height larger than width (1.15x) for bigger display while ensuring pagination is visible
                final cardHeight = availableWidth * 1.15;

                return Container(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  width: double.infinity,
                  child: Column(
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: engagementProvider.items.length,
                          itemBuilder: (context, index) {
                            final item = engagementProvider.items[index];
                            return _buildEngagementCard(item, index);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPageIndicator(engagementProvider.items.length),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available width: screen width - parent padding (16*2) - container padding (4*2) = width - 40
        final availableWidth = constraints.maxWidth - 40;
        // Set height larger than width (1.15x) for bigger display while ensuring pagination is visible
        final cardHeight = availableWidth * 1.15;

        return Container(
          height: cardHeight,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Loading engagement...',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(String error) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available width: screen width - parent padding (16*2) - container padding (4*2) = width - 40
        final availableWidth = constraints.maxWidth - 40;
        // Set height larger than width (1.15x) for bigger display while ensuring pagination is visible
        final cardHeight = availableWidth * 1.15;

        return Container(
          height: cardHeight,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange[700],
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // Old Code: 'Unable to load engagement',
                    // New Code:
                    (error.trim().isNotEmpty)
                        ? error
                        : 'Network အခက်အခဲရှိနေပါသည်',
                    style: TextStyle(
                      color: Colors.orange[900],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEngagementCard(EngagementItem item, int index) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double value = 1.0;
        if (_pageController.position.haveDimensions) {
          value = _pageController.page! - index;
          value = (1 - (value.abs() * 0.15)).clamp(0.85, 1.0);
        }

        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCardContent(item),
              _buildInteractionCountBadge(item),
            ],
          ),
        ),
      ),
    );
  }

  /// Interaction count badge shown in top-right corner of each card
  Widget _buildInteractionCountBadge(EngagementItem item) {
    if (item.interactionCount <= 0) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              item.interactionCount >= 1000
                  ? '${(item.interactionCount / 1000).toStringAsFixed(1)}k'
                  : item.interactionCount.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContent(EngagementItem item) {
    switch (item.type) {
      case EngagementType.banner:
        return _buildBannerCard(item);
      case EngagementType.quiz:
        return _buildQuizCard(item);
      case EngagementType.poll:
        return _buildPollCard(item);
      case EngagementType.announcement:
        return _buildAnnouncementCard(item);
      case EngagementType.number:
        return _buildNumberCard(item);
    }
  }

  /// Professional Banner Card with Tap-to-Quick-View
  /// Entire card is tappable to show full content in Quick View dialog
  Widget _buildBannerCard(EngagementItem item) {
    return GestureDetector(
      onTap: () => _showContentQuickView(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Media (Image/GIF/Video)
          if (item.mediaUrl != null && item.mediaUrl!.isNotEmpty)
            _EngagementMediaWidget(
              mediaUrl: item.mediaUrl!,
              fit: BoxFit.cover,
              autoplay: false,
              showControls: false,
              placeholder: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                ),
                child: const Icon(Icons.image_not_supported,
                    color: Colors.white, size: 50),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
              ),
            ),
          // Overlay Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
          // Content
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.title.isNotEmpty)
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (item.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _stripHtmlTags(item.content),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Tap hint
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app,
                      color: Colors.white.withOpacity(0.7),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to view full content',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizCard(EngagementItem item) {
    final hasInteracted = item.hasInteracted;
    final hasImage = item.mediaUrl != null && item.mediaUrl!.isNotEmpty;

    // If quiz has an image, show it with tap functionality
    if (hasImage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Background Media (Image/GIF/Video) - Make it tappable for Quick View
          GestureDetector(
            onTap: () =>
                _showImageQuickView(context, item.mediaUrl!, item.title),
            child: _EngagementMediaWidget(
              mediaUrl: item.mediaUrl!,
              fit: BoxFit.cover,
              autoplay: false,
              showControls: false,
              placeholder: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasInteracted
                        ? [Colors.green[400]!, Colors.green[600]!]
                        : [Colors.purple[400]!, Colors.deepPurple[600]!],
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasInteracted
                        ? [Colors.green[400]!, Colors.green[600]!]
                        : [Colors.purple[400]!, Colors.deepPurple[600]!],
                  ),
                ),
                child: const Icon(Icons.image_not_supported,
                    color: Colors.white, size: 50),
              ),
            ),
          ),
          // Overlay with content
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        hasInteracted ? Icons.check_circle : Icons.quiz,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.title.isNotEmpty ? item.title : 'Quiz',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.rewardPoints > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '+${item.rewardPoints} PTS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Question or Content - Use Flexible to prevent overflow
                  Flexible(
                    child: (item.quizData != null &&
                            item.quizData!.question.isNotEmpty)
                        ? Text(
                            item.quizData!.question,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : (item.content.isNotEmpty)
                            ? Text(
                                _stripHtmlTags(item.content),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  // Action Button
                  if (hasInteracted)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Already answered',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => _showQuizDialog(item),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'Answer Now',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // No image - show gradient background
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasInteracted
              ? [Colors.green[400]!, Colors.green[600]!]
              : [Colors.purple[400]!, Colors.deepPurple[600]!],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  hasInteracted ? Icons.check_circle : Icons.quiz,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title.isNotEmpty ? item.title : 'Quiz',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.rewardPoints > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+${item.rewardPoints} PTS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Question
            if (item.quizData != null && item.quizData!.question.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        item.quizData!.question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasInteracted)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.done_all, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Already answered',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    else
                      ElevatedButton(
                        onPressed: () => _showQuizDialog(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'Answer Now',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              )
            else if (item.content.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        _stripHtmlTags(item.content),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Only show "View Details" button for quiz type
                    if (!hasInteracted && item.type == EngagementType.quiz)
                      ElevatedButton(
                        onPressed: () => _showQuizDialog(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'View Details',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Professional Poll Card Design
  /// Distinct from Quiz: Uses orange/amber color scheme, voting terminology, and poll-specific UI
  /// All poll modes (AUTO_RUN, Manual, Scheduled): use feed-based design
  Widget _buildPollCard(EngagementItem item) {
    final schedule = item.pollVotingSchedule;
    final votingStatusRaw = schedule?['voting_status']?.toString() ?? 'open';
    final votingStatus = votingStatusRaw.toLowerCase();
    final secondsUntilClose = schedule != null && schedule['seconds_until_close'] is int
        ? (schedule['seconds_until_close'] as int)
        : (schedule != null && schedule['seconds_until_close'] is num
            ? (schedule['seconds_until_close'] as num).toInt()
            : 0);
    final r = item.pollResult;
    final hasWinning = r != null &&
        (r['winning_option'] != null ||
            (r['winning_index'] != null && r['winning_index'] >= 0) ||
            ((r['options'] as List?)?.isNotEmpty ?? false));
    final isResultLikeStatus = votingStatus == 'showing_result' ||
        votingStatus == 'showing_results' ||
        votingStatus == 'ended' ||
        votingStatus == 'result' ||
        votingStatus == 'results';
    final showResult = isResultLikeStatus &&
        r != null &&
        ((r['total_votes'] ?? 0) > 0 || hasWinning);

    if (showResult) {
      /*
      Old Code:
      return _PollResultWinnerPopupHost(item: item);
      */
      // New Code:
      // Smooth/stable transition between voting and result states.
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: ValueKey<String>(
            'poll_result_${item.id}_${schedule == null ? '' : schedule['current_session_id'] ?? ''}_${r['winning_index'] ?? ''}',
          ),
          child: _PollResultWinnerPopupHost(item: item),
        ),
      );
    }

    final hasInteracted = item.hasInteracted;
    final hasImage = item.mediaUrl != null && item.mediaUrl!.isNotEmpty;
    final bool isPollActive = item.quizData?.isActive ?? true;
    final sessionKey = _pollSessionKey(item);
    if (secondsUntilClose > 11 && !_isInHandoverBuffer(sessionKey)) {
      _forcedOverlaySessionKeys.remove(sessionKey);
      _handoverTriggeredAt.remove(sessionKey);
    }
    final isForcedOverlay = _forcedOverlaySessionKeys.contains(sessionKey);
    final showOverlay =
        isForcedOverlay || (secondsUntilClose >= 1 && secondsUntilClose <= 10);
    final showPermanentTimer = !showOverlay && secondsUntilClose > 10;

    Widget cardContent;

    // If poll has an image, show it with tap functionality
    if (hasImage) {
      cardContent = Stack(
        fit: StackFit.expand,
        children: [
          // Background Media (Image/GIF/Video) - Make it tappable for Quick View
          GestureDetector(
            onTap: () =>
                _showImageQuickView(context, item.mediaUrl!, item.title),
            child: _EngagementMediaWidget(
              mediaUrl: item.mediaUrl!,
              fit: BoxFit.cover,
              autoplay: false,
              showControls: false,
              placeholder: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasInteracted
                        ? [Colors.teal[400]!, Colors.teal[600]!]
                        : [Colors.orange[400]!, Colors.deepOrange[600]!],
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasInteracted
                        ? [Colors.teal[400]!, Colors.teal[600]!]
                        : [Colors.orange[400]!, Colors.deepOrange[600]!],
                  ),
                ),
                child: const Icon(Icons.image_not_supported,
                    color: Colors.white, size: 50),
              ),
            ),
          ),
          // Overlay with content
          // PROFESSIONAL FIX: Use Positioned to ensure content is always visible
          // This prevents clipping of "Your Choice" section
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
              child: Padding(
                // PROFESSIONAL FIX: Increase bottom padding when user has interacted
                // This ensures "Your Choice" section has enough space and is not clipped
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  hasInteracted
                      ? 24
                      : 20, // Extra bottom padding for "Your Choice" section
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize:
                      MainAxisSize.min, // CRITICAL: Use min to prevent clipping
                  children: [
                    // Header with Poll Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            item.title.isNotEmpty ? item.title : 'Poll',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (item.rewardPoints > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '+${item.rewardPoints} PTS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Question or Content
                    // PROFESSIONAL FIX: Reduce spacing and lines when hasInteracted to make room for "Your Choice"
                    if (item.quizData != null &&
                        item.quizData!.question.isNotEmpty)
                      Text(
                        item.quizData!.question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        maxLines: hasInteracted
                            ? 1
                            : 2, // Reduce lines when has "Your Choice"
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      )
                    else if (item.content.isNotEmpty)
                      Text(
                        _stripHtmlTags(item.content),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        maxLines: hasInteracted
                            ? 1
                            : 2, // Reduce lines when has "Your Choice"
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    // PROFESSIONAL FIX: Reduce spacing when hasInteracted to make room for "Your Choice"
                    SizedBox(height: hasInteracted ? 8 : 12),
                    // Action Button - Poll specific
                    // CREATIVE DESIGN: Beautiful animated celebration design for voted polls
                    if (hasInteracted) ...[
                      // PROFESSIONAL FIX: Use IntrinsicHeight to ensure proper space allocation
                      // This ensures "Your Choice" section is always visible and not clipped
                      IntrinsicHeight(
                        child: _VoteSubmittedCelebration(
                          key: ValueKey('vote_submitted_${item.id}'),
                          detailedBets: pollUserDetailedBets(
                            item,
                            engagementProvider:
                                Provider.of<EngagementProvider>(context, listen: false),
                          ),
                        ),
                      ),
                    ] else
                      ElevatedButton(
                        onPressed:
                            isPollActive ? () => _showPollDialog(item) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          // PROFESSIONAL FIX: Make "Poll Closed" text clearly visible with white/light gray
                          // Use white color for disabled state to ensure visibility against dark background
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: BorderSide(
                              // PROFESSIONAL FIX: Keep white border when disabled for better visibility
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          isPollActive ? 'ကစားမည်' : 'ပိတ်ထားသည်',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
    // No image - show gradient background with poll-specific colors
    cardContent = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasInteracted
              ? [Colors.teal[400]!, Colors.teal[600]!]
              : [Colors.orange[400]!, Colors.deepOrange[600]!],
        ),
      ),
      child: Padding(
        // PROFESSIONAL FIX: Increase bottom padding when user has interacted
        // This ensures "Your Choice" section has enough space and is not clipped
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          hasInteracted
              ? 24
              : 20, // Extra bottom padding for "Your Choice" section
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Poll Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    item.title.isNotEmpty ? item.title : 'Poll',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (item.rewardPoints > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+${item.rewardPoints} PTS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Question or Content
            // PROFESSIONAL FIX: Optimized layout to prevent overflow - uses Flexible spacing and proper constraints
            if (item.quizData != null && item.quizData!.question.isNotEmpty)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // PROFESSIONAL FIX: Use SingleChildScrollView for constrained spaces to prevent overflow
                    return SingleChildScrollView(
                      physics:
                          const NeverScrollableScrollPhysics(), // Disable scrolling, just prevent overflow
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Question text - flexible sizing
                            Flexible(
                              child: Text(
                                item.quizData!.question,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            // PROFESSIONAL FIX: Use Flexible instead of Spacer to prevent overflow
                            // Only add spacing if there's enough space
                            if (constraints.maxHeight > 100)
                              const SizedBox(height: 8)
                            else
                              const SizedBox(height: 4),
                            // Action Button - Poll specific
                            // CREATIVE DESIGN: Beautiful animated celebration design for voted polls
                            if (hasInteracted) ...[
                              // PROFESSIONAL FIX: Wrap in Container with minimum height to ensure visibility
                              Container(
                                constraints: BoxConstraints(
                                  minHeight:
                                      100, // Ensure space for both badge and "Your Choice"
                                  maxHeight: constraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: _VoteSubmittedCelebration(
                                    key: ValueKey('vote_submitted_${item.id}'),
                                    detailedBets: pollUserDetailedBets(
                                      item,
                                      engagementProvider: Provider.of<EngagementProvider>(
                                          context,
                                          listen: false),
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              ElevatedButton(
                                onPressed: () => _showPollDialog(item),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.deepOrange,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                child: const Text(
                                  'ကစားမည်',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (item.content.isNotEmpty)
              // PROFESSIONAL FIX: Optimized layout to prevent overflow - same fix as quizData section
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _stripHtmlTags(item.content),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            // PROFESSIONAL FIX: Use adaptive spacing instead of Spacer
                            if (constraints.maxHeight > 100)
                              const SizedBox(height: 8)
                            else
                              const SizedBox(height: 4),
                            // Action Button - Poll specific
                            // CREATIVE DESIGN: Beautiful animated celebration design for voted polls
                            if (hasInteracted) ...[
                              // PROFESSIONAL FIX: Use IntrinsicHeight to ensure proper space allocation
                              IntrinsicHeight(
                                child: _VoteSubmittedCelebration(
                                  key: ValueKey('vote_submitted_${item.id}'),
                                  detailedBets: pollUserDetailedBets(
                                    item,
                                    engagementProvider:
                                        Provider.of<EngagementProvider>(context, listen: false),
                                  ),
                                ),
                              ),
                            ] else
                              ElevatedButton(
                                onPressed: isPollActive
                                    ? () => _showPollDialog(item)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.deepOrange,
                                  // PROFESSIONAL FIX: Make "Poll Closed" text clearly visible with light gray
                                  // Use light gray color for disabled state to ensure visibility against grey background
                                  disabledForegroundColor: Colors.grey[600]!,
                                  disabledBackgroundColor: Colors.grey[200]!,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                child: Text(
                                  isPollActive ? 'ကစားမည်' : 'ပိတ်ထားသည်',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey<String>(
          'poll_vote_${item.id}_${votingStatus}_${item.hasInteracted ? 1 : 0}',
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            cardContent,
            Positioned(
              top: 10,
              left: 10,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0, -0.08),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: showPermanentTimer
                    ? IgnorePointer(
                        key: ValueKey<String>('badge_$sessionKey'),
                        child: _PermanentPollTimer(
                          key: ValueKey<String>(
                            'timer_${item.id}_${votingStatus}_$sessionKey',
                          ),
                          initialSeconds: secondsUntilClose,
                          onReachedHandover: () {
                            if (!mounted) return;
                            if (_forcedOverlaySessionKeys.contains(sessionKey)) {
                              return;
                            }
                            setState(() {
                              _forcedOverlaySessionKeys.add(sessionKey);
                              _handoverTriggeredAt[sessionKey] = DateTime.now();
                            });
                          },
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('poll_timer_none'),
                      ),
              ),
            ),
            if (showOverlay)
              _PollCountdownOverlay(
                key: ValueKey<String>('overlay_$sessionKey'),
                initialSeconds: secondsUntilClose,
              ),
          ],
        ),
      ),
    );
  }

  /// Professional Announcement Card with Tap-to-Quick-View
  /// Entire card is tappable to show full content in Quick View dialog
  Widget _buildAnnouncementCard(EngagementItem item) {
    final hasImage = item.mediaUrl != null && item.mediaUrl!.isNotEmpty;

    return GestureDetector(
      onTap: () => _showContentQuickView(context, item),
      child: hasImage
          ? Stack(
              fit: StackFit.expand,
              children: [
                // Background Media (Image/GIF/Video)
                _EngagementMediaWidget(
                  mediaUrl: item.mediaUrl!,
                  fit: BoxFit.cover,
                  autoplay: false,
                  showControls: false,
                  placeholder: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue[400]!, Colors.cyan[600]!],
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue[400]!, Colors.cyan[600]!],
                      ),
                    ),
                    child: const Icon(Icons.image_not_supported,
                        color: Colors.white, size: 50),
                  ),
                ),
                // Overlay with content
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(Icons.campaign,
                                color: Colors.white, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title.isNotEmpty
                                    ? item.title
                                    : 'Announcement',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              item.content.isNotEmpty
                                  ? _stripHtmlTags(item.content)
                                  : 'No content available',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.4,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Tap hint
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app,
                              color: Colors.white.withOpacity(0.7),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view full content',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    offset: const Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue[400]!, Colors.cyan[600]!],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.campaign,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title.isNotEmpty ? item.title : 'Announcement',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          item.content.isNotEmpty
                              ? _stripHtmlTags(item.content)
                              : 'No content available',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Tap hint
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.touch_app,
                          color: Colors.white.withOpacity(0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tap to view full content',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Professional Number Card with Creative Design and Blinking Animation
  /// Displays numeric content prominently with eye-catching visual effects
  Widget _buildNumberCard(EngagementItem item) {
    // Extract numeric value from content
    // Remove # symbol if present before parsing
    final content = item.content.trim().replaceAll('#', '').trim();
    final numericValue = int.tryParse(content) ?? 0;
    final displayText = numericValue > 0 ? numericValue.toString() : content;

    return LayoutBuilder(
      builder: (context, constraints) {
        // PROFESSIONAL FIX: Calculate responsive font size with proper constraint handling
        // Engagement card has taller aspect ratio (height = width * 1.15), so we need to work within that
        final screenWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 300.0; // Fallback width
        final screenHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screenWidth *
                1.15; // Engagement card has taller aspect ratio (height = width * 1.15)

        // Account for padding and other elements
        final availableWidth = screenWidth - 32; // 16px padding on each side
        final availableHeight =
            screenHeight - 80; // Account for title, badge, padding

        // PROFESSIONAL FIX: Make number MUCH LARGER - use 95% of available space
        // This ensures the number is as big as possible while still fitting
        final widthBasedSize = (availableWidth * 0.95).clamp(150.0, 400.0);
        final heightBasedSize = (availableHeight * 0.95).clamp(150.0, 300.0);

        // Use the smaller of the two to ensure it fits perfectly
        // But prioritize making it as large as possible
        final calculatedSize = (widthBasedSize < heightBasedSize
                ? widthBasedSize
                : heightBasedSize)
            .clamp(180.0, 350.0); // Increased range for much larger numbers

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo[600]!,
                Colors.purple[600]!,
                Colors.deepPurple[700]!,
              ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // PROFESSIONAL FIX: Removed _AnimatedNumberBackground to eliminate diagonal lines
              // Background pattern was creating decorative lines that interfered with number display
              // Clean background without any pattern lines

              // Main content with proper constraints to prevent overflow
              // PROFESSIONAL FIX: Minimize padding to maximize number size
              // Engagement card has taller aspect ratio (height = width * 1.15), so we must fit within that
              Padding(
                padding:
                    const EdgeInsets.all(12), // Reduced padding for more space
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    // PROFESSIONAL FIX: Ensure constraints are bounded
                    // Use width as fallback since card has taller aspect ratio
                    final maxWidth = innerConstraints.maxWidth.isFinite
                        ? innerConstraints.maxWidth
                        : 300.0; // Fallback width
                    final maxHeight = innerConstraints.maxHeight.isFinite
                        ? innerConstraints.maxHeight
                        : maxWidth *
                            1.15; // Fallback to width * 1.15 (taller aspect ratio)

                    // PROFESSIONAL FIX: Minimize title/badge space to maximize number size
                    // Calculate available height (accounting for title and badge)
                    final titleHeight =
                        item.title.isNotEmpty ? 30.0 : 0.0; // Reduced
                    final badgeHeight =
                        item.rewardPoints > 0 ? 28.0 : 0.0; // Reduced
                    final spacing = (item.title.isNotEmpty ? 4.0 : 0.0) +
                        (item.rewardPoints > 0 ? 4.0 : 0.0); // Reduced spacing
                    final numberHeight =
                        (maxHeight - titleHeight - badgeHeight - spacing)
                            .clamp(100.0, maxHeight); // Increased minimum

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title (if provided) - Smaller to maximize number space
                        if (item.title.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12, // Smaller font
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        // Blinking Number Display - Use SizedBox with calculated height
                        // PROFESSIONAL FIX: Ensure height is bounded and fits within card
                        SizedBox(
                          height: numberHeight.isFinite ? numberHeight : 140.0,
                          width: double.infinity,
                          child: Center(
                            child: _BlinkingNumberWidget(
                              number: displayText,
                              size: calculatedSize,
                            ),
                          ),
                        ),

                        // Reward points badge (if applicable) - Smaller to maximize number space
                        if (item.rewardPoints > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4, // Reduced padding
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.stars,
                                    color: Colors.amber,
                                    size: 14, // Smaller icon
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '+${item.rewardPoints} PNP',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10, // Smaller font
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // Decorative corner elements
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.tag,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator(int count) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == index ? primaryColor : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  void _showQuizDialog(EngagementItem item) {
    if (item.quizData == null) return;

    // Prevent opening dialog if already answered
    if (item.hasInteracted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already answered this quiz.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuizDialog(item: item),
    );
  }

  /// Show Poll Dialog - Distinct from Quiz with voting terminology and orange theme
  /// Allow opening dialog even if already voted (view-only, one-time vote)
  void _showPollDialog(EngagementItem item) {
    if (item.quizData == null) return;

    // Allow opening dialog even if already voted (view-only, one-time vote)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PollDialog(item: item),
    );
  }

  /// Show Quick View dialog for engagement images
  /// Professional image viewer with zoom and pan capabilities
  void _showImageQuickView(
      BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _ImageQuickViewDialog(
        imageUrl: imageUrl,
        title: title,
      ),
    );
  }

  /// Show Content Quick View dialog for Banner and Announcement cards
  /// Professional content viewer with image (if available) and full text content
  /// Records interaction (view) so Dashboard interaction count increases
  void _showContentQuickView(BuildContext context, EngagementItem item) {
    _recordBannerOrAnnouncementView(context, item);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _ContentQuickViewDialog(item: item),
    );
  }

  /// Record banner/announcement view with backend so Dashboard interaction count increases
  void _recordBannerOrAnnouncementView(BuildContext context, EngagementItem item) {
    if (item.type != EngagementType.banner && item.type != EngagementType.announcement) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) return;
    final engagementProvider = Provider.of<EngagementProvider>(context, listen: false);
    final userId = authProvider.user!.id;
    final token = authProvider.token;
    engagementProvider.submitInteraction(
      userId: userId,
      token: token,
      itemId: item.id,
      answer: 'viewed',
    ).then((result) {
      if (result['success'] == true && mounted) {
        engagementProvider.refresh(userId: userId, token: token);
      }
    }).catchError((_) {});
  }

  String _stripHtmlTags(String html) {
    final RegExp exp =
        RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);
    return html.replaceAll(exp, '').trim();
  }
}

/// Always-visible compact timer badge for poll duration.
/// Separate from [_PollCountdownOverlay], which remains last-10-seconds only.
class _PermanentPollTimer extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback? onReachedHandover;

  const _PermanentPollTimer({
    super.key,
    required this.initialSeconds,
    this.onReachedHandover,
  });

  @override
  State<_PermanentPollTimer> createState() => _PermanentPollTimerState();
}

class _PermanentPollTimerState extends State<_PermanentPollTimer> {
  late int _secondsLeft;
  Timer? _timer;
  bool _didNotifyHandover = false;

  int _clampSeconds(int value) => value < 0 ? 0 : value;

  void _startOrRefreshTimer() {
    _timer?.cancel();
    _didNotifyHandover = false;
    if (_secondsLeft <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _secondsLeft = _clampSeconds(_secondsLeft - 1);
      });
      if (_secondsLeft <= 10) {
        if (!_didNotifyHandover) {
          _didNotifyHandover = true;
          widget.onReachedHandover?.call();
        }
        _timer?.cancel();
      }
    });
  }

  String _formatMmSs(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void initState() {
    super.initState();
    _secondsLeft = _clampSeconds(widget.initialSeconds);
    _startOrRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant _PermanentPollTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _clampSeconds(widget.initialSeconds);
    final prev = _clampSeconds(oldWidget.initialSeconds);
    if (next <= 10) {
      _secondsLeft = next;
      _timer?.cancel();
      return;
    }
    if (next != prev) {
      // Guard against delayed parent refresh spikes (e.g. 10 -> 100) within same session widget.
      final looksLikeSpike = next > _secondsLeft && _secondsLeft <= 12;
      if (looksLikeSpike) return;
      _secondsLeft = next;
      _startOrRefreshTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 10) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.28),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatMmSs(_secondsLeft),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Countdown overlay for Auto Run poll (last 10 seconds before close)
class _PollCountdownOverlay extends StatefulWidget {
  final int initialSeconds;

  const _PollCountdownOverlay({super.key, required this.initialSeconds});

  @override
  State<_PollCountdownOverlay> createState() => _PollCountdownOverlayState();
}

class _PollCountdownOverlayState extends State<_PollCountdownOverlay> {
  late int _secondsLeft;
  Timer? _timer;
  bool _hasTriggeredForceRefreshBurst = false;

  void _triggerForceRefreshBurstOnTimerEnd() {
    if (_hasTriggeredForceRefreshBurst || !mounted) return;
    _hasTriggeredForceRefreshBurst = true;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id;
    if (userId == null) return;
    final userIdStr = userId.toString();

    Future<void> runAttempt(String label) async {
      try {
        await PointProvider.instance.refreshPointState(
          userId: userIdStr,
          forceRefresh: true,
          refreshBalance: true,
          refreshTransactions: false,
          refreshUserCallback: authProvider.refreshUser,
        );
        app_logger.Logger.info(
          'Poll timer-end force refresh success ($label) for user=$userIdStr',
          tag: 'EngagementCarousel',
        );
      } catch (e, st) {
        app_logger.Logger.warning(
          'Poll timer-end force refresh failed ($label): $e',
          tag: 'EngagementCarousel',
          error: e,
          stackTrace: st,
        );
      }
    }

    // Fire immediately, then retry at +1s and +3s to absorb backend propagation lag.
    unawaited(runAttempt('immediate'));
    unawaited(
      Future<void>.delayed(const Duration(seconds: 1), () async {
        if (!mounted) return;
        await runAttempt('after_1s');
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        await runAttempt('after_3s');
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
        } else {
          _triggerForceRefreshBurstOnTimerEnd();
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: AbsorbPointer(
        absorbing: false,
        child: IgnorePointer(
          child: Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_secondsLeft',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Closing in...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Extracts text, media_url, and media_type from a poll option.
/// Supports: Map (extended format) or String (legacy).
({String text, String? mediaUrl, String? mediaType}) _parsePollOption(dynamic opt) {
  if (opt == null) return (text: 'Option', mediaUrl: null, mediaType: null);
  if (opt is Map) {
    final m = Map<String, dynamic>.from(opt);
    final textStr = (m['text'] ?? '').toString().trim();
    final mediaUrlStr = m['media_url']?.toString().trim();
    final mediaTypeStr = m['media_type']?.toString().trim();
    return (
      text: textStr.isNotEmpty ? textStr : 'Option',
      mediaUrl: (mediaUrlStr != null && mediaUrlStr.isNotEmpty)
          ? mediaUrlStr
          : null,
      mediaType: (mediaTypeStr != null && mediaTypeStr.isNotEmpty)
          ? mediaTypeStr
          : null,
    );
  }
  final s = opt.toString().trim();
  return (text: s.isNotEmpty ? s : 'Option', mediaUrl: null, mediaType: null);
}

/// When [winning_index] is missing (legacy feed bug), derive a display winner from
/// [vote_counts] so we do not always fall back to option 0.
int? _leadingPollOptionIndexFromVoteCounts(
    dynamic voteCountsRaw, int optionCount) {
  if (voteCountsRaw == null || optionCount <= 0) return null;
  if (voteCountsRaw is! Map) return null;
  var bestIdx = -1;
  var bestCount = -1;
  voteCountsRaw.forEach((key, value) {
    final idx = key is int
        ? key
        : int.tryParse(key.toString());
    if (idx == null || idx < 0 || idx >= optionCount) return;
    final c = value is int
        ? value
        : (value is num
            ? value.toInt()
            : int.tryParse(value.toString()) ?? 0);
    if (c > bestCount) {
      bestCount = c;
      bestIdx = idx;
    } else if (c == bestCount && c > 0) {
      // Deterministic tie-break: smallest index (stable across rebuilds).
      if (bestIdx < 0 || idx < bestIdx) {
        bestIdx = idx;
      }
    }
  });
  if (bestIdx >= 0 && bestCount > 0) return bestIdx;
  return null;
}

/// Stable "random-looking" option index when API has not yet sent [winning_index]
/// (e.g. race before DB write). Same inputs => same index across rebuilds — no [Random] flicker.
int _stableFallbackOptionIndex(EngagementItem item, int optionCount) {
  if (optionCount <= 0) return 0;
  final schedule = item.pollVotingSchedule;
  final endsAt = schedule?['result_display_ends_at']?.toString() ??
      schedule?['end_time']?.toString() ??
      '';
  final seed = '${item.id}_${item.title}_$endsAt';
  var h = 0x811c9dc5;
  for (final u in seed.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h % optionCount;
}

/// Library helpers for poll UI (used by [_EngagementCarouselState] and [_PollResultCard]).
int pollSelectedOptionCountFromUserAnswer(EngagementItem item) {
  final ua = item.userAnswer?.trim();
  if (ua == null || ua.isEmpty) return 0;
  final optLen = item.quizData?.options.length ?? 0;
  var c = 0;
  for (final part in ua.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final idx = int.tryParse(part);
    if (idx != null && idx >= 0 && idx < optLen) {
      c++;
    }
  }
  if (c == 0 && ua.isNotEmpty) return 1;
  return c;
}

/// Total **Amount** unit count for receipt fallback (sum of per-option multipliers; not PNP).
int? pollVoteTotalAmountUnits(EngagementItem item) {
  final n = pollSelectedOptionCountFromUserAnswer(item);
  if (n <= 0) return null;
  final allowUser = item.quizData?.allowUserAmount ?? true;
  if (!allowUser) {
    return n;
  }
  final bet = item.userBetAmount;
  if (bet != null && bet > 0) {
    return bet * n;
  }
  return n;
}

String? pollUserChoiceDisplayLabel(EngagementItem item) {
  if (item.userAnswer == null || item.userAnswer!.trim().isEmpty) {
    return null;
  }
  final options = item.quizData?.options;
  if (options == null || options.isEmpty) {
    return item.userAnswer!.trim();
  }
  final raw = item.userAnswer!.trim();
  final parts = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
  final texts = <String>[];
  for (final part in parts) {
    final idx = int.tryParse(part);
    if (idx != null && idx >= 0 && idx < options.length) {
      final text = options[idx].trim();
      if (text.isNotEmpty && !texts.contains(text)) {
        texts.add(text);
      }
    }
  }
  if (texts.isEmpty) {
    return raw;
  }
  return texts.join(', ');
}

// --- Poll per-option unit overlay (client persistence when API omits keys 3+, etc.) ---

/// Storage key: engagement item + stable option id string.
String pollUserLocalUnitStorageKey(int engagementItemId, String optionUniqueId) =>
    '$engagementItemId|$optionUniqueId';

/// Last-known units per option; synced from API when present, else from dialog edits.
/// Survives widget rebuilds before feed returns full [user_bet_amount_per_option].
// Old Code:
// final Map<String, int> _pollUserLocalUnitOverlay = <String, int>{};
//
// New Code:
// Moved to EngagementProvider for persistence across lifecycle/restart.

/// Writes the same field [pollUserSeparatedBetStates] reads for fallback.
void recordPollUserLocalUnitOverride(
  EngagementProvider engagementProvider,
  int engagementItemId,
  String optionUniqueId,
  int units,
) {
  if (units <= 0) return;
  unawaited(
    engagementProvider.setPollUserLocalUnitOverride(
      engagementItemId,
      optionUniqueId,
      units,
    ),
  );
}

/// Single key format for dialog state and receipt: `index::label` (index disambiguates).
String pollOptionUniqueId(List<dynamic> options, int idx) {
  if (idx < 0) {
    return 'i$idx';
  }
  if (idx >= options.length) {
    return 'i$idx|oob';
  }
  final label = options[idx].toString().trim();
  return '$idx::${label.isEmpty ? '?' : label}';
}

int _resolvePollOptionUnits({
  required EngagementProvider engagementProvider,
  required int itemId,
  required List<dynamic> options,
  required int idx,
  required int? fromApi,
  required int? declaredBet,
  required bool isSingleSelection,
  required bool allowUser,
}) {
  if (fromApi != null && fromApi > 0) return fromApi;
  if (!allowUser) {
    return 1;
  }
  final uid = pollOptionUniqueId(options, idx);
  // Old Code:
  // final fromLocal =
  //    _pollUserLocalUnitOverlay[pollUserLocalUnitStorageKey(itemId, uid)];
  //
  // New Code:
  final fromLocal = engagementProvider.getPollUserLocalUnitOverride(itemId, uid);
  if (fromLocal != null && fromLocal > 0) return fromLocal;
  if (isSingleSelection && declaredBet != null && declaredBet > 0) {
    return declaredBet;
  }
  return 1;
}

/// Builds two-lane poll states (display and calculated use the same resolved units;
/// no separate normalization—integer passthrough only).
({
  Map<String, int?>? displayBets,
  Map<String, int?>? calculatedTotals,
})? pollUserSeparatedBetStates(
  EngagementItem item, {
  required EngagementProvider engagementProvider,
}) {
  if (!item.hasInteracted) return null;
  final ua = item.userAnswer?.trim();
  if (ua == null || ua.isEmpty) return null;
  final q = item.quizData;
  final options = q?.options ?? [];
  if (options.isEmpty) return null;
  final allowUser = q?.allowUserAmount ?? true;
  final perMap = item.userBetUnitsPerOption;
  final int? declaredBet = item.userBetAmount;

  // Isolated per-option units from API (index -> units).
  final isolatedUnitsByOption = <int, int>{};
  if (perMap != null && perMap.isNotEmpty) {
    perMap.forEach((k, v) {
      if (k >= 0 && v > 0) {
        isolatedUnitsByOption[k] = v;
      }
    });
  }

  final validIndices = <int>[];
  for (final part
      in ua.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final i = int.tryParse(part);
    if (i != null && i >= 0 && i < options.length) {
      validIndices.add(i);
    }
  }
  final isSingleSelection = validIndices.length == 1;

  final selectedOptionDisplay = <String, int>{};
  final calculatedTotal = <String, int>{};
  void addLineForOption(String label, int units) {
    if (label.isEmpty || units <= 0) return;
    selectedOptionDisplay[label] = units;
    calculatedTotal[label] = units;
  }

  var parsedAnyIndex = false;
  for (final part
      in ua.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final idx = int.tryParse(part);
    if (idx == null || idx < 0 || idx >= options.length) continue;
    parsedAnyIndex = true;
    final rawLabel = options[idx].toString().trim();
    if (rawLabel.isEmpty) continue;

    final match = RegExp(r'-\s*([^+]+?)\s*\+').firstMatch(rawLabel);
    final cleanLabel =
        match != null && match.group(1) != null ? match.group(1)!.trim() : rawLabel;

    final fromApi = isolatedUnitsByOption[idx];
    final units = _resolvePollOptionUnits(
      engagementProvider: engagementProvider,
      itemId: item.id,
      options: options,
      idx: idx,
      fromApi: fromApi,
      declaredBet: declaredBet,
      isSingleSelection: isSingleSelection,
      allowUser: allowUser,
    );

    addLineForOption(cleanLabel, units);
  }

  if (selectedOptionDisplay.isNotEmpty) {
    return (
      displayBets: Map<String, int?>.from(selectedOptionDisplay),
      calculatedTotals: Map<String, int?>.from(calculatedTotal),
    );
  }

  if (!parsedAnyIndex) {
    final label = pollUserChoiceDisplayLabel(item)?.trim();
    final display = (label != null && label.isNotEmpty) ? label : ua;
    final total = pollVoteTotalAmountUnits(item);
    return (
      displayBets: {display: 1},
      calculatedTotals: {display: (total != null && total > 0) ? total : 1},
    );
  }

  return null;
}

/// UI-only map for "Your choice" receipt. Must never consume calc lane directly.
Map<String, int?>? pollUserDetailedBets(
  EngagementItem item, {
  required EngagementProvider engagementProvider,
}) {
  final separated = pollUserSeparatedBetStates(
    item,
    engagementProvider: engagementProvider,
  );
  return separated?.displayBets;
}

/// Calculation-only map for multiplier/reward debugging and backend math tracking.
Map<String, int?>? pollUserCalculatedTotals(
  EngagementItem item, {
  required EngagementProvider engagementProvider,
}) {
  final separated = pollUserSeparatedBetStates(
    item,
    engagementProvider: engagementProvider,
  );
  return separated?.calculatedTotals;
}

/// Compact inline receipt: `Option A : 2` (omits value if null).
List<InlineSpan> _pollReceiptInlineSpans(Map<String, int?> detailedBets) {
  const shadow = [
    Shadow(
      color: Color(0x73000000),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];
  final spans = <InlineSpan>[];
  var i = 0;
  for (final e in detailedBets.entries) {
    if (i > 0) {
      spans.add(TextSpan(
        text: ', ',
        style: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
          shadows: shadow,
        ),
      ));
    }
    spans.add(TextSpan(
      text: e.key,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
        shadows: shadow,
      ),
    ));
    if (e.value != null) {
      spans.add(TextSpan(
        text: ' : ${e.value}',
        style: TextStyle(
          color: Colors.amber.shade100,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
          shadows: shadow,
        ),
      ));
    }
    i++;
  }
  return spans;
}

Widget _pollDetailedReceiptSection(
  BuildContext context, {
  required Map<String, int?>? detailedBets,
  Map<String, int?>? calculatedBets,
  String heading = 'Your choice',
  bool wrapInGlass = false,
}) {
  if (detailedBets == null || detailedBets.isEmpty) {
    return const SizedBox.shrink();
  }

  final headingStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: Colors.white.withOpacity(0.9),
    shadows: const [
      Shadow(
        color: Color(0x73000000),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
  );

  final body = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 18,
            color: Colors.white.withOpacity(0.95),
          ),
          const SizedBox(width: 8),
          Text(heading, style: headingStyle),
        ],
      ),
      const SizedBox(height: 8),
      // Separation proof log right before UI render:
      // Display lane (receipt) vs Calculation lane (multiplier math).
      Builder(
        builder: (_) {
          print(
            '[PollReceiptSeparatedState] Display: ${detailedBets.toString()}, '
            'Total: ${calculatedBets?.toString() ?? 'n/a'}',
          );
          return const SizedBox.shrink();
        },
      ),
      RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, height: 1.35),
          children: _pollReceiptInlineSpans(detailedBets),
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  if (!wrapInGlass) {
    return body;
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.14),
              Colors.white.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.28),
            width: 1,
          ),
        ),
        child: body,
      ),
    ),
  );
}

/// In-place poll result in the carousel (chart/percentages live in [_PollResultCard]).
/// **Not** a dialog — winner celebration popups are suppressed elsewhere ([PointNotificationModal]).
/// Poll winner balance sync: [_triggerWinnerChecksForVisibleFeedPolls] (silent).
class _PollResultWinnerPopupHost extends StatelessWidget {
  final EngagementItem item;

  const _PollResultWinnerPopupHost({required this.item});

  @override
  Widget build(BuildContext context) {
    return _PollResultCard(item: item);
  }
}

/// Result display for Auto Run poll (shown for ~1 min after close).
/// Displays ONLY the winning option: image/media + text in a clean card.
class _PollResultCard extends StatelessWidget {
  final EngagementItem item;

  const _PollResultCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final result = item.pollResult;
    if (result == null) return const SizedBox.shrink();

    // Prefer winning_option (new API) or derive from options[winning_index]
    final winningOptionRaw = result['winning_option'];
    final options = List<dynamic>.from(result['options'] ?? []);
    final winningIndex = result['winning_index'] is int
        ? result['winning_index'] as int?
        : (result['winning_index'] is num)
            ? (result['winning_index'] as num).toInt()
            : null;

    // Never use Random() here — results must be stable across rebuilds.
    // Prefer explicit winning_option / winning_index from API; if missing, use vote leader
    // (do NOT default to options[0] — that incorrectly shows "option 1" every time).
    ({String text, String? mediaUrl, String? mediaType}) winning;
    if (winningOptionRaw != null && winningOptionRaw is Map) {
      winning = _parsePollOption(winningOptionRaw);
    } else if (winningIndex != null &&
        winningIndex >= 0 &&
        winningIndex < options.length) {
      winning = _parsePollOption(options[winningIndex]);
    } else {
      final lead = _leadingPollOptionIndexFromVoteCounts(
        result['vote_counts'],
        options.length,
      );
      if (lead != null && lead < options.length) {
        winning = _parsePollOption(options[lead]);
      } else if (options.isNotEmpty) {
        // Server should send winning_index after resolve; until then show a stable pick
        // from options (not "not resolved") — matches random-winner UX expectations.
        final idx = _stableFallbackOptionIndex(item, options.length);
        winning = _parsePollOption(options[idx]);
      } else {
        winning = (text: 'No result', mediaUrl: null, mediaType: null);
      }
    }

    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    final userDetailed = item.hasInteracted
        ? pollUserDetailedBets(
            item,
            engagementProvider: engagementProvider,
          )
        : null;
    final userCalculated = item.hasInteracted
        ? pollUserCalculatedTotals(
            item,
            engagementProvider: engagementProvider,
          )
        : null;

    return _CompactPollResultCard(
      text: winning.text,
      mediaUrl: winning.mediaUrl,
      userDetailedBets: userDetailed,
      userCalculatedTotals: userCalculated,
    );
  }
}

/// Result card matching Engagement Hub cards: fills the same card area, radius 20.
class _CompactPollResultCard extends StatelessWidget {
  final String text;
  final String? mediaUrl;
  /// Selected options with per-option Count; null hides receipt.
  final Map<String, int?>? userDetailedBets;
  /// Calculation-only values (multiplier lane). Not shown in UI text.
  final Map<String, int?>? userCalculatedTotals;

  const _CompactPollResultCard({
    required this.text,
    this.mediaUrl,
    this.userDetailedBets,
    this.userCalculatedTotals,
  });

  static const double _hubCardRadius = 20.0; // Match Engagement Hub card

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-card image / fallback background
        mediaUrl != null && mediaUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: mediaUrl!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported,
                      size: 40,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              )
            : Container(
                color: Colors.grey[200],
                child: Center(
                  child: Icon(
                    Icons.emoji_events,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                ),
              ),

        // Full-card overlay identical to active poll card style.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (userDetailedBets != null && userDetailedBets!.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.32),
                          width: 1,
                        ),
                      ),
                      child: _pollDetailedReceiptSection(
                        context,
                        detailedBets: userDetailedBets,
                        calculatedBets: userCalculatedTotals,
                        heading: 'Your choice',
                        wrapInGlass: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Determine media type from URL
/// Returns: 'image', 'gif', or 'video'
String getMediaType(String url) {
  final lowerUrl = url.toLowerCase();
  if (lowerUrl.endsWith('.gif') || lowerUrl.contains('.gif?')) {
    return 'gif';
  } else if (lowerUrl.endsWith('.mp4') ||
      lowerUrl.endsWith('.webm') ||
      lowerUrl.endsWith('.mov') ||
      lowerUrl.endsWith('.m4v') ||
      lowerUrl.contains('.mp4?') ||
      lowerUrl.contains('.webm?') ||
      lowerUrl.contains('.mov?') ||
      lowerUrl.contains('video') ||
      lowerUrl.contains('youtube.com') ||
      lowerUrl.contains('youtu.be') ||
      lowerUrl.contains('vimeo.com')) {
    return 'video';
  } else {
    return 'image';
  }
}

/// Professional Media Widget that handles Image, GIF, and Video
/// Supports autoplay for videos and proper caching for images/GIFs
class _EngagementMediaWidget extends StatefulWidget {
  final String mediaUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool autoplay;
  final bool showControls;

  const _EngagementMediaWidget({
    required this.mediaUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.autoplay = false,
    this.showControls = true,
  });

  @override
  State<_EngagementMediaWidget> createState() => _EngagementMediaWidgetState();
}

class _EngagementMediaWidgetState extends State<_EngagementMediaWidget> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;

  @override
  void initState() {
    super.initState();
    final mediaType = getMediaType(widget.mediaUrl);
    if (mediaType == 'video') {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl),
      );
      await _videoController!.initialize();

      // Add listener to track video playback state
      _videoController!.addListener(() {
        if (mounted) {
          final isPlaying = _videoController!.value.isPlaying;
          if (isPlaying != _isVideoPlaying) {
            setState(() {
              _isVideoPlaying = isPlaying;
            });
          }
        }
      });

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        if (widget.autoplay) {
          _videoController!.play();
          setState(() {
            _isVideoPlaying = true;
          });
        }
      }
    } catch (e) {
      app_logger.Logger.error(
        'Error initializing video: $e',
        tag: 'EngagementMediaWidget',
        error: e,
      );
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleVideoPlayback() {
    if (_videoController == null) return;
    if (_isVideoPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    setState(() {
      _isVideoPlaying = !_isVideoPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaType = getMediaType(widget.mediaUrl);

    switch (mediaType) {
      case 'video':
        if (!_isVideoInitialized) {
          return widget.placeholder ??
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: GestureDetector(
                  onTap: widget.showControls ? _toggleVideoPlayback : null,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
            if (widget.showControls)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleVideoPlayback,
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

      case 'gif':
        // GIFs are handled as images - CachedNetworkImage supports GIFs
        return CachedNetworkImage(
          imageUrl: widget.mediaUrl,
          fit: widget.fit,
          placeholder: (context, url) =>
              widget.placeholder ??
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          errorWidget: (context, url, error) =>
              widget.errorWidget ??
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white70,
                    size: 50,
                  ),
                ),
              ),
        );

      case 'image':
      default:
        return CachedNetworkImage(
          imageUrl: widget.mediaUrl,
          fit: widget.fit,
          placeholder: (context, url) =>
              widget.placeholder ??
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          errorWidget: (context, url, error) =>
              widget.errorWidget ??
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.white70,
                    size: 50,
                  ),
                ),
              ),
        );
    }
  }
}

/// Quiz Dialog Widget
class _QuizDialog extends StatefulWidget {
  final EngagementItem item;

  const _QuizDialog({required this.item});

  @override
  State<_QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends State<_QuizDialog> {
  int? _selectedOption;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    // Prevent dialog from opening if already answered
    if (widget.item.hasInteracted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already answered this quiz.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      });
      return const SizedBox.shrink();
    }

    final quizData = widget.item.quizData!;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.quiz, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Question
            Text(
              quizData.question,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            // Options
            ...List.generate(
              quizData.options.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: _isSubmitting
                      ? null
                      : () {
                          setState(() {
                            _selectedOption = index;
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _selectedOption == index
                          ? primaryColor.withOpacity(0.1)
                          : Colors.grey[100],
                      border: Border.all(
                        color: _selectedOption == index
                            ? primaryColor
                            : Colors.grey[300]!,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedOption == index
                                  ? primaryColor
                                  : Colors.grey[400]!,
                              width: 2,
                            ),
                            color: _selectedOption == index
                                ? primaryColor
                                : Colors.transparent,
                          ),
                          child: _selectedOption == index
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            quizData.options[index],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: _selectedOption == index
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedOption == null || _isSubmitting
                    ? null
                    : _submitAnswer,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Submit Answer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAnswer() async {
    if (_selectedOption == null) return;

    // PROFESSIONAL FIX: Prevent submission if already interacted
    // This provides immediate feedback before making API call
    if (widget.item.hasInteracted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already answered this quiz.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
    });

    // PROFESSIONAL FIX: Use try-finally to ensure _isSubmitting is ALWAYS reset
    // This prevents blocking subsequent quiz submissions and ensures proper cleanup
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final engagementProvider =
          Provider.of<EngagementProvider>(context, listen: false);
      final pointProvider = Provider.of<PointProvider>(context, listen: false);

      // PROFESSIONAL FIX: Ensure token is loaded before checking authentication
      // This handles cases where token might not be cached yet after user switch
      String? token = authProvider.token; // Try synchronous getter first
      if (token == null) {
        // If token is not cached, load it from storage
        app_logger.Logger.info('Token not cached, loading from storage...',
            tag: 'EngagementCarousel');
        token = await authProvider.getToken();
      }

      // Validate authentication state with proper error handling
      if (authProvider.user == null) {
        app_logger.Logger.warning('User is null, cannot submit quiz answer',
            tag: 'EngagementCarousel');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to submit your answer.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      if (token == null) {
        app_logger.Logger.warning(
            'Token is null after loading attempt, cannot submit quiz answer',
            tag: 'EngagementCarousel');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to submit your answer.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // PROFESSIONAL FIX: Validate user is still authenticated before submission
      // This prevents submission with stale user data after account switch
      final currentUserId = authProvider.user!.id;
      app_logger.Logger.info(
          'Submitting quiz answer: userId=$currentUserId, itemId=${widget.item.id}, answer=$_selectedOption',
          tag: 'EngagementCarousel');

      final result = await engagementProvider.submitInteraction(
        userId: currentUserId,
        token: token,
        itemId: widget.item.id,
        answer: _selectedOption.toString(),
      );

      if (!mounted) return;

      // PROFESSIONAL FIX: Reset submitting state BEFORE popping dialog
      // This ensures state is reset even if widget gets disposed after pop
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }

      // Pop dialog before showing result
      if (mounted) {
        Navigator.pop(context);
      }

      if (result['success'] == true) {
        // PROFESSIONAL FIX: Extract data from nested 'data' object or top-level
        final responseData = result['data'] as Map<String, dynamic>?;
        final isCorrect =
            responseData?['is_correct'] ?? result['is_correct'] ?? false;
        final pointsEarned = (responseData?['points_earned'] ??
            result['points_earned'] ??
            0) as int;
        final message = result['message']?.toString() ?? '';

        app_logger.Logger.info(
            'Quiz result - Correct: $isCorrect, Points: $pointsEarned, Message: $message',
            tag: 'EngagementCarousel');

        // Refresh points balance
        await pointProvider.loadBalance(
          authProvider.user!.id.toString(),
          forceRefresh: true,
        );

        // Refresh engagement feed to update hasInteracted status
        await engagementProvider.refresh(
          userId: authProvider.user!.id,
          token: token,
        );

        // Show result dialog
        if (mounted) {
          _showResultDialog(isCorrect, pointsEarned, message);
        }
      } else {
        // PROFESSIONAL FIX: Handle duplicate submission error gracefully
        final message =
            result['message']?.toString() ?? 'Failed to submit answer';
        final isDuplicate = result['is_duplicate'] == true;

        app_logger.Logger.warning(
            'Quiz submission failed: $message, isDuplicate: $isDuplicate',
            tag: 'EngagementCarousel');

        // If duplicate or user mismatch, refresh engagement feed to sync state
        if (isDuplicate ||
            message.toLowerCase().contains('user') ||
            message.toLowerCase().contains('account')) {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.user != null) {
            await engagementProvider.refresh(
              userId: authProvider.user!.id,
              token: authProvider.token,
            );
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: isDuplicate ? Colors.orange : Colors.red,
              duration: Duration(seconds: isDuplicate ? 3 : 2),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      // PROFESSIONAL FIX: Handle any exceptions gracefully
      app_logger.Logger.error('Exception during quiz submission: $e',
          tag: 'EngagementCarousel', error: e, stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'An error occurred while submitting your answer. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        // Only pop if dialog is still open
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      }
    } finally {
      // PROFESSIONAL FIX: ALWAYS reset submitting state in finally block
      // This ensures state is reset even if there's an exception or early return
      if (mounted && _isSubmitting) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showResultDialog(bool isCorrect, int pointsEarned, [String? message]) {
    // Ultimate UI silence: quiz result dialog disabled; balance refresh already ran in submit path.
    /*
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated success/result icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrect
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                ),
                child: Icon(
                  isCorrect ? Icons.celebration : Icons.info_outline,
                  color: isCorrect ? Colors.green : Colors.orange,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(
                isCorrect ? 'Correct! 🎉' : 'Thanks for participating!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // IMPORTANT:
              // We intentionally do NOT render the raw backend "message" here.
              // Backend messages can include internal details; prefer app-owned
              // localized copy for user-facing text.
              // Points earned
              if (pointsEarned > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.deepBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.deepBlue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stars,
                        color: AppTheme.deepBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'You earned $pointsEarned points!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.deepBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!isCorrect) ...[
                const SizedBox(height: 8),
                Text(
                  'Better luck next time!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              // OK Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Refresh engagement feed to show updated status
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final engagementProvider =
                          Provider.of<EngagementProvider>(context,
                              listen: false);
                      final authProvider =
                          Provider.of<AuthProvider>(context, listen: false);
                      if (authProvider.user != null) {
                        engagementProvider.refresh(
                          userId: authProvider.user!.id,
                          token: authProvider.token,
                        );
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isCorrect ? Colors.green : AppTheme.deepBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    */
  }
}

/// Professional Poll Dialog Widget
/// Distinct from Quiz: Uses orange theme, voting terminology, and poll-specific UI
class _PollDialog extends StatefulWidget {
  final EngagementItem item;

  const _PollDialog({required this.item});

  @override
  State<_PollDialog> createState() => _PollDialogState();
}

class _PollDialogState extends State<_PollDialog> {
  /// Checkbox-style poll: multiple selection (Set of option indices).
  /// Replaces previous radio-style single selection for better UX.
  final Set<int> _selectedIndices = {};
  /// Isolated per-option state: [pollOptionUniqueId] -> multiplier. Matches receipt lookup.
  final Map<String, int> _isolatedUnitsByOption = <String, int>{};
  bool _isSubmitting = false;
  int? _confirmedBalanceForSubmit;

  String _optionKeyForIndex(int index) {
    final opts = widget.item.quizData?.options ?? const <dynamic>[];
    return pollOptionUniqueId(opts, index);
  }

  @override
  void initState() {
    super.initState();
    _updateSelectedFromItem();
  }

  @override
  void didUpdateWidget(_PollDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.userAnswer != oldWidget.item.userAnswer ||
        widget.item.userBetUnitsPerOption != oldWidget.item.userBetUnitsPerOption) {
      _updateSelectedFromItem();
    }
  }

  /// Parse [userAnswer] indices; hydrate units from API, else overlay, else 1. Any option count.
  void _updateSelectedFromItem() {
    final options = widget.item.quizData?.options ?? const <dynamic>[];
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    if (widget.item.hasInteracted && widget.item.userAnswer != null) {
      final raw = widget.item.userAnswer!.trim();
      _selectedIndices.clear();
      _isolatedUnitsByOption.clear();
      final perOption = widget.item.userBetUnitsPerOption;
      for (final part in raw.split(',')) {
        final idx = int.tryParse(part.trim());
        if (idx == null || idx < 0 || idx >= options.length) {
          continue;
        }
        _selectedIndices.add(idx);
        final k = pollOptionUniqueId(options, idx);
        final fromApi = perOption?[idx];
        // Old Code:
        // final local = _pollUserLocalUnitOverlay[
        //     pollUserLocalUnitStorageKey(widget.item.id, k)];
        //
        // New Code:
        final local =
            engagementProvider.getPollUserLocalUnitOverride(widget.item.id, k);
        final int u;
        if (fromApi != null && fromApi > 0) {
          u = fromApi;
          recordPollUserLocalUnitOverride(engagementProvider, widget.item.id, k, u);
        } else if (local != null && local > 0) {
          u = local;
        } else {
          u = 1;
        }
        _isolatedUnitsByOption[k] = u;
      }
    } else if (!widget.item.hasInteracted) {
      _selectedIndices.clear();
      _isolatedUnitsByOption.clear();
    }
  }

  void _toggleOption(int index) {
    setState(() {
      final k = _optionKeyForIndex(index);
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        _isolatedUnitsByOption.remove(k);
      } else {
        _selectedIndices.add(index);
        _isolatedUnitsByOption[k] = _isolatedUnitsByOption[k] ?? 1;
      }
    });
  }

  /// Persists to [recordPollUserLocalUnitOverride] so [pollUserSeparatedBetStates] can read.
  void _updateOptionUnitValue(int optionIndex, int nextValue) {
    if (nextValue <= 0) return;
    final k = _optionKeyForIndex(optionIndex);
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    setState(() {
      _isolatedUnitsByOption[k] = nextValue;
      recordPollUserLocalUnitOverride(
          engagementProvider, widget.item.id, k, nextValue);
      // ignore: avoid_print
      print('User Selected Multiplier: $nextValue (optionKey=$k)');
    });
  }

  /// Per selected checkbox PNP (stake only — never [rewardPoints] / win potential).
  int get _perUnitPollPnp {
    final q = widget.item.quizData;
    if (q == null) return 1000;
    return q.spentPerUnitPnpForPoll(engagementRewardPoints: widget.item.rewardPoints);
  }

  /*
  // OLD total logic (kept for reference):
  // This assumed one shared amount across all selected options.
  int get _totalCost => _perUnitPollPnp * _selectedIndices.length;
  */

  /// Grand total derived from isolated per-option states (safe, non-mutating).
  int get _isolatedGrandTotalPnp {
    var total = 0;
    for (final idx in _selectedIndices) {
      final k = _optionKeyForIndex(idx);
      total += _perUnitPollPnp * (_isolatedUnitsByOption[k] ?? 1);
    }
    return total;
  }

  /// Balance from user custom fields (my_point / My Point Value / points_balance from /users/me).
  /// Used when PointProvider gives 0 so confirmation dialog shows real balance,
  /// matching the same source My PNP card uses.
  static int _balanceFromCustomFields(Map<String, String>? customFields) {
    if (customFields == null) return 0;
    final raw = customFields['my_point'] ??
        customFields['my_points'] ??
        customFields['My Point Value'] ??
        customFields['points_balance'];
    if (raw == null || raw.trim().isEmpty) return 0;

    final trimmed = raw.trim();

    // Try direct int parse first (e.g. "18200")
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;

    // Old Code: // Fallback: extract first number sequence from strings like "18,200 points"
    // Old Code: final match = RegExp(r'\d+').firstMatch(trimmed);
    // Old Code: if (match != null) {
    // Old Code:   final extracted = match.group(0);
    // Old Code:   if (extracted != null) {
    // Old Code:     final parsed = int.tryParse(extracted);
    // Old Code:     if (parsed != null) return parsed;
    // Old Code:   }
    // Old Code: }

    final numericString = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(numericString) ?? 0;
  }

  Future<void> _onPlayPressed() async {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ကျေးဇူးပြု၍ အနည်းဆုံး တစ်ခု ရွေးချယ်ပါ။'),
        ),
      );
      return;
    }

    final selectedCount = _selectedIndices.length;
    final q = widget.item.quizData;
    if (q == null) return;
    final allowUserAmount = q.allowUserAmount;
    final int perUnitPnp = q.spentPerUnitPnpForPoll(engagementRewardPoints: widget.item.rewardPoints);
    // Cost when Amount multiplier k = 1
    final requiredPerAmount = perUnitPnp * selectedCount;

    // Fetch latest REAL balance from API (PointProvider)
    // PROFESSIONAL FIX: Use only PointProvider/currentBalance (backed by /points/balance)
    // so client-side check matches the server's single source of truth (get_user_point_balance)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final pointProvider = Provider.of<PointProvider>(context, listen: false);
    final userId = authProvider.user?.id;
    if (userId == null) return;
    if (!mounted) return;
    setState(() => _isSubmitting = true);
    await pointProvider.loadBalance(userId.toString(), forceRefresh: true);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // REAL balance used for poll cost check (matches backend)
    int userBalance = pointProvider.currentBalance;
    // If PointProvider returned 0 (e.g. /points/balance failed or not loaded),
    // use AuthProvider custom fields (same source as My PNP) so user sees real balance.
    if (userBalance == 0) {
      final fromAuth =
          _balanceFromCustomFields(authProvider.user?.customFields);
      if (fromAuth > 0) userBalance = fromAuth;
    }

    if (requiredPerAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Poll cost မမှန်ကန်သဖြင့် ကစား၍မရပါ။'),
        ),
      );
      return;
    }

    // Determine maximum amount user can afford for current selection
    final maxAmount = userBalance ~/ requiredPerAmount;

    if (maxAmount <= 0) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Point မလောက်ပါ',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text(
            'ဤ Poll သည် checkbox တစ်ခုလျှင် $perUnitPnp points ကုန်ကျပါသည်။\n\n'
            'သင်ရွေးချယ်ထားသော checkbox $selectedCount ခုအတွက် အနည်းဆုံး '
            '$requiredPerAmount points လိုအပ်ပါသည် (အနိမ့်ဆုံး Amount အဆင့်)။\n\n'
            'သင့်လက်ကျန်: $userBalance points ဖြစ်သဖြင့် ယခုအချိန်တွင် ကစား၍ မရနိုင်ပါ။',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ပိတ်မည်'),
            ),
          ],
        ),
      );
      return;
    }

    if (!allowUserAmount) {
      final totalCost = requiredPerAmount;
      if (userBalance < totalCost) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Point မလောက်ပါ',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            content: Text(
              'ဤ Poll သည် checkbox တစ်ခုလျှင် $perUnitPnp points ကုန်ကျပါသည်။\n\n'
              'သင်ရွေးချယ်ထားသော checkbox $selectedCount ခုအတွက် စုစုပေါင်း $totalCost points လိုအပ်ပါသည်။\n\n'
              'သင့်လက်ကျန်: $userBalance points ဖြစ်သဖြင့် ယခုအချိန်တွင် ကစား၍ မရနိုင်ပါ။',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ပိတ်မည်'),
              ),
            ],
          ),
        );
        return;
      }

      // Confirm single-Amount (1× base cost) spend — Base Cost mode
      await _submitVote(amount: 1);
      return;
    }

    // Remember the confirmed balance we showed to the user
    _confirmedBalanceForSubmit = userBalance;

    // Step 2: Let user choose Amount per option (each selected option gets its own amount)
    final selectedList = _selectedIndices.toList()..sort();
    final options = q.options;
    for (final i in selectedList) {
      final k = _optionKeyForIndex(i);
      _isolatedUnitsByOption[k] = _isolatedUnitsByOption[k] ?? 1;
    }

    // Old Code: per-option amount `showDialog<void>` — both actions used `Navigator.pop(ctx)` only (no result).
    /*
    // Old Code:
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int totalCost = 0;
            for (final idx in selectedList) {
              final k = _optionKeyForIndex(idx);
              totalCost += perUnitPnp * (_isolatedUnitsByOption[k] ?? 1);
            }
            final canAfford = totalCost <= userBalance;
            return AlertDialog(
              title: const Text(
                'Option တစ်ခုချင်းစီအတွက် Amount သတ်မှတ်ပါ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('သင့်လက်ရှိ Point: $userBalance', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('အဆင့် တစ်ခုလျှင်: $perUnitPnp PNP', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    const SizedBox(height: 16),
                    ...selectedList.map((idx) {
                      final k = _optionKeyForIndex(idx);
                      final amt = _isolatedUnitsByOption[k] ?? 1;
                      final optLabel = idx < options.length ? options[idx] : 'Option ${idx + 1}';
                      final maxForThis = userBalance ~/ perUnitPnp;
                      return Padding(
                        key: ValueKey<String>(k),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                optLabel,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                                  onPressed: amt > 1
                                      ? () => setDialogState(() {
                                            final dynamicValue = amt - 1;
                                            _updateOptionUnitValue(idx, dynamicValue);
                                          })
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: Text('$amt', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 22),
                                  onPressed: amt < maxForThis
                                      ? () => setDialogState(() {
                                            final dynamicValue = amt + 1;
                                            _updateOptionUnitValue(idx, dynamicValue);
                                          })
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                              ],
                            ),
                            Text('${perUnitPnp * amt}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Text(
                      'စုစုပေါင်း ကုန်ကျမည်: $totalCost PNP',
                      style: TextStyle(fontWeight: FontWeight.bold, color: canAfford ? null : Colors.red),
                    ),
                    if (!canAfford)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Point မလောက်ပါ (လိုအပ်ချက်: $totalCost)', style: TextStyle(fontSize: 12, color: Colors.red[700])),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်တော့ပါ', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: canAfford
                      ? () => Navigator.pop(ctx)
                      : null,
                  child: const Text('ကစားမည်'),
                ),
              ],
            );
          },
        );
      },
    );
    */

    final bool? isConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int totalCost = 0;
            for (final idx in selectedList) {
              final k = _optionKeyForIndex(idx);
              totalCost += perUnitPnp * (_isolatedUnitsByOption[k] ?? 1);
            }
            final canAfford = totalCost <= userBalance;
            return AlertDialog(
              title: const Text(
                'Option တစ်ခုချင်းစီအတွက် Amount သတ်မှတ်ပါ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('သင့်လက်ရှိ Point: $userBalance', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('အဆင့် တစ်ခုလျှင်: $perUnitPnp PNP', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    const SizedBox(height: 16),
                    ...selectedList.map((idx) {
                      final k = _optionKeyForIndex(idx);
                      final amt = _isolatedUnitsByOption[k] ?? 1;
                      final optLabel = idx < options.length ? options[idx] : 'Option ${idx + 1}';
                      final maxForThis = userBalance ~/ perUnitPnp;
                      return Padding(
                        key: ValueKey<String>(k),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                optLabel,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                                  onPressed: amt > 1
                                      ? () => setDialogState(() {
                                            final dynamicValue = amt - 1;
                                            _updateOptionUnitValue(idx, dynamicValue);
                                          })
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: Text('$amt', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 22),
                                  onPressed: amt < maxForThis
                                      ? () => setDialogState(() {
                                            final dynamicValue = amt + 1;
                                            _updateOptionUnitValue(idx, dynamicValue);
                                          })
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                              ],
                            ),
                            Text('${perUnitPnp * amt}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Text(
                      'စုစုပေါင်း ကုန်ကျမည်: $totalCost PNP',
                      style: TextStyle(fontWeight: FontWeight.bold, color: canAfford ? null : Colors.red),
                    ),
                    if (!canAfford)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Point မလောက်ပါ (လိုအပ်ချက်: $totalCost)', style: TextStyle(fontSize: 12, color: Colors.red[700])),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('မလုပ်တော့ပါ', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: canAfford
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('ကစားမည်'),
                ),
              ],
            );
          },
        );
      },
    );
    if (isConfirmed != true) return;
    if (!mounted) return;

    int finalTotalCost = 0;
    for (final idx in selectedList) {
      final k = _optionKeyForIndex(idx);
      finalTotalCost += perUnitPnp * (_isolatedUnitsByOption[k] ?? 1);
    }
    if (finalTotalCost > userBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('သတ်မှတ်ထားသော Amount အတွက် Point မလောက်တော့ပါ။ ပြန်လည် ကြိုးစားကြည့်ပါ။')),
      );
      return;
    }

    final isolatedAmountPerOption = <int, int>{};
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    for (final idx in selectedList) {
      final k = _optionKeyForIndex(idx);
      final u = _isolatedUnitsByOption[k] ?? 1;
      recordPollUserLocalUnitOverride(engagementProvider, widget.item.id, k, u);
      isolatedAmountPerOption[idx] = u;
    }
    await _submitVote(amountPerOption: isolatedAmountPerOption);
  }

  @override
  Widget build(BuildContext context) {
    final pollData = widget.item.quizData!;
    final pollColor = Colors.deepOrange;

    // Parsed previous vote indices for "already voted" display (read-only from item).
    final Set<int> userSelectedIndices = {};
    if (widget.item.hasInteracted && widget.item.userAnswer != null) {
      for (final part in widget.item.userAnswer!.trim().split(',')) {
        final idx = int.tryParse(part.trim());
        if (idx != null && idx >= 0) userSelectedIndices.add(idx);
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Poll Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.poll, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Question
            Text(
              pollData.question,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ရွေးချယ်နိုင်သည့် အဖြေများ (တစ်ခုထက် ပိုရွေးနိုင်သည်)',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 20),
            // Show message when user has already voted (read-only display).
            if (widget.item.hasInteracted && userSelectedIndices.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  // User Amount mode: show bet amount when available
                  final betAmt = widget.item.userBetAmount;
                  final q = widget.item.quizData;
                  final isUserAmountMode = q?.allowUserAmount ?? false;
                  String voteMsg =
                      'ဤ Poll ကို ကစားပြီးပါပြီ။\nအောက်တွင် သင်ရွေးချယ်ထားသည့် အဖြေများကို ပြထားပါသည်။\n(တစ်ကြိမ်သာ ကစားနိုင်ပါသည်။)';
                  if (isUserAmountMode && betAmt != null && betAmt > 0) {
                    final count = userSelectedIndices.length;
                    final totalAmountUnits = betAmt * count;
                    voteMsg +=
                        '\nသင် ထိုးခဲ့သော Amount: $betAmt (ရွေးချယ်ထားသော အဖြေ $count ခု, စုစုပေါင်း Amount $totalAmountUnits)';
                  }
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: pollColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: pollColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.how_to_vote, color: pollColor, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            voteMsg,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: pollColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
            // Options: Checkbox-style (multiple selection) instead of Radio.
            ...List.generate(
              pollData.options.length,
              (index) {
                final isSelected = _selectedIndices.contains(index);
                final isUserPreviousSelection = widget.item.hasInteracted &&
                    userSelectedIndices.contains(index) &&
                    !isSelected;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: (_isSubmitting || widget.item.hasInteracted)
                        ? null
                        : () {
                            _toggleOption(index);
                            app_logger.Logger.info(
                                'Poll option toggled: index=$index, selected=${_selectedIndices.toList()}',
                                tag: 'EngagementCarousel');
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? pollColor.withOpacity(0.15)
                            : Colors.grey[100],
                        border: Border.all(
                          color: isSelected ? pollColor : Colors.grey[300]!,
                          width: isUserPreviousSelection
                              ? 2.5
                              : isSelected
                                  ? 3
                                  : 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Checkbox-style: square with check (Material Checkbox for semantics).
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_isSubmitting ||
                                      widget.item.hasInteracted)
                                  ? null
                                  : (_) => _toggleOption(index),
                              activeColor: pollColor,
                              checkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pollData.options[index],
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isUserPreviousSelection)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: pollColor.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'ယခင်ရွေးချယ်မှု',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (isSelected)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: pollColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'သင့်ရွေးချယ်မှု',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // Submit Button - Poll specific (enabled when at least one option selected).
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedIndices.isEmpty ||
                        _isSubmitting ||
                        widget.item.hasInteracted
                    ? null
                    : _onPlayPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: pollColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        widget.item.hasInteracted ? 'ကစားပြီးပါပြီ' : 'ကစားမည်',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitVote({int amount = 1, Map<int, int>? amountPerOption}) async {
    if (_selectedIndices.isEmpty) return;

    // TEMP: Block re-submission if user has already interacted with this poll
    if (widget.item.hasInteracted) {
      app_logger.Logger.info(
        'Vote submission blocked: user already voted on this poll (itemId=${widget.item.id})',
        tag: 'EngagementCarousel',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('ဤ Poll ကို ကစားပြီးပါပြီ။ တစ်ကြိမ်သာ ကစားနိုင်ပါသည်။'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // PROFESSIONAL FIX: Don't allow multiple simultaneous submissions for the same dialog
    // But allow new submissions if previous one completed (even if refresh is ongoing)
    if (_isSubmitting) {
      app_logger.Logger.warning(
          'Vote submission already in progress, ignoring duplicate request',
          tag: 'EngagementCarousel');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    // PROFESSIONAL FIX: Use try-finally to ensure _isSubmitting is ALWAYS reset
    // This prevents blocking subsequent vote submissions from other polls
    // Each dialog instance has its own _isSubmitting state, so this ensures proper cleanup
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final engagementProvider =
          Provider.of<EngagementProvider>(context, listen: false);
      final pointProvider = Provider.of<PointProvider>(context, listen: false);

      // PROFESSIONAL FIX: Ensure token is loaded before checking authentication
      // This handles cases where token might not be cached yet after user switch
      String? token = authProvider.token; // Try synchronous getter first
      if (token == null) {
        // If token is not cached, load it from storage
        app_logger.Logger.info('Token not cached, loading from storage...',
            tag: 'EngagementCarousel');
        token = await authProvider.getToken();
      }

      // Validate authentication state with proper error handling
      if (authProvider.user == null) {
        app_logger.Logger.warning('User is null, cannot submit poll vote',
            tag: 'EngagementCarousel');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ကစားရန် Login လုပ်ပါ။'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      if (token == null) {
        app_logger.Logger.warning(
            'Token is null after loading attempt, cannot submit poll vote',
            tag: 'EngagementCarousel');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ကစားရန် Login လုပ်ပါ။'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // PROFESSIONAL FIX: Validate user is still authenticated before submission
      final currentUserId = authProvider.user!.id;
      final quiz = widget.item.quizData;
      if (quiz == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Poll ဒေတာ မရှိပါ။')),
          );
        }
        return;
      }
      final stakePerUnit = quiz.spentPerUnitPnpForPoll(engagementRewardPoints: widget.item.rewardPoints);
      int totalCost;
      if (amountPerOption != null && amountPerOption.isNotEmpty) {
        totalCost = 0;
        for (final idx in _selectedIndices) {
          totalCost += stakePerUnit * (amountPerOption[idx] ?? 1);
        }
      } else {
        final amt = amount <= 0 ? 1 : amount;
        totalCost = quiz.allowUserAmount
            ? stakePerUnit * _selectedIndices.length * amt
            : stakePerUnit * _selectedIndices.length;
      }

      // Old Code: `await Future.wait` + `serverBalance` / `fromAuth` / `fromConfirmed` / max reduce / client pre-submit gate (redundant after `_onPlayPressed`; `submitInteraction` enforces balance).
      // Old Code:      // Re-fetch balance before submit (parallel for less delay)
      // Old Code:      await Future.wait([
      // Old Code:        authProvider.refreshUser(),
      // Old Code:        pointProvider.loadBalance(currentUserId.toString(), forceRefresh: true),
      // Old Code:      ]);
      // Old Code:      if (!mounted) return;
      // Old Code:
      // Old Code:      int serverBalance = pointProvider.currentBalance;
      // Old Code:      final fromAuth =
      // Old Code:          _balanceFromCustomFields(authProvider.user?.customFields);
      // Old Code:      final fromConfirmed = _confirmedBalanceForSubmit ?? 0;
      // Old Code:
      // Old Code:      // Use the maximum of all known balances for this single submit flow so that
      // Old Code:      // temporary API/meta desyncs don't incorrectly block the user.
      // Old Code:      serverBalance = [
      // Old Code:        serverBalance,
      // Old Code:        fromAuth,
      // Old Code:        fromConfirmed,
      // Old Code:      ].reduce((a, b) => a > b ? a : b);
      // Old Code:
      // Old Code:      if (serverBalance < totalCost) {
      // Old Code:        app_logger.Logger.warning(
      // Old Code:          'Balance re-check failed before submit: serverBalance=$serverBalance, totalCost=$totalCost',
      // Old Code:          tag: 'EngagementCarousel',
      // Old Code:        );
      // Old Code:        if (mounted) {
      // Old Code:          final messenger = ScaffoldMessenger.of(context);
      // Old Code:          messenger.showSnackBar(
      // Old Code:            SnackBar(
      // Old Code:              content: Text(
      // Old Code:                'Point မလောက်ပါ။ လက်ကျန်: $serverBalance, လိုအပ်ချက်: $totalCost။ ကျေးဇူးပြု၍ စာမျက်နှာ refresh လုပ်ပြီး ထပ်ကြိုးစားပါ။',
      // Old Code:              ),
      // Old Code:              backgroundColor: Colors.orange,
      // Old Code:              duration: const Duration(seconds: 4),
      // Old Code:            ),
      // Old Code:          );
      // Old Code:        }
      // Old Code:        return;
      // Old Code:      }

      // Local estimate for optimistic UI only (no extra network before submit; server is source of truth).
      int balanceBefore = _confirmedBalanceForSubmit ?? pointProvider.currentBalance;
      if (balanceBefore == 0) {
        final fromAuthUi =
            _balanceFromCustomFields(authProvider.user?.customFields);
        if (fromAuthUi > 0) balanceBefore = fromAuthUi;
      }

      // Send comma-separated indices for checkbox (multiple) selection.
      final answer = _selectedIndices.toList()..sort();
      final answerStr = answer.join(',');
      
      // CRITICAL FIX: Get session_id for AUTO_RUN polls
      // This enables multi-session voting (user can vote in each cycle)
      String? sessionId;
      final schedule = widget.item.pollVotingSchedule;
      
      if (schedule != null) {
        // Backend now provides current_session_id for AUTO_RUN polls
        sessionId = schedule['current_session_id']?.toString();
        
        // Fallback: Calculate manually if backend doesn't provide it (legacy compatibility)
        if ((sessionId == null || sessionId.isEmpty)) {
          final pollModeRaw = schedule['poll_mode']?.toString();
          final pollMode = pollModeRaw?.toUpperCase();
          
          // Calculate session for AUTO_RUN and MANUAL_SESSION polls
          if (pollMode == 'AUTO_RUN' || pollMode == 'MANUAL_SESSION') {
            final startedAtStr = schedule['poll_actual_start_at']?.toString();
            final pollDuration = schedule['poll_duration'] ?? schedule['poll_period_minutes'];
            final resultSecondsRaw = schedule['result_display_duration_seconds'] ??
                schedule['result_display_seconds'];
            
            if (startedAtStr != null && pollDuration != null && resultSecondsRaw != null) {
              final startedAt = DateTime.tryParse(startedAtStr);
              final pollDurationMin = (pollDuration is int) ? pollDuration : 
                                     (pollDuration is double) ? pollDuration.toInt() : 15;
              final resultSeconds = (resultSecondsRaw is int)
                  ? resultSecondsRaw
                  : (resultSecondsRaw is double)
                      ? resultSecondsRaw.toInt()
                      : int.tryParse(resultSecondsRaw.toString()) ?? 60;
              
              if (startedAt != null && pollDurationMin > 0) {
                // Cycle = voting window (minutes→seconds) + result phase (seconds).
                final cycleSeconds = (pollDurationMin * 60) + resultSeconds;
                final now = DateTime.now();
                final elapsed = now.difference(startedAt).inSeconds;
                final iteration = (elapsed / cycleSeconds).floor();
                sessionId = 's$iteration';
                app_logger.Logger.info(
                    'AUTO_RUN poll session calculated manually: $sessionId (elapsed: ${elapsed}s, cycle: ${cycleSeconds}s)',
                    tag: 'EngagementCarousel');
              }
            }
          }
        } else {
          app_logger.Logger.info(
              'Using session_id from backend: $sessionId',
              tag: 'EngagementCarousel');
        }
      }
      
      app_logger.Logger.info(
          'Submitting poll vote: userId=$currentUserId, itemId=${widget.item.id}, answer=$answerStr, sessionId=$sessionId, balanceBefore(optimistic)=$balanceBefore, amountPerOption=$amountPerOption',
          tag: 'EngagementCarousel');

      final result = await engagementProvider.submitInteraction(
        userId: currentUserId,
        token: token,
        itemId: widget.item.id,
        answer: answerStr,
        sessionId: sessionId,
        selectedOptionIds: answer,
        betAmount: amountPerOption == null ? (amount <= 0 ? 1 : amount) : null,
        betAmountPerOption: amountPerOption,
      );

      if (!mounted) return;

      // Capture messenger before pop - context may be invalid after Navigator.pop
      final messenger = ScaffoldMessenger.of(context);

      // PROFESSIONAL FIX: Reset submitting state BEFORE popping dialog
      // This ensures state is reset even if widget gets disposed after pop
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }

      // Pop poll dialog before showing result
      if (mounted) {
        Navigator.pop(context);
      }

      if (result['success'] == true) {
        final int newBalance = balanceBefore - totalCost;

        // ============================================================================
        // CRITICAL: Points deducted from wp_twork_point_transactions (backend)
        // Winner rewards will be added to SAME TABLE when poll is resolved
        // Balance = SUM(type='earn') - SUM(type='redeem') from wp_twork_point_transactions
        // ============================================================================
        
        app_logger.Logger.info(
            '✓ Poll vote submitted — DEDUCTION SUCCESS! Item: ${widget.item.id}, Cost: $totalCost, Balance: $balanceBefore → $newBalance',
            tag: 'EngagementCarousel');

        /*
        // OLD CODE:
        // Optimistic update: My PNP card updates instantly (no delay)
        // AuthProvider().applyPointsBalanceSnapshot(newBalance);
        // PointProvider.instance.applyRemoteBalanceSnapshot(
        //   userId: currentUserId.toString(),
        //   currentBalance: newBalance,
        // );
        */

        // NEW FIX: Canonical sync after poll vote deduction.
        unawaited(
          CanonicalPointBalanceSync.apply(
            userId: currentUserId.toString(),
            currentBalance: newBalance,
            source: 'poll_vote_deduct_carousel',
            emitBroadcast: false,
            pointProvider: pointProvider,
          ),
        );

        // Show success feedback so user knows points were deducted
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'ကစားမှု အောင်မြင်ပါသည်။ $totalCost points နှုတ်ယူပြီးပါပြီ။',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh user (my_point, my_points, points_balance) so Home Page My PNP updates
        authProvider.refreshUser().catchError((error) {
          app_logger.Logger.warning('Failed to refresh user after vote: $error',
              tag: 'EngagementCarousel');
        });

        // Refresh points balance (non-blocking)
        pointProvider
            .loadBalance(
          authProvider.user!.id.toString(),
          forceRefresh: true,
        )
            .then((_) {
          // loadBalance returns void, so we read the updated balance from the provider
          final refreshedBalance = pointProvider.currentBalance;
          app_logger.Logger.info(
              'Balance refreshed after poll vote: $refreshedBalance (expected: $newBalance)',
              tag: 'EngagementCarousel');
        })
            .catchError((error) {
          app_logger.Logger.warning('Failed to refresh points balance: $error',
              tag: 'EngagementCarousel');
        });

        // PROFESSIONAL FIX: Refresh engagement feed asynchronously without blocking
        // This allows subsequent vote submissions to proceed even during refresh
        engagementProvider
            .refresh(
          userId: authProvider.user!.id,
          token: token,
        )
            .catchError((error) {
          app_logger.Logger.warning('Failed to refresh engagement feed: $error',
              tag: 'EngagementCarousel');
        });
      } else {
        // PROFESSIONAL FIX: Handle duplicate and insufficient_balance errors
        final message =
            result['message']?.toString() ?? 'ကစားမှု မအောင်မြင်ပါ။';
        final isDuplicate = result['is_duplicate'] == true;
        final isInsufficient =
            result['code']?.toString().toLowerCase() == 'insufficient_balance';

        app_logger.Logger.warning(
            'Poll submission failed: $message, isDuplicate: $isDuplicate, isInsufficient: $isInsufficient',
            tag: 'EngagementCarousel');

        // Old Code: `confirmedBalance` / `serverSaysZero` / `weHadBalance` / `requiredInt` / layered displayMessage (server `insufficient_balance` already authoritative).
        // Old Code:        final int? confirmedBalance = _confirmedBalanceForSubmit;
        // Old Code:        final int requiredInt = requiredVal is int
        // Old Code:            ? requiredVal
        // Old Code:            : (requiredVal is num
        // Old Code:                ? requiredVal.toInt()
        // Old Code:                : int.tryParse(requiredVal.toString()) ?? 0);
        // Old Code:        final bool serverSaysZero =
        // Old Code:            isInsufficient && serverBalanceVal != null && serverBalanceVal == 0;
        // Old Code:        final bool weHadBalance = confirmedBalance != null &&
        // Old Code:            confirmedBalance > 0 &&
        // Old Code:            requiredVal != null &&
        // Old Code:            confirmedBalance >= requiredInt;
        // Old Code:        final String displayMessage;
        // Old Code:        if (isInsufficient && requiredVal != null) {
        // Old Code:          if (serverSaysZero && weHadBalance) {
        // Old Code:            displayMessage = ...;
        // Old Code:          } else if (serverBalanceVal != null) {
        // Old Code:            displayMessage = ...;
        // Old Code:          } else {
        // Old Code:            displayMessage = message;
        // Old Code:          }
        // Old Code:        } else {
        // Old Code:          displayMessage = message;
        // Old Code:        }

        final String displayMessage;
        if (isInsufficient) {
          final m = message.trim();
          displayMessage =
              m.isNotEmpty ? m : 'Point မလောက်ပါ။ သင့်လက်ကျန် မလောက်ပါ။';
        } else {
          displayMessage = message;
        }

        // If duplicate or user mismatch, refresh engagement feed to sync state (non-blocking)
        if (isDuplicate ||
            message.toLowerCase().contains('user') ||
            message.toLowerCase().contains('account')) {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.user != null) {
            engagementProvider
                .refresh(
              userId: authProvider.user!.id,
              token: authProvider.token,
            )
                .catchError((error) {
              app_logger.Logger.warning(
                  'Failed to refresh engagement feed after error: $error',
                  tag: 'EngagementCarousel');
            });
          }
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text(isDuplicate
                ? 'ဤ Poll ကို ကစားပြီးပါပြီ။ တစ်ကြိမ်သာ ကစားနိုင်ပါသည်။'
                : displayMessage),
            backgroundColor: isDuplicate ? Colors.orange : Colors.red,
            duration: Duration(
                seconds: isDuplicate ? 3 : (isInsufficient ? 5 : 2)),
          ),
        );
      }
    } catch (e, stackTrace) {
      // PROFESSIONAL FIX: Handle any exceptions gracefully
      app_logger.Logger.error('Exception during vote submission: $e',
          tag: 'EngagementCarousel', error: e, stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'ကစားမှု ပို့ရာတွင် ပြဿနာတစ်ခု ဖြစ်နေပါသည်။ နောက်တစ်ကြိမ် ထပ်ကြိုးစားပါ။'),
            backgroundColor: Colors.red,
          ),
        );
        // Only pop if dialog is still open
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      }
    } finally {
      // PROFESSIONAL FIX: ALWAYS reset submitting state in finally block
      // This ensures state is reset even if there's an exception or early return
      // This is critical to prevent blocking subsequent vote submissions
      if (mounted && _isSubmitting) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

/// Professional Image Quick View Dialog
/// Provides full-screen image viewing with zoom and pan capabilities
/// Quick View Dialog for Media (Image, GIF, Video)
class _ImageQuickViewDialog extends StatefulWidget {
  final String imageUrl;
  final String title;

  const _ImageQuickViewDialog({
    required this.imageUrl,
    required this.title,
  });

  @override
  State<_ImageQuickViewDialog> createState() => _ImageQuickViewDialogState();
}

class _ImageQuickViewDialogState extends State<_ImageQuickViewDialog> {
  @override
  Widget build(BuildContext context) {
    final mediaType = getMediaType(widget.imageUrl);
    final isVideo = mediaType == 'video';
    final isGif = mediaType == 'gif';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Full-screen media viewer
          GestureDetector(
            onTap: isVideo ? null : () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.black87,
              child: Center(
                child: isVideo || isGif
                    ? _EngagementMediaWidget(
                        mediaUrl: widget.imageUrl,
                        fit: BoxFit.contain,
                        autoplay: isVideo,
                        showControls: isVideo,
                        placeholder: Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        errorWidget: Container(
                          color: Colors.black,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white70,
                              size: 64,
                            ),
                          ),
                        ),
                      )
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.black,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.white70,
                                size: 64,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          // Title bar at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title.isNotEmpty ? widget.title : 'Media View',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Close button hint at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Tap anywhere to close',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Professional Content Quick View Dialog
/// Displays full content for Banner and Announcement cards
/// Shows image (if available) with zoom/pan and full text content
class _ContentQuickViewDialog extends StatelessWidget {
  final EngagementItem item;

  const _ContentQuickViewDialog({required this.item});

  /// Helper method to strip HTML tags from content
  String _stripHtmlTags(String html) {
    final RegExp exp =
        RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);
    return html.replaceAll(exp, '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = item.mediaUrl != null && item.mediaUrl!.isNotEmpty;
    final hasContent = item.content.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black87,
          child: SafeArea(
            child: Column(
              children: [
                // Title bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.type == EngagementType.banner
                            ? Icons.image
                            : Icons.campaign,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.title.isNotEmpty
                              ? item.title
                              : (item.type == EngagementType.banner
                                  ? 'Banner'
                                  : 'Announcement'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                // Content area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Media section (Image/GIF/Video) - if available
                        if (hasImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: getMediaType(item.mediaUrl!) == 'video'
                                ? _EngagementMediaWidget(
                                    mediaUrl: item.mediaUrl!,
                                    fit: BoxFit.contain,
                                    autoplay: false,
                                    showControls: true,
                                    placeholder: Container(
                                      height: 300,
                                      color: Colors.grey[900],
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    errorWidget: Container(
                                      height: 300,
                                      color: Colors.grey[900],
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.white70,
                                          size: 64,
                                        ),
                                      ),
                                    ),
                                  )
                                : InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 4.0,
                                    child: _EngagementMediaWidget(
                                      mediaUrl: item.mediaUrl!,
                                      fit: BoxFit.contain,
                                      autoplay: false,
                                      showControls: false,
                                      placeholder: Container(
                                        height: 300,
                                        color: Colors.grey[900],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      errorWidget: Container(
                                        height: 300,
                                        color: Colors.grey[900],
                                        child: const Center(
                                          child: Icon(
                                            Icons.image_not_supported,
                                            color: Colors.white70,
                                            size: 64,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // Text content section
                        if (hasContent) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _stripHtmlTags(item.content),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.6,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (!hasImage) ...[
                          // No content and no image
                          Container(
                            padding: const EdgeInsets.all(40),
                            child: const Center(
                              child: Text(
                                'No content available',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Close hint
                        Center(
                          child: Text(
                            'Tap anywhere to close',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blinking Number Widget with Creative Animation
/// Displays numbers with a smooth blinking/flashing effect
class _BlinkingNumberWidget extends StatefulWidget {
  final String number;
  final double size;

  const _BlinkingNumberWidget({
    required this.number,
    required this.size,
  });

  @override
  State<_BlinkingNumberWidget> createState() => _BlinkingNumberWidgetState();
}

class _BlinkingNumberWidgetState extends State<_BlinkingNumberWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // PROFESSIONAL FIX: Optimized animation for smooth number text blinking only
    // Animation applies ONLY to the number text, no background effects
    // Using optimal duration for smooth visual effect without performance issues
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    // Optimized opacity animation - smooth transition for number text blinking
    // Only the number text opacity changes, no background effects
    _opacityAnimation = Tween<double>(
      begin: 0.2, // Lower minimum for more dramatic fade effect
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut, // Smooth transition prevents flickering
      ),
    );

    // Subtle scale animation for pulsing effect - applies only to number text
    // Creates smooth pulsing/blinking effect on the number itself
    _scaleAnimation = Tween<double>(
      begin: 0.92, // Subtle scale variation
      end: 1.08, // Smooth pulsing effect
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut, // Smooth curve prevents visual jumps
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // PROFESSIONAL FIX: Optimized constraint handling for better performance
        // Use both width and height constraints to prevent overflow
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : double.infinity;

        // PROFESSIONAL FIX: Calculate responsive size efficiently
        // Use 95% of available space to maximize number visibility
        final widthBasedSize = maxWidth.isFinite
            ? (maxWidth * 0.95).clamp(150.0, 500.0)
            : widget.size.clamp(150.0, 500.0);
        final heightBasedSize = maxHeight.isFinite
            ? (maxHeight * 0.95).clamp(150.0, 500.0)
            : widget.size.clamp(150.0, 500.0);

        // Use the smaller of the two to ensure it fits perfectly
        final responsiveSize = maxWidth.isFinite && maxHeight.isFinite
            ? (widthBasedSize < heightBasedSize
                ? widthBasedSize
                : heightBasedSize)
            : widget.size.clamp(180.0, 450.0);

        // PROFESSIONAL FIX: Optimized AnimatedBuilder - only the number text blinks, no background effects
        // Container is minimal for layout only, all animations apply ONLY to the text
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Calculate animation values once per frame for efficiency
            final opacityValue = _opacityAnimation.value;
            final scaleValue = _scaleAnimation.value;

            // Minimal container for layout - no background, no decoration, no padding
            // Only used to center the blinking number text
            return Container(
              width: double.infinity,
              height: maxHeight.isFinite ? maxHeight : null,
              constraints: BoxConstraints(
                maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
                maxHeight: maxHeight.isFinite ? maxHeight : double.infinity,
                minWidth: 0,
                minHeight: 0,
              ),
              // No padding, no decoration, no background - clean layout container
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                // PROFESSIONAL FIX: Apply opacity and scale animations ONLY to the number text
                // This ensures ONLY the number blinks, no background effects
                child: Transform.scale(
                  scale: scaleValue,
                  child: Opacity(
                    opacity: opacityValue,
                    child: Text(
                      widget.number,
                      style: TextStyle(
                        fontSize: responsiveSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: responsiveSize * 0.03,
                        height: 1.0,
                        // PROFESSIONAL FIX: No shadows, no effects - clean number text only
                        // Only the number itself blinks with smooth opacity and scale animation
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Animated Background Pattern for Number Cards
/// Creates a subtle animated pattern in the background
class _AnimatedNumberBackground extends StatefulWidget {
  const _AnimatedNumberBackground();

  @override
  State<_AnimatedNumberBackground> createState() =>
      _AnimatedNumberBackgroundState();
}

class _AnimatedNumberBackgroundState extends State<_AnimatedNumberBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * 3.14159, // Full rotation in radians
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _NumberBackgroundPainter(
            rotation: _rotationAnimation.value,
          ),
          child: Container(),
        );
      },
    );
  }
}

/// Custom Painter for Number Background Pattern
class _NumberBackgroundPainter extends CustomPainter {
  final double rotation;

  _NumberBackgroundPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    // Draw rotating circles
    for (int i = 0; i < 3; i++) {
      final x = center.dx + radius * 0.3 * (i + 1) * (rotation % 1);
      final y = center.dy + radius * 0.2 * (i + 1) * (rotation % 1);

      canvas.drawCircle(
        Offset(x, y),
        radius * 0.1 * (i + 1),
        paint,
      );
    }

    // Draw decorative lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 8; i++) {
      final startX = center.dx + radius * 0.2 * (i % 2 == 0 ? 1 : -1);
      final startY = center.dy;
      final endX = center.dx + radius * 0.6 * (i % 2 == 0 ? 1 : -1);
      final endY = center.dy;

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_NumberBackgroundPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}

/// Receipt-style list of selected poll options (per-option Count) on the carousel card.
class _VoteSubmittedCelebration extends StatelessWidget {
  final Map<String, int?>? detailedBets;

  const _VoteSubmittedCelebration({
    super.key,
    this.detailedBets,
  });

  @override
  Widget build(BuildContext context) {
    final bets = detailedBets;
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bets != null && bets.isNotEmpty) ...[
            _pollDetailedReceiptSection(
              context,
              detailedBets: bets,
              calculatedBets: null,
              heading: 'Your choice',
              wrapInGlass: true,
            ),
          ],
        ],
      ),
    );

    return IgnorePointer(
      child: SizedBox(
        width: double.infinity,
        child: content,
      ),
    );
  }
}
