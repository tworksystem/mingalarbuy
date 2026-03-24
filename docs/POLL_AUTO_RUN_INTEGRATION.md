# Poll Auto-Run Lifecycle Integration Guide

This guide provides code snippets and instructions for integrating the robust "Auto-Run" poll lifecycle into the existing T-Work Rewards engagement system.

## Overview

- **Poll Modes:** `AUTO_RUN`, `SCHEDULED`, `MANUAL`
- **New Config Fields:** `poll_duration` (minutes), `result_display_duration` (minutes), `started_at` (datetime)
- **Approach:** Time-based lazy evaluation (no WP-Cron loops) — state is calculated when the client requests it
- **Session-based votes:** Each AUTO_RUN cycle = one `session_id`; votes are scoped per session

---

## 1. Database Migration

Add this migration logic to `run_engagement_migrations()` in `twork-rewards-system.php`. Place it **after** the existing `rotation_duration` migration block.

### 1.1 Add `session_id` to user_interactions

```php
// Add session_id column to user_interactions for poll session scoping
$table_interactions = $wpdb->prefix . 'twork_user_interactions';
$session_col_exists = $wpdb->get_results("SHOW COLUMNS FROM `" . esc_sql($table_interactions) . "` LIKE 'session_id'");
if (empty($session_col_exists)) {
    $wpdb->query("ALTER TABLE `" . esc_sql($table_interactions) . "` ADD COLUMN `session_id` varchar(50) NOT NULL DEFAULT '' AFTER `item_id`");
    // Backfill existing rows with empty session_id
    $wpdb->query("UPDATE `" . esc_sql($table_interactions) . "` SET session_id = '' WHERE session_id IS NULL");
}
// Drop old unique key if exists, add new composite unique key
$wpdb->query("ALTER TABLE `" . esc_sql($table_interactions) . "` DROP INDEX IF EXISTS user_item_unique");
$wpdb->query("ALTER TABLE `" . esc_sql($table_interactions) . "` ADD UNIQUE KEY user_item_session_unique (user_id, item_id, session_id)");
```

### 1.2 quiz_data JSON structure for polls

Store in `quiz_data` (no new columns needed):

```json
{
  "question": "Your question?",
  "options": [
    {"text": "Option A", "media_url": "https://example.com/a.gif", "media_type": "gif"},
    {"text": "Option B", "media_url": "https://example.com/b.jpg", "media_type": "image"},
    {"text": "Option C", "media_url": "https://example.com/c.mp4", "media_type": "video"}
  ],
  "poll_mode": "AUTO_RUN",
  "poll_duration": 15,
  "result_display_duration": 1,
  "started_at": "2025-02-22 10:00:00"
}
```

- `poll_mode`: `AUTO_RUN` | `SCHEDULED` | `MANUAL`
- `poll_duration`: minutes (e.g., 15)
- `result_display_duration`: minutes (e.g., 1)
- `started_at`: datetime for first cycle (required for AUTO_RUN)
- **Options** (legacy or extended):
  - Legacy: `"options": ["A", "B", "C"]`
  - Extended: `"options": [{ "text": "A", "media_url": "...", "media_type": "image"|"gif"|"video" }, ...]`

---

## 2. REST API Endpoints

Register these routes in `register_engagement_routes()` (add after existing routes).

### 2.1 GET poll-state — Lazy Evaluation

**Route:** `GET /wp-json/twork/v1/poll/state/(?P<poll_id>\d+)`

```php
register_rest_route('twork/v1', '/poll/state/(?P<poll_id>\d+)', array(
    'methods' => WP_REST_Server::READABLE,
    'callback' => array($this, 'rest_poll_state'),
    'permission_callback' => '__return_true',
    'args' => array(
        'poll_id' => array(
            'required' => true,
            'validate_callback' => function ($p) { return absint($p) > 0; }
        ),
    ),
));
```

**Handler `rest_poll_state`:**

```php
public function rest_poll_state(WP_REST_Request $request)
{
    global $wpdb;
    $poll_id = absint($request->get_param('poll_id'));
    if ($poll_id <= 0) {
        return new WP_REST_Response(array('success' => false, 'message' => 'Invalid poll_id'), 400);
    }

    $table_items = $wpdb->prefix . 'twork_engagement_items';
    $item = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table_items WHERE id = %d AND type = 'poll'", $poll_id), ARRAY_A);
    if (!$item) {
        return new WP_REST_Response(array('success' => false, 'message' => 'Poll not found'), 404);
    }

    $quiz_data = json_decode($item['quiz_data'], true);
    if (!is_array($quiz_data)) {
        return new WP_REST_Response(array('success' => false, 'message' => 'Invalid poll config'), 500);
    }

    $mode = strtoupper($quiz_data['poll_mode'] ?? 'MANUAL');
    $poll_duration_min = max(1, (int) ($quiz_data['poll_duration'] ?? 15));
    $result_duration_min = max(0, (int) ($quiz_data['result_display_duration'] ?? 1));

    $cycle_seconds = ($poll_duration_min + $result_duration_min) * 60;
    $voting_seconds = $poll_duration_min * 60;

    if ($mode !== 'AUTO_RUN') {
        // SCHEDULED / MANUAL: use existing poll_voting_end_time if set
        $end_time = $quiz_data['poll_voting_end_time'] ?? '';
        $end_ts = !empty($end_time) ? strtotime($end_time) : 0;
        $now_ts = time();
        $state = ($end_ts > 0 && $now_ts > $end_ts) ? 'SHOWING_RESULTS' : 'ACTIVE';
        return new WP_REST_Response(array(
            'success' => true,
            'data' => array(
                'state' => $state,
                'current_session_id' => '',
                'ends_at' => $end_time ?: null,
                'poll_duration' => $poll_duration_min,
                'result_display_duration' => $result_duration_min,
                'mode' => $mode,
            ),
        ), 200);
    }

    $started_at = $quiz_data['started_at'] ?? $quiz_data['poll_actual_start_at'] ?? '';
    if (empty($started_at)) {
        $started_at = current_time('mysql');
        $quiz_data['started_at'] = $started_at;
        $wpdb->update($table_items, array('quiz_data' => wp_json_encode($quiz_data)), array('id' => $poll_id), array('%s'), array('%d'));
    }

    $start_ts = strtotime($started_at);
    $now_ts = time();
    $elapsed = $now_ts - $start_ts;
    if ($elapsed < 0) $elapsed = 0;

    $iteration = (int) floor($elapsed / $cycle_seconds);
    $cycle_start_ts = $start_ts + ($iteration * $cycle_seconds);
    $voting_ends_ts = $cycle_start_ts + $voting_seconds;
    $results_ends_ts = $cycle_start_ts + $cycle_seconds;

    $session_id = 's' . $iteration;

    if ($now_ts < $voting_ends_ts) {
        $state = 'ACTIVE';
        $ends_at = date('Y-m-d\TH:i:s\Z', $voting_ends_ts);
    } elseif ($now_ts < $results_ends_ts) {
        $state = 'SHOWING_RESULTS';
        $ends_at = date('Y-m-d\TH:i:s\Z', $results_ends_ts);
    } else {
        $state = 'ACTIVE';
        $iteration++;
        $session_id = 's' . $iteration;
        $cycle_start_ts = $start_ts + ($iteration * $cycle_seconds);
        $voting_ends_ts = $cycle_start_ts + $voting_seconds;
        $ends_at = date('Y-m-d\TH:i:s\Z', $voting_ends_ts);
    }

    return new WP_REST_Response(array(
        'success' => true,
        'data' => array(
            'state' => $state,
            'current_session_id' => $session_id,
            'ends_at' => $ends_at,
            'poll_duration' => $poll_duration_min,
            'result_display_duration' => $result_duration_min,
            'mode' => 'AUTO_RUN',
        ),
    ), 200);
}
```

### 2.2 POST vote — With session_id

Update `rest_engagement_interact` to accept `session_id` for polls. Add to the params extraction:

```php
$session_id = isset($params['session_id']) ? sanitize_text_field($params['session_id']) : '';
```

For AUTO_RUN polls, use the `current_session_id` from the poll-state response. For MANUAL/SCHEDULED, pass empty string.

When inserting the interaction for a **poll**, include `session_id`:

```php
$wpdb->insert($table_interactions, array(
    'user_id' => $user_id,
    'item_id' => $item_id,
    'session_id' => $session_id,
    'interaction_type' => 'poll_vote',
    'interaction_value' => $answer,
    // ... rest
), array('%d', '%d', '%s', '%s', '%s', ...));
```

And when checking for duplicate vote:

```php
if (!empty($session_id)) {
    $existing = $wpdb->get_var($wpdb->prepare(
        "SELECT id FROM $table_interactions WHERE user_id = %d AND item_id = %d AND session_id = %s",
        $user_id, $item_id, $session_id
    ));
} else {
    $existing = $wpdb->get_var($wpdb->prepare(
        "SELECT id FROM $table_interactions WHERE user_id = %d AND item_id = %d AND (session_id = '' OR session_id IS NULL)",
        $user_id, $item_id
    ));
}
```

### 2.3 GET poll-results — By session

**Route:** `GET /wp-json/twork/v1/poll/results/(?P<poll_id>\d+)/(?P<session_id>[a-zA-Z0-9_-]+)`

```php
register_rest_route('twork/v1', '/poll/results/(?P<poll_id>\d+)/(?P<session_id>[a-zA-Z0-9_-]+)', array(
    'methods' => WP_REST_Server::READABLE,
    'callback' => array($this, 'rest_poll_results_by_session'),
    'permission_callback' => '__return_true',
    'args' => array(
        'poll_id' => array('required' => true, 'validate_callback' => function ($p) { return absint($p) > 0; }),
        'session_id' => array('required' => true, 'sanitize_callback' => 'sanitize_text_field'),
    ),
));
```

**Handler:**

```php
public function rest_poll_results_by_session(WP_REST_Request $request)
{
    global $wpdb;
    $poll_id = absint($request->get_param('poll_id'));
    $session_id = sanitize_text_field($request->get_param('session_id'));

    $table_items = $wpdb->prefix . 'twork_engagement_items';
    $table_interactions = $wpdb->prefix . 'twork_user_interactions';

    $item = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table_items WHERE id = %d AND type = 'poll'", $poll_id), ARRAY_A);
    if (!$item) {
        return new WP_REST_Response(array('success' => false, 'message' => 'Poll not found'), 404);
    }

    $quiz_data = json_decode($item['quiz_data'], true);
    $options = $quiz_data['options'] ?? array();
    $num_options = count($options);

    $vote_counts = array();
    foreach (array_keys($options) as $i) $vote_counts[$i] = 0;

    $sql = $wpdb->prepare(
        "SELECT interaction_value FROM $table_interactions WHERE item_id = %d AND session_id = %s",
        $poll_id, $session_id
    );
    $rows = $wpdb->get_results($sql, ARRAY_A);
    foreach ($rows as $row) {
        $value = trim($row['interaction_value'] ?? '');
        if ($value === '') continue;
        foreach (array_map('trim', explode(',', $value)) as $part) {
            if ($part !== '' && is_numeric($part)) {
                $idx = (int) $part;
                if ($idx >= 0 && $idx < $num_options) $vote_counts[$idx]++;
            }
        }
    }

    $total_votes = array_sum($vote_counts);
    $percentages = array();
    foreach ($vote_counts as $i => $c) {
        $percentages[$i] = $total_votes > 0 ? round(($c / $total_votes) * 100, 2) : 0.0;
    }

    return new WP_REST_Response(array(
        'success' => true,
        'data' => array(
            'session_id' => $session_id,
            'vote_counts' => $vote_counts,
            'vote_percentages' => $percentages,
            'total_votes' => $total_votes,
            'options' => $options,
        ),
    ), 200);
}
```

---

## 3. Flutter: Smart Poll Widget

The `AutoRunPollWidget` is in `lib/widgets/auto_run_poll_widget.dart`.

### Usage in Engagement Carousel

Use `AutoRunPollWidget` when the poll has `poll_mode == 'AUTO_RUN'`:

```dart
// In _buildPollCard or wherever you render poll cards:
if ((item.pollVotingSchedule?['poll_mode'] ?? '') == 'AUTO_RUN') {
  return AutoRunPollWidget(
    pollId: item.id,
    question: item.quizData?.question ?? '',
    options: item.quizData?.options ?? [],
    rewardPoints: item.rewardPoints,
    title: item.title.isNotEmpty ? item.title : null,
    hasInteracted: item.hasInteracted,
    userAnswer: item.userAnswer,
    userId: currentUserId,
    onVoteSubmitted: () => engagementProvider.refresh(),
    onPointsEarned: () => pointProvider.refresh(),
  );
}
// Otherwise use existing _buildPollCard logic for SCHEDULED/MANUAL
```

### State Flow

1. **LOADING** → Fetch `GET /wp-json/twork/v1/poll/state/{poll_id}`
2. **ACTIVE** → Show voting UI; Timer re-evaluates every second against `ends_at`
3. **COUNTDOWN** → When ≤10 seconds to `ends_at`, show 10–9–8... countdown
4. **SHOWING_RESULTS** → Fetch `GET /wp-json/twork/v1/poll/results/{poll_id}/{session_id}`; show bars for `result_display_duration`
5. **RESET** → Re-fetch poll state and return to ACTIVE for the new session

---

## Integration Checklist

1. **WordPress**
   - Add migration for `session_id` in `run_engagement_migrations()`
   - Register `rest_poll_state` and `rest_poll_results_by_session` routes
   - Implement `rest_poll_state` and `rest_poll_results_by_session`
   - Update `rest_engagement_interact` to accept and store `session_id`
   - Update `get_engagement_item_statistics` to filter by `session_id` when provided (for results by session)

2. **Flutter**
   - Add `getPollState` and `getPollResultsBySession` to `EngagementService`
   - Add optional `sessionId` to `submitInteraction`
   - Use `AutoRunPollWidget` for polls in AUTO_RUN mode
