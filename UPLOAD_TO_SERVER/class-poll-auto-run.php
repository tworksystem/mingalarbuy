<?php
/**
 * Poll Auto-Run REST API and lazy-evaluation logic.
 * Integrate by requiring this file and calling TWork_Poll_Auto_Run::register()
 * from your main plugin class.
 *
 * @package TWork_Rewards
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Handles poll-state (lazy eval) and poll-results-by-session REST endpoints.
 *
 * Security: Routes use permission_callback __return_true; the mobile app authenticates
 * via WooCommerce consumer key/secret on the same requests. Do not expose sensitive
 * data beyond what engagement UX requires.
 */
class TWork_Poll_Auto_Run {

    /**
     * MySQL GET_LOCK name max length (portable across MariaDB/MySQL).
     */
    const POLL_REWARD_LOCK_MAX_NAME_LEN = 64;

    /**
     * Seconds to wait for advisory lock before proceeding without lock (degraded mode).
     */
    const POLL_REWARD_LOCK_TIMEOUT = 15;

    /**
     * Max session_id length accepted in URL (prevents oversized lock names / log noise).
     */
    const POLL_SESSION_ID_MAX_LEN = 191;

    /**
     * Register REST routes and hooks.
     */
    public static function register()
    {
        add_action('rest_api_init', array(__CLASS__, 'register_routes'));
    }

    /**
     * Register REST API routes.
     */
    public static function register_routes()
    {
        register_rest_route('twork/v1', '/poll/state/(?P<poll_id>\d+)', array(
            'methods' => WP_REST_Server::READABLE,
            'callback' => array(__CLASS__, 'rest_poll_state'),
            'permission_callback' => '__return_true',
            'args' => array(
                'poll_id' => array(
                    'required' => true,
                    'validate_callback' => function ($p) {
                        return absint($p) > 0;
                    },
                ),
            ),
        ));

        register_rest_route('twork/v1', '/poll/results/(?P<poll_id>\d+)/(?P<session_id>[a-zA-Z0-9_-]+)', array(
            'methods' => WP_REST_Server::READABLE,
            'callback' => array(__CLASS__, 'rest_poll_results_by_session'),
            'permission_callback' => '__return_true',
            'args' => array(
                'poll_id' => array(
                    'required' => true,
                    'validate_callback' => function ($p) {
                        return absint($p) > 0;
                    },
                ),
                'session_id' => array(
                    'required' => true,
                    'sanitize_callback' => 'sanitize_text_field',
                ),
                'user_id' => array(
                    'required' => false,
                    'sanitize_callback' => 'absint',
                ),
            ),
        ));
    }

    /**
     * GET poll-state: lazy-evaluated state for AUTO_RUN mode.
     *
     * @param WP_REST_Request $request
     * @return WP_REST_Response
     */
    public static function rest_poll_state(WP_REST_Request $request)
    {
        global $wpdb;
        $poll_id = absint($request->get_param('poll_id'));
        if ($poll_id <= 0) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Invalid poll_id',
            ), 400);
        }

        $table_items = $wpdb->prefix . 'twork_engagement_items';
        $item = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM $table_items WHERE id = %d AND type = 'poll'",
            $poll_id
        ), ARRAY_A);

        if (!$item) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Poll not found',
            ), 404);
        }

        $quiz_data = json_decode($item['quiz_data'], true);
        if (!is_array($quiz_data)) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Invalid poll config',
            ), 500);
        }

        $mode = strtoupper($quiz_data['poll_mode'] ?? 'MANUAL');
        $poll_duration_min = max(1, (int) ($quiz_data['poll_duration'] ?? 15));
        $result_duration_min = max(0, (int) ($quiz_data['result_display_duration'] ?? 1));

        $cycle_seconds = ($poll_duration_min + $result_duration_min) * 60;
        $voting_seconds = $poll_duration_min * 60;

        $poll_base_cost = isset($quiz_data['poll_base_cost']) ? max(0, (int) $quiz_data['poll_base_cost']) : 0;
        $reward_multiplier = isset($quiz_data['reward_multiplier']) ? max(0, (float) $quiz_data['reward_multiplier']) : 4;
        $require_confirmation = self::is_quiz_bool_true($quiz_data, 'require_confirmation', true);
        $allow_user_amount = self::is_quiz_bool_true($quiz_data, 'allow_user_amount', true);

        $bet_amount_step = self::resolve_bet_amount_step_for_quiz($quiz_data);

        // MANUAL_SESSION uses same session cycling as AUTO_RUN, so skip this early return
        if ($mode !== 'AUTO_RUN' && $mode !== 'MANUAL_SESSION') {
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
                    'poll_base_cost' => $poll_base_cost,
                    'reward_multiplier' => $reward_multiplier,
                    'require_confirmation' => $require_confirmation,
                    'allow_user_amount' => $allow_user_amount,
                    'bet_amount_step' => $bet_amount_step,
                ),
            ), 200);
        }

        $started_at = $quiz_data['started_at'] ?? $quiz_data['poll_actual_start_at'] ?? '';
        if (empty($started_at)) {
            $started_at = current_time('mysql');
            $quiz_data['started_at'] = $started_at;
            $wpdb->update(
                $table_items,
                array('quiz_data' => wp_json_encode($quiz_data)),
                array('id' => $poll_id),
                array('%s'),
                array('%d')
            );
        }

        $start_ts = strtotime($started_at);
        if ($start_ts === false) {
            $started_at = current_time('mysql');
            $quiz_data['started_at'] = $started_at;
            $wpdb->update(
                $table_items,
                array('quiz_data' => wp_json_encode($quiz_data)),
                array('id' => $poll_id),
                array('%s'),
                array('%d')
            );
            $start_ts = strtotime($started_at);
        }
        if ($start_ts === false) {
            $start_ts = time();
        }
        $now_ts = time();
        $elapsed = max(0, $now_ts - (int) $start_ts);

        $iteration = (int) floor($elapsed / $cycle_seconds);
        $cycle_start_ts = $start_ts + ($iteration * $cycle_seconds);
        $voting_ends_ts = $cycle_start_ts + $voting_seconds;
        $results_ends_ts = $cycle_start_ts + $cycle_seconds;

        $session_id = 's' . $iteration;

        if ($now_ts < $voting_ends_ts) {
            $state = 'ACTIVE';
            $ends_at = gmdate('Y-m-d\TH:i:s\Z', $voting_ends_ts);
        } elseif ($now_ts < $results_ends_ts) {
            $state = 'SHOWING_RESULTS';
            $ends_at = gmdate('Y-m-d\TH:i:s\Z', $results_ends_ts);
        } else {
            $state = 'ACTIVE';
            $iteration++;
            $session_id = 's' . $iteration;
            $cycle_start_ts = $start_ts + ($iteration * $cycle_seconds);
            $voting_ends_ts = $cycle_start_ts + $voting_seconds;
            $ends_at = gmdate('Y-m-d\TH:i:s\Z', $voting_ends_ts);
        }

        // Reliability guard:
        // Winner payout is normally triggered by /poll/results. If client timing skips it,
        // backend totals never increase. Trigger once here as well while showing results.
        if ($state === 'SHOWING_RESULTS' && $session_id !== '') {
            try {
                $distribution_request = new WP_REST_Request('GET');
                $distribution_request->set_param('poll_id', $poll_id);
                $distribution_request->set_param('session_id', $session_id);
                $distribution_request->set_param('user_id', 0);
                self::rest_poll_results_by_session($distribution_request);
            } catch (Exception $e) {
                error_log(
                    sprintf(
                        'TWork Poll Auto-Run: state-triggered payout failed. poll_id=%d session=%s err=%s',
                        (int) $poll_id,
                        (string) $session_id,
                        $e->getMessage()
                    )
                );
            }
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
                'poll_base_cost' => $poll_base_cost,
                'reward_multiplier' => $reward_multiplier,
                'require_confirmation' => $require_confirmation,
                'allow_user_amount' => $allow_user_amount,
                'bet_amount_step' => $bet_amount_step,
            ),
        ), 200);
    }

    /**
     * Single source of truth for bet_amount_step (must match reward math in poll results).
     *
     * @param array $quiz_data Decoded quiz_data from engagement item.
     * @return int Step in PNP (>= 1).
     */
    private static function resolve_bet_amount_step_for_quiz(array $quiz_data)
    {
        $poll_base_cost = isset($quiz_data['poll_base_cost']) ? max(0, (int) $quiz_data['poll_base_cost']) : 0;
        $bet_amount_step = 1000;
        if (isset($quiz_data['bet_amount_step'])) {
            $bet_amount_step = max(1, (int) $quiz_data['bet_amount_step']);
        } elseif ($poll_base_cost > 0) {
            // Back-compat: older polls may store step as a small "unit" number.
            // Example: poll_base_cost=1 => bet_amount_step=1000 (so user picks 1..N units => 1000..PNP).
            $bet_amount_step = (int) $poll_base_cost;
            if ($bet_amount_step > 0 && $bet_amount_step < 1000) {
                $bet_amount_step *= 1000;
            }
        }

        return $bet_amount_step;
    }

    /**
     * Normalize quiz_data boolean flags stored as true/1/"1" (default true when key absent).
     *
     * @param array  $quiz_data Decoded quiz_data.
     * @param string $key       Field name.
     * @param bool   $default_when_unset Default if key is missing.
     * @return bool
     */
    private static function is_quiz_bool_true(array $quiz_data, $key, $default_when_unset = true)
    {
        if (!array_key_exists($key, $quiz_data)) {
            return $default_when_unset;
        }
        $v = $quiz_data[ $key ];
        return $v === true || $v === 1 || $v === '1';
    }

    /**
     * Build per-option vote counts from interaction rows (comma-separated indices; each token counts once).
     *
     * @param array $rows       Rows from twork_user_interactions.
     * @param int   $num_options Number of poll options.
     * @return int[] Map option_index => vote count.
     */
    private static function aggregate_vote_counts(array $rows, $num_options)
    {
        $vote_counts = array();
        for ($i = 0; $i < $num_options; $i++) {
            $vote_counts[ $i ] = 0;
        }
        foreach ($rows as $row) {
            $value = trim($row['interaction_value'] ?? '');
            if ($value === '') {
                continue;
            }
            foreach (array_map('trim', explode(',', $value)) as $part) {
                if ($part !== '' && is_numeric($part)) {
                    $idx = (int) $part;
                    if ($idx >= 0 && $idx < $num_options) {
                        $vote_counts[ $idx ]++;
                    }
                }
            }
        }

        return $vote_counts;
    }

    /**
     * Stable idempotency key for poll winner ledger rows.
     *
     * @param int    $poll_id    Engagement item id.
     * @param string $session_id Session key (may be empty).
     * @param int    $user_id    WordPress user id.
     * @return string
     */
    private static function build_poll_winner_order_id($poll_id, $session_id, $user_id)
    {
        return 'engagement:poll:' . (int) $poll_id . ':session:' . $session_id . ':' . (int) $user_id;
    }

    /**
     * PNP credited to a winner for this row (user-amount vs fixed reward).
     *
     * @param array $row               Interaction row.
     * @param int   $winning_index     Winning option index.
     * @param int   $bet_amount_step   PNP per unit.
     * @param bool  $allow_user_amount User-amount mode.
     * @param int   $reward_amount     Fixed reward (PNP) when not user-amount.
     * @param float $reward_multiplier Multiplier for user-amount path.
     * @return int Non-negative reward PNP.
     */
    private static function calculate_user_poll_reward_amount(
        array $row,
        $winning_index,
        $bet_amount_step,
        $allow_user_amount,
        $reward_amount,
        $reward_multiplier
    ) {
        $user_bet_amount = self::resolve_bet_amount_for_winner($row, $winning_index);
        $user_bet_pnp = max(0, (int) $bet_amount_step) * max(1, (int) $user_bet_amount);
        if ($allow_user_amount) {
            return (int) round($user_bet_pnp * max(0.0, (float) $reward_multiplier));
        }

        return max(0, (int) $reward_amount);
    }

    /**
     * Read rewards_distributed; when lock is held, re-query for authoritative value.
     *
     * @param \wpdb  $wpdb          WordPress DB object.
     * @param string $table_rewards Full table name.
     * @param int    $poll_id       Poll id.
     * @param string $session_id    Session id.
     * @param bool   $lock_acquired Whether GET_LOCK succeeded for this connection.
     * @return string|null Raw column value from DB.
     */
    private static function get_poll_session_rewards_distributed_flag($wpdb, $table_rewards, $poll_id, $session_id, $lock_acquired)
    {
        $already = $wpdb->get_var(
            $wpdb->prepare(
                "SELECT rewards_distributed FROM $table_rewards WHERE poll_id = %d AND session_id = %s",
                $poll_id,
                $session_id
            )
        );
        if ($lock_acquired) {
            $already = $wpdb->get_var(
                $wpdb->prepare(
                    "SELECT rewards_distributed FROM $table_rewards WHERE poll_id = %d AND session_id = %s",
                    $poll_id,
                    $session_id
                )
            );
        }

        return $already;
    }

    /**
     * Award one winner; returns false if balance update appears to fail.
     *
     * @param object $rewards      {@see TWork_Rewards_System} instance.
     * @param int                  $uid          User id.
     * @param int                  $user_reward  PNP to credit.
     * @param string               $order_id     Idempotency key.
     * @param string               $description  Ledger description.
     * @param string               $item_title   Poll title.
     * @return bool True if award or silent credit reported success.
     */
    private static function award_poll_winner_via_rewards($rewards, $uid, $user_reward, $order_id, $description, $item_title)
    {
        global $wpdb;
        $new_bal = $rewards->award_engagement_points_to_user(
            $uid,
            $user_reward,
            $order_id,
            $description,
            'poll',
            $item_title
        );
        if ($new_bal <= 0) {
            $new_bal = $rewards->credit_engagement_points_silent($uid, $user_reward, $order_id, $description);
        }
        if ($new_bal > 0) {
            return true;
        }

        // Critical reliability: "balance <= 0" does not mean award failed.
        // Actual success criterion is the presence of the idempotent ledger row.
        if ($uid > 0 && $order_id !== '') {
            $table_points = $wpdb->prefix . 'twork_point_transactions';
            $table_ok = ($wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $table_points)) === $table_points);
            $exists = $table_ok ? $wpdb->get_var(
                $wpdb->prepare(
                    "SELECT id FROM $table_points WHERE user_id = %d AND order_id = %s LIMIT 1",
                    (int) $uid,
                    (string) $order_id
                )
            ) : null;
            if ($exists) {
                return true;
            }
            error_log(
                sprintf(
                    'TWork Poll Auto-Run: winner ledger row missing after award attempts. user_id=%d order_id=%s points=%d',
                    (int) $uid,
                    (string) $order_id,
                    (int) $user_reward
                )
            );
        }

        return false;
    }

    /**
     * Mark session rewards as distributed (idempotent replace).
     *
     * @param \wpdb  $wpdb          WordPress DB.
     * @param string $table_rewards Full rewards table name.
     * @param int    $poll_id       Poll id.
     * @param string $session_id    Session id.
     * @return void
     */
    private static function mark_poll_session_rewards_distributed($wpdb, $table_rewards, $poll_id, $session_id)
    {
        $wpdb->replace(
            $table_rewards,
            array(
                'poll_id' => $poll_id,
                'session_id' => $session_id,
                'rewards_distributed' => 1,
                'distributed_at' => current_time('mysql'),
            ),
            array('%d', '%s', '%d', '%s')
        );
    }

    /**
     * MySQL named locks are limited to 64 characters; keep names stable and collision-resistant.
     *
     * @param int    $poll_id Poll / engagement item id.
     * @param string $session_id Session key (may be empty for manual polls).
     * @return string Lock name (non-empty), at most POLL_REWARD_LOCK_MAX_NAME_LEN chars.
     */
    private static function build_poll_reward_lock_name($poll_id, $session_id)
    {
        $poll_id = (int) $poll_id;
        $hash = md5((string) $session_id);
        $name = 'twork_pr_' . $poll_id . '_' . $hash;
        if (strlen($name) > self::POLL_REWARD_LOCK_MAX_NAME_LEN) {
            $name = substr($name, 0, self::POLL_REWARD_LOCK_MAX_NAME_LEN);
        }

        return $name;
    }

    /**
     * True if interaction_value includes the winning option index (comma-separated indices allowed).
     *
     * @param string $interaction_value Raw DB value.
     * @param int    $winning_index Winning option index.
     * @return bool
     */
    private static function user_selected_winning_option($interaction_value, $winning_index)
    {
        $value = trim((string) $interaction_value);
        if ($value === '') {
            return false;
        }
        $winning_index = (int) $winning_index;
        foreach (array_map('trim', explode(',', $value)) as $part) {
            if ($part !== '' && is_numeric($part) && (int) $part === $winning_index) {
                return true;
            }
        }

        return false;
    }

    /**
     * Normalize poll option to object with text, media_url, media_type.
     * Supports legacy string options: "Option A" -> { text: "Option A", media_url: null, media_type: null }.
     *
     * @param mixed $opt Raw option (string or array)
     * @return array{text: string, media_url: string|null, media_type: string|null}
     */
    private static function normalize_option($opt)
    {
        if (is_array($opt)) {
            return array(
                'text' => isset($opt['text']) ? (string) $opt['text'] : (isset($opt[0]) ? (string) $opt[0] : ''),
                'media_url' => !empty($opt['media_url']) ? esc_url_raw($opt['media_url']) : null,
                'media_type' => !empty($opt['media_type']) ? sanitize_key($opt['media_type']) : null,
            );
        }
        return array(
            'text' => (string) $opt,
            'media_url' => null,
            'media_type' => null,
        );
    }

    /**
     * Resolve bet amount for reward calculation.
     * When bet_amount_per_option JSON exists and contains the winning index, use that amount.
     * Otherwise fall back to bet_amount.
     *
     * @param array $row DB row with bet_amount and optionally bet_amount_per_option
     * @param int   $winning_index The winning option index
     * @return int Amount to use for reward scaling (>= 1)
     */
    private static function resolve_bet_amount_for_winner($row, $winning_index)
    {
        $fallback = max(1, (int) ($row['bet_amount'] ?? 1));
        $raw = isset($row['bet_amount_per_option']) ? $row['bet_amount_per_option'] : null;
        if ($raw === '' || $raw === null) {
            return $fallback;
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return $fallback;
        }
        $key_str = (string) $winning_index;
        $key_int = (int) $winning_index;
        $raw_amt = null;
        if (array_key_exists($key_str, $decoded)) {
            $raw_amt = $decoded[ $key_str ];
        } elseif (array_key_exists($key_int, $decoded)) {
            $raw_amt = $decoded[ $key_int ];
        } else {
            return $fallback;
        }
        $amt = (int) $raw_amt;

        return $amt >= 1 ? $amt : $fallback;
    }

    /**
     * GET poll-results by session_id.
     * Returns ONLY the winning option's text and media (no vote counts) for minimalist media-focused UI.
     *
     * Poll options schema supports:
     * - Legacy: options = ["A", "B", "C"]
     * - Extended: options = [{ "text": "A", "media_url": "https://...", "media_type": "image"|"gif"|"video" }, ...]
     *
     * @param WP_REST_Request $request
     * @return WP_REST_Response
     */
    public static function rest_poll_results_by_session(WP_REST_Request $request)
    {
        global $wpdb;
        $poll_id = absint($request->get_param('poll_id'));
        $session_id = sanitize_text_field($request->get_param('session_id'));
        // Manual/schedule polls store interactions with session_id '' (REST path cannot be empty).
        // Flutter uses this token when poll/state returns empty current_session_id.
        if ($session_id === 'default' || $session_id === '_') {
            $session_id = '';
        }
        if (strlen($session_id) > self::POLL_SESSION_ID_MAX_LEN) {
            $session_id = substr($session_id, 0, self::POLL_SESSION_ID_MAX_LEN);
        }
        $requesting_user_id = absint($request->get_param('user_id'));

        $table_items = $wpdb->prefix . 'twork_engagement_items';
        $table_interactions = $wpdb->prefix . 'twork_user_interactions';

        $item = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM $table_items WHERE id = %d AND type = 'poll'",
            $poll_id
        ), ARRAY_A);

        if (!$item) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Poll not found',
            ), 404);
        }

        $quiz_data = json_decode($item['quiz_data'], true);
        if (!is_array($quiz_data)) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Invalid poll config',
            ), 500);
        }
        $raw_options = $quiz_data['options'] ?? array();
        if (!is_array($raw_options)) {
            $raw_options = array();
        }
        $num_options = count($raw_options);

        $rows = $wpdb->get_results(
            $wpdb->prepare(
                "SELECT user_id, interaction_value, bet_amount, bet_amount_per_option FROM $table_interactions WHERE item_id = %d AND session_id = %s",
                $poll_id,
                $session_id
            ),
            ARRAY_A
        );
        if (!is_array($rows)) {
            $rows = array();
        }

        $vote_counts = self::aggregate_vote_counts($rows, $num_options);

        $poll_mode = strtoupper((string) ($quiz_data['poll_mode'] ?? ''));
        $is_auto_run = ($poll_mode === 'AUTO_RUN');
        $is_manual_session = ($poll_mode === 'MANUAL_SESSION');

        // Determine winning index:
        // - AUTO_RUN: compute per-session winner from current session votes (highest votes)
        // - MANUAL_SESSION: use admin-set winner from session_resolutions, or wait if not resolved
        // - Other modes: honour explicit correct_index when present, otherwise fallback
        $winning_index = 0;
        $resolution_pending = false;

        if ($is_manual_session && !empty($session_id)) {
            // MANUAL_SESSION: Check if admin has resolved this session
            $session_resolutions = isset($quiz_data['session_resolutions']) && is_array($quiz_data['session_resolutions'])
                ? $quiz_data['session_resolutions']
                : array();
            
            if (isset($session_resolutions[$session_id]) && isset($session_resolutions[$session_id]['correct_index'])) {
                // Admin has set winner for this session
                $winning_index = (int) $session_resolutions[$session_id]['correct_index'];
            } else {
                // Session not yet resolved - return pending status
                $resolution_pending = true;
                $winning_index = -1;
            }
        } elseif ($is_auto_run) {
            // AUTO_RUN: winner is the option(s) with the highest vote count
            // for THIS session only. If multiple tie, pick one at random.
            $max_votes = 0;
            $candidates = array();
            foreach ($vote_counts as $idx => $count) {
                if ($count > $max_votes) {
                    $max_votes = $count;
                    $candidates = ($count > 0) ? array($idx) : array();
                } elseif ($count > 0 && $count === $max_votes) {
                    $candidates[] = $idx;
                }
            }

            if (!empty($candidates)) {
                // FIXED: Use deterministic hash instead of wp_rand to ensure all concurrent requests get the EXACT same winner
                $hash = md5($poll_id . '_' . $session_id);
                $hash_num = hexdec(substr($hash, 0, 8));
                $winning_index = $candidates[$hash_num % count($candidates)];
            } else {
                // No votes in this session:
                if ($num_options > 0) {
                    $hash = md5($poll_id . '_' . $session_id . '_fallback');
                    $hash_num = hexdec(substr($hash, 0, 8));
                    $winning_index = $hash_num % $num_options;
                } else {
                    $winning_index = 0;
                }
            }
        } else {
            // Non AUTO_RUN modes: prefer explicit correct_index when configured.
            $correct_index_from_item = null;
            if (isset($quiz_data['correct_index']) && (int) $quiz_data['correct_index'] >= 0) {
                $correct_index_from_item = (int) $quiz_data['correct_index'];
            }

            if ($correct_index_from_item !== null && $correct_index_from_item < $num_options) {
                $winning_index = $correct_index_from_item;
            } else {
                $options_with_votes = array();
                foreach ($vote_counts as $idx => $count) {
                    if ($count > 0) {
                        $options_with_votes[] = $idx;
                    }
                }
                if (!empty($options_with_votes)) {
                    $winning_index = $options_with_votes[array_rand($options_with_votes)];
                    // Persist resolved correct_index for manual polls so subsequent
                    // calls to results endpoint remain stable.
                    $quiz_data['correct_index'] = $winning_index;
                    $quiz_data['poll_correct_answer_mode'] = 'random';
                    $wpdb->update(
                        $table_items,
                        array('quiz_data' => wp_json_encode($quiz_data)),
                        array('id' => $poll_id),
                        array('%s'),
                        array('%d')
                    );
                } else {
                    $winning_index = 0;
                }
            }
        }

        $winning_option = null;
        if ($winning_index >= 0 && isset($raw_options[$winning_index])) {
            $opt = self::normalize_option($raw_options[$winning_index]);
            $winning_option = array(
                'text' => $opt['text'],
                'media_url' => $opt['media_url'],
                'media_type' => $opt['media_type'],
            );
        }

        /*
         * Winners = users whose selected answer matches the winning result.
         * - Credit real balance via sync_user_points() → wp_twork_point_transactions.
         * - Send 1 FCM notification per winner via award_engagement_points_to_user().
         * Idempotency: order_id = engagement:poll:{poll_id}:session:{session_id}:{user_id}.
         */
        // User Amount mode: reward = (user's bet on winning option, in PNP) × multiplier
        //   e.g. User bet 4,000 PNP on Option B, multiplier 4 → 4,000 × 4 = 16,000 PNP
        //   user_bet_amount = units (e.g. 4); user_bet_pnp = bet_amount_step × user_bet_amount = 4,000
        // Base Cost mode: fixed reward = poll_base_cost × reward_multiplier
        $effective_base = class_exists('TWork_Poll_PNP') ? TWork_Poll_PNP::get_effective_reward_base($quiz_data) : 0;
        $reward_multiplier = isset($quiz_data['reward_multiplier']) ? max(0, (float) $quiz_data['reward_multiplier']) : 4;
        $bet_amount_step = self::resolve_bet_amount_step_for_quiz($quiz_data);
        $allow_user_amount = self::is_quiz_bool_true($quiz_data, 'allow_user_amount', true);
        $reward_amount = ($effective_base > 0 && $reward_multiplier > 0) ? (int) round($effective_base * $reward_multiplier) : 0;
        if ($reward_amount <= 0) {
            $fallback_base = isset($quiz_data['poll_base_cost']) ? max(1, (int) $quiz_data['poll_base_cost']) : 1000;
            $reward_amount = (int) round($fallback_base * max(1, $reward_multiplier));
        }
        if ($reward_amount <= 0) {
            error_log(
                sprintf(
                    'TWork Poll Auto-Run: reward_amount still <= 0 after fallback; no payout. poll_id=%d mode=%s',
                    $poll_id,
                    $is_auto_run ? 'AUTO_RUN' : 'manual'
                )
            );
        }
        $item_title = $item['title'] ?? 'Poll #' . $poll_id;

        $user_won = false;
        $points_earned = 0;
        $current_balance = 0;

        if ($is_auto_run && $reward_amount > 0 && !class_exists('TWork_Rewards_System')) {
            error_log(
                sprintf(
                    'TWork Poll Auto-Run: TWork_Rewards_System not loaded — AUTO_RUN winner points not credited. poll_id=%d session=%s',
                    $poll_id,
                    $session_id
                )
            );
        }

        // Award points for AUTO_RUN and resolved MANUAL_SESSION polls
        if (($is_auto_run || ($is_manual_session && !$resolution_pending)) && $reward_amount > 0 && class_exists('TWork_Rewards_System')) {
            $rewards_inst = TWork_Rewards_System::get_instance();
            $rewards_inst->ensure_point_transactions_table_exists();
            $rewards_inst->ensure_poll_session_rewards_table_exists();
            $table_rewards = $wpdb->prefix . 'twork_poll_session_rewards';
            // Advisory lock prevents thundering-herd work, but payout must still run if lock cannot be obtained.
            $lock_name = self::build_poll_reward_lock_name($poll_id, $session_id);
            $lock_acquired = (bool) $wpdb->get_var($wpdb->prepare(
                'SELECT GET_LOCK(%s, %d)',
                $lock_name,
                self::POLL_REWARD_LOCK_TIMEOUT
            ));
            if (!$lock_acquired && defined('WP_DEBUG') && WP_DEBUG) {
                error_log(sprintf(
                    'TWork Poll Auto-Run: GET_LOCK not acquired; continuing idempotent payout without lock. poll_id=%d session=%s',
                    (int) $poll_id,
                    (string) $session_id
                ));
            }
            $already_distributed = self::get_poll_session_rewards_distributed_flag(
                $wpdb,
                $table_rewards,
                $poll_id,
                $session_id,
                $lock_acquired
            );
            try {
                $need_distribution = ($already_distributed === null || (int) $already_distributed !== 1);
                if ($need_distribution) {
                    $rewards = $rewards_inst;
                    $all_awards_succeeded = true;
                    $awarded_winner_count = 0;
                    foreach ($rows as $row) {
                        $value = trim($row['interaction_value'] ?? '');
                        if ($value === '' || !self::user_selected_winning_option($value, $winning_index)) {
                            continue;
                        }
                        $uid = (int) ($row['user_id'] ?? 0);
                        if ($uid <= 0) {
                            continue;
                        }
                        $user_reward = self::calculate_user_poll_reward_amount(
                            $row,
                            $winning_index,
                            $bet_amount_step,
                            $allow_user_amount,
                            $reward_amount,
                            $reward_multiplier
                        );
                        if ($user_reward < 1) {
                            $user_reward = max(1, (int) $reward_amount);
                        }

                        $order_id = self::build_poll_winner_order_id($poll_id, $session_id, $uid);
                        $description = sprintf('Poll winner: %s (+%d PNP)', $item_title, $user_reward);
                        
                        // CRITICAL: Award points to wp_twork_point_transactions (SAME table as deduction)
                        $balance_before_award = (int) $rewards->get_user_points_balance($uid);
                        $award_success = self::award_poll_winner_via_rewards($rewards, $uid, $user_reward, $order_id, $description, $item_title);
                        
                        if (!$award_success) {
                            $all_awards_succeeded = false;
                            error_log(sprintf(
                                'TWork Poll Auto-Run: CRITICAL - Winner award FAILED! poll_id=%d session=%s user=%d reward=%d order=%s',
                                $poll_id,
                                $session_id,
                                $uid,
                                $user_reward,
                                substr($order_id, 0, 60)
                            ));
                        } else {
                            $awarded_winner_count++;
                            $balance_after_award = (int) $rewards->get_user_points_balance($uid);
                            if (defined('WP_DEBUG') && WP_DEBUG) {
                                error_log(sprintf(
                                    'TWork Poll Auto-Run: Winner award SUCCESS — poll_id=%d session=%s user=%d reward=%d balance=%d→%d order=%s',
                                    $poll_id,
                                    $session_id,
                                    $uid,
                                    $user_reward,
                                    $balance_before_award,
                                    $balance_after_award,
                                    substr($order_id, 0, 50)
                                ));
                            }
                        }
                        if ($uid === $requesting_user_id) {
                            $user_won = true;
                            $points_earned = $user_reward;
                            $current_balance = (int) $rewards->get_user_points_balance($requesting_user_id);
                        }
                    }
                    if ($all_awards_succeeded && $awarded_winner_count > 0) {
                        self::mark_poll_session_rewards_distributed($wpdb, $table_rewards, $poll_id, $session_id);
                        $already_distributed = 1;
                    } elseif ($awarded_winner_count === 0 && defined('WP_DEBUG') && WP_DEBUG) {
                        error_log(sprintf(
                            'TWork Poll Auto-Run: no winner awards produced for session; not marking distributed. poll_id=%d session=%s rows=%d winning_index=%d',
                            (int) $poll_id,
                            (string) $session_id,
                            count($rows),
                            (int) $winning_index
                        ));
                    }
                }
            } catch (\Throwable $e) {
                error_log('TWork Poll Auto-Run: Exception during distribution: ' . $e->getMessage());
            } finally {
                if ($lock_acquired && $lock_name !== '') {
                    $wpdb->query($wpdb->prepare('SELECT RELEASE_LOCK(%s)', $lock_name));
                }
            }
            // Make sure the code below (which populates JSON response for late clients) is OUTSIDE the try-finally block:
            if ($already_distributed !== null && (int) $already_distributed === 1 && $requesting_user_id > 0) {
                // Prior request distributed rewards; still return user_won for client popup + sync.
                foreach ($rows as $row) {
                    if ((int) ($row['user_id'] ?? 0) !== $requesting_user_id) {
                        continue;
                    }
                    $value = trim($row['interaction_value'] ?? '');
                    if ($value === '' || !self::user_selected_winning_option($value, $winning_index)) {
                        continue;
                    }
                    $user_won = true;
                    $points_earned = self::calculate_user_poll_reward_amount(
                        $row,
                        $winning_index,
                        $bet_amount_step,
                        $allow_user_amount,
                        $reward_amount,
                        $reward_multiplier
                    );
                    $current_balance = (int) TWork_Rewards_System::get_instance()->get_user_points_balance($requesting_user_id);
                    break;
                }
            }
        } elseif (!$is_auto_run && $reward_amount > 0) {
            if (class_exists('TWork_Rewards_System')) {
                $rewards_inst = TWork_Rewards_System::get_instance();
                $rewards_inst->ensure_point_transactions_table_exists();
                $rewards_inst->ensure_poll_session_rewards_table_exists();
            }
            $table_rewards = $wpdb->prefix . 'twork_poll_session_rewards';
            $lock_name = self::build_poll_reward_lock_name($poll_id, $session_id);
            $lock_acquired = (bool) $wpdb->get_var($wpdb->prepare(
                'SELECT GET_LOCK(%s, %d)',
                $lock_name,
                self::POLL_REWARD_LOCK_TIMEOUT
            ));
            try {
                $already_distributed = self::get_poll_session_rewards_distributed_flag(
                    $wpdb,
                    $table_rewards,
                    $poll_id,
                    $session_id,
                    $lock_acquired
                );
                $use_rewards_system = class_exists('TWork_Rewards_System');
                $use_pnp_fallback = class_exists('TWork_Poll_PNP');
                $need_manual_distribution = ($already_distributed === null || (int) $already_distributed !== 1);

                if (($use_rewards_system || $use_pnp_fallback) && $need_manual_distribution) {
                    $manual_all_succeeded = true;
                    foreach ($rows as $row) {
                        $value = trim($row['interaction_value'] ?? '');
                        if ($value === '' || !self::user_selected_winning_option($value, $winning_index)) {
                            continue;
                        }
                        $uid = (int) ($row['user_id'] ?? 0);
                        if ($uid <= 0) {
                            continue;
                        }
                        $user_reward = self::calculate_user_poll_reward_amount(
                            $row,
                            $winning_index,
                            $bet_amount_step,
                            $allow_user_amount,
                            $reward_amount,
                            $reward_multiplier
                        );
                        if ($user_reward < 1) {
                            $user_reward = max(1, (int) $reward_amount);
                        }

                        if ($use_rewards_system) {
                            $rewards = TWork_Rewards_System::get_instance();
                            $order_id = self::build_poll_winner_order_id($poll_id, $session_id, $uid);
                            $description = sprintf('Poll winner: %s (+%d PNP)', $item_title, $user_reward);
                            
                            // CRITICAL: Award points to wp_twork_point_transactions (SAME table as deduction)
                            $balance_before = (int) $rewards->get_user_points_balance($uid);
                            $award_success = self::award_poll_winner_via_rewards($rewards, $uid, $user_reward, $order_id, $description, $item_title);
                            
                            if (!$award_success) {
                                $manual_all_succeeded = false;
                                error_log(sprintf(
                                    'TWork Poll Auto-Run: CRITICAL - Manual poll winner award FAILED! poll_id=%d session=%s user=%d reward=%d order=%s',
                                    $poll_id,
                                    $session_id,
                                    $uid,
                                    $user_reward,
                                    substr($order_id, 0, 60)
                                ));
                            } else {
                                $balance_after = (int) $rewards->get_user_points_balance($uid);
                                if (defined('WP_DEBUG') && WP_DEBUG) {
                                    error_log(sprintf(
                                        'TWork Poll Auto-Run: Manual poll winner award SUCCESS — poll_id=%d session=%s user=%d reward=%d balance=%d→%d',
                                        $poll_id,
                                        $session_id,
                                        $uid,
                                        $user_reward,
                                        $balance_before,
                                        $balance_after
                                    ));
                                }
                            }
                        } else {
                            $pnp_order = self::build_poll_winner_order_id($poll_id, $session_id, $uid);
                            $pnp_desc = sprintf('Poll winner: %s (+%d PNP)', $item_title, $user_reward);
                            $balance_before = (int) TWork_Poll_PNP::get_user_pnp($uid);
                            $new_balance = TWork_Poll_PNP::update_user_pnp($uid, $user_reward, $pnp_order, $pnp_desc);
                            if (defined('WP_DEBUG') && WP_DEBUG) {
                                error_log(sprintf(
                                    'TWork Poll Auto-Run: Manual poll winner PNP award — poll_id=%d user=%d reward=%d balance=%d→%d',
                                    $poll_id,
                                    $uid,
                                    $user_reward,
                                    $balance_before,
                                    (int) $new_balance
                                ));
                            }
                        }
                    }
                    if ($manual_all_succeeded) {
                        self::mark_poll_session_rewards_distributed($wpdb, $table_rewards, $poll_id, $session_id);
                    }
                }
            } finally {
                if ($lock_acquired && $lock_name !== '') {
                    $wpdb->query($wpdb->prepare('SELECT RELEASE_LOCK(%s)', $lock_name));
                }
            }
            // Manual/schedule: populate user_won for JSON when caller passes user_id.
            if ($requesting_user_id > 0 && $reward_amount > 0 && !$user_won) {
                foreach ($rows as $row) {
                    if ((int) ($row['user_id'] ?? 0) !== $requesting_user_id) {
                        continue;
                    }
                    $value = trim($row['interaction_value'] ?? '');
                    if ($value === '' || !self::user_selected_winning_option($value, $winning_index)) {
                        continue;
                    }
                    $user_won = true;
                    $points_earned = self::calculate_user_poll_reward_amount(
                        $row,
                        $winning_index,
                        $bet_amount_step,
                        $allow_user_amount,
                        $reward_amount,
                        $reward_multiplier
                    );
                    $current_balance = class_exists('TWork_Rewards_System')
                        ? (int) TWork_Rewards_System::get_instance()->get_user_points_balance($requesting_user_id)
                        : (class_exists('TWork_Poll_PNP') ? (int) TWork_Poll_PNP::get_user_pnp($requesting_user_id) : 0);
                    break;
                }
            }
        }

        $response_data = array(
            'session_id' => $session_id,
            'winning_option' => $winning_option,
            'resolution_pending' => $resolution_pending,
        );
        if ($requesting_user_id > 0) {
            $response_data['user_won'] = $user_won;
            $response_data['points_earned'] = $points_earned;
            $response_data['current_balance'] = $current_balance;
        }
        
        // MANUAL_SESSION: Include resolution info if available
        if ($is_manual_session && !empty($session_id)) {
            $session_resolutions = isset($quiz_data['session_resolutions']) && is_array($quiz_data['session_resolutions'])
                ? $quiz_data['session_resolutions']
                : array();
            if (isset($session_resolutions[$session_id])) {
                $response_data['resolution_mode'] = $session_resolutions[$session_id]['mode'] ?? 'manual';
                $response_data['resolved_at'] = $session_resolutions[$session_id]['resolved_at'] ?? null;
            }
        }

        return new WP_REST_Response(array(
            'success' => true,
            'data' => $response_data,
        ), 200);
    }
}
