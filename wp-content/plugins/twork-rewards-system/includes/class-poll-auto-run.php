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
 */
class TWork_Poll_Auto_Run {

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
            'permission_callback' => array(TWork_Rewards_System::get_instance(), 'rest_permission_user_or_admin'),
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
            'permission_callback' => array(TWork_Rewards_System::get_instance(), 'rest_permission_user_or_admin'),
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

        if (!$item || !is_array($item)) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Poll not found',
            ), 404);
        }

        $quiz_data = json_decode($item['quiz_data'] ?? '', true);
        if (!is_array($quiz_data)) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Invalid poll config',
            ), 500);
        }

        $mode = strtoupper((string) ($quiz_data['poll_mode'] ?? 'MANUAL'));
        $poll_duration_min = max(1, (int) ($quiz_data['poll_duration'] ?? 15));
        // Result phase: total seconds (canonical). Legacy minute-only values resolved in TWork_Rewards_System.
        $result_display_sec = class_exists('TWork_Rewards_System')
            ? TWork_Rewards_System::resolve_result_display_duration_seconds($quiz_data)
            : max(0, (int) ($quiz_data['result_display_duration'] ?? 1)) * 60;

        // Cycle = voting window (minutes→seconds) + result phase (seconds).
        $voting_seconds = $poll_duration_min * 60;
        $cycle_seconds = $voting_seconds + $result_display_sec;

        $poll_base_cost = isset($quiz_data['poll_base_cost']) ? max(0, (int) $quiz_data['poll_base_cost']) : 0;
        $reward_multiplier = isset($quiz_data['reward_multiplier']) ? max(0, (float) $quiz_data['reward_multiplier']) : 4;
        $req_conf = $quiz_data['require_confirmation'] ?? null;
        $require_confirmation = $req_conf === null || $req_conf === true
            || $req_conf === 1 || $req_conf === '1';
        $allow_amt = $quiz_data['allow_user_amount'] ?? null;
        $allow_user_amount = $allow_amt === null || $allow_amt === true
            || $allow_amt === 1 || $allow_amt === '1';

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

        if ($mode !== 'AUTO_RUN') {
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
                    'result_display_duration_seconds' => $result_display_sec,
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
        $now_ts = time();
        $elapsed = max(0, $now_ts - $start_ts);

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

        // Throttled server tick: run AUTO_RUN process (awards, cycle reset) when any client requests state.
        // Supplements WP-Cron so narrow award windows are not missed when the app is backgrounded/closed.
        if (class_exists('TWork_Rewards_System')) {
            try {
                TWork_Rewards_System::get_instance()->twork_rewards_throttled_auto_run_process($poll_id, 45);
            } catch (\Throwable $e) {
                if (defined('WP_DEBUG') && WP_DEBUG) {
                    error_log(
                        sprintf(
                            '[TWork auto_run] rest_poll_state tick poll_id=%d err=%s',
                            (int) $poll_id,
                            $e->getMessage()
                        )
                    );
                }
            }
        }

        // Old Code:        // (no throttled twork_rewards_throttled_auto_run_process — relied only on WP-Cron + feed paths)

        return new WP_REST_Response(array(
            'success' => true,
            'data' => array(
                'state' => $state,
                'current_session_id' => $session_id,
                'ends_at' => $ends_at,
                'poll_duration' => $poll_duration_min,
                'result_display_duration_seconds' => $result_display_sec,
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
     * Normalize poll option to object with text, media_url, media_type.
     * Supports legacy string options: "Option A" -> { text: "Option A", media_url: null, media_type: null }.
     *
     * @param mixed $opt Raw option (string or array)
     * @return array{text: string, media_url: string|null, media_type: string|null}
     */
    private static function normalize_option($opt)
    {
        if (is_array($opt)) {
            $media_url_raw = $opt['media_url'] ?? null;
            $media_type_raw = $opt['media_type'] ?? null;

            return array(
                'text' => isset($opt['text']) ? (string) $opt['text'] : (isset($opt[0]) ? (string) $opt[0] : ''),
                'media_url' => ($media_url_raw !== null && $media_url_raw !== '' && is_string($media_url_raw))
                    ? esc_url_raw($media_url_raw)
                    : null,
                'media_type' => ($media_type_raw !== null && $media_type_raw !== '' && (is_string($media_type_raw) || is_numeric($media_type_raw)))
                    ? sanitize_key((string) $media_type_raw)
                    : null,
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
        if (!is_array($row)) {
            $row = array();
        }
        $fallback = max(1, (int) ($row['bet_amount'] ?? 1));
        $raw = $row['bet_amount_per_option'] ?? null;
        if ($raw === '' || $raw === null) {
            return $fallback;
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded) || !isset($decoded[(string) $winning_index])) {
            return $fallback;
        }
        $amt = (int) $decoded[(string) $winning_index];
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
        if ( $session_id === 'default' || $session_id === '_' ) {
            $session_id = '';
        }
        $requesting_user_id = absint($request->get_param('user_id'));

        $table_items = $wpdb->prefix . 'twork_engagement_items';
        $table_interactions = $wpdb->prefix . 'twork_user_interactions';

        $item = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM $table_items WHERE id = %d AND type = 'poll'",
            $poll_id
        ), ARRAY_A);

        if (!$item || !is_array($item)) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Poll not found',
            ), 404);
        }

        $quiz_data = json_decode($item['quiz_data'] ?? '', true);
        if (!is_array($quiz_data)) {
            $quiz_data = array();
        }

        $raw_options = $quiz_data['options'] ?? array();
        if (!is_array($raw_options)) {
            $raw_options = array();
        }
        $num_options = count($raw_options);

        $vote_counts = array();
        for ($i = 0; $i < $num_options; $i++) {
            $vote_counts[$i] = 0;
        }

        // SELECT * avoids undefined keys on older schemas missing bet_amount / bet_amount_per_option columns.
        $rows = $wpdb->get_results($wpdb->prepare(
            "SELECT * FROM $table_interactions WHERE item_id = %d AND session_id = %s",
            $poll_id,
            $session_id
        ), ARRAY_A);
        if (!is_array($rows)) {
            $rows = array();
        }

        foreach ($rows as $row) {
            if (!is_array($row)) {
                continue;
            }
            $value = trim((string) ($row['interaction_value'] ?? ''));
            if ($value === '') {
                continue;
            }
            foreach (array_map('trim', explode(',', $value)) as $part) {
                if ($part !== '' && is_numeric($part)) {
                    $idx = (int) $part;
                    if ($idx >= 0 && $idx < $num_options) {
                        $vote_counts[$idx]++;
                    }
                }
            }
        }

        $poll_mode = strtoupper((string) ($quiz_data['poll_mode'] ?? ''));
        $is_auto_run = ($poll_mode === 'AUTO_RUN');

        $correct_index = isset($quiz_data['correct_index']) ? (int) $quiz_data['correct_index'] : -1;

        // Determine winning index:
        // - AUTO_RUN: optional transient lock; else DB correct_index (from process_auto_run_poll) or
        //   admin override only — never random_int here (cron resolves random winners).
        // - Other modes: honour explicit correct_index when present, otherwise
        //   fall back to vote-based winner (and persist for future calls).
        $winning_index = 0;

        if ($is_auto_run) {
            $force_winner_raw = isset($quiz_data['auto_run_override_index']) ? (int) $quiz_data['auto_run_override_index'] : -1;
            $force_winner_effective = ($force_winner_raw < 0) ? 'random' : (string) $force_winner_raw;
            if (defined('WP_DEBUG') && WP_DEBUG) {
                error_log(sprintf(
                    '[twork poll-auto-run] poll_id=%d pre-resolution force_winner(auto_run_override_index)=%s raw=%d correct_index=%d',
                    (int) $poll_id,
                    $force_winner_effective,
                    $force_winner_raw,
                    $correct_index
                ));
            }

            $transient_key = 'twork_auto_run_winner_' . (int) $poll_id . '_' . md5((string) $session_id);
            $saved_winner = get_transient($transient_key);
            if ($saved_winner !== false) {
                $winning_index = (int) $saved_winner;
            } else {
                if ($correct_index < 0) {
                    $override_index = isset($quiz_data['auto_run_override_index']) ? (int) $quiz_data['auto_run_override_index'] : -1;
                    if ($override_index >= 0 && $override_index < $num_options) {
                        $correct_index = $override_index;
                    } else {
                        $correct_index = -1; // Keep it as -1. Wait for cron job to resolve it!
                    }
                }
                if ($correct_index >= 0 && $correct_index < $num_options) {
                    $winning_index = $correct_index;
                } else {
                    $winning_index = -1;
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

        // Old Code: Payout on GET (client-dependent) — [award_poll_winner_points] was called only when the app hit this REST route.
        // Now poll resolution + [award_poll_winner_points] run from WP-Cron (see twork_rewards_auto_run_poll_cron in twork-rewards-system.php).
        // Old Code:        // PROFESSIONAL FIX: Eliminate Race Conditions & Ghost Balances
        // Old Code:        if ($winning_index >= 0 && class_exists('TWork_Rewards_System')) {
        // Old Code:            TWork_Rewards_System::get_instance()->award_poll_winner_points($poll_id, $session_id);
        // Old Code:            $rows = $wpdb->get_results($wpdb->prepare(
        // Old Code:                "SELECT * FROM $table_interactions WHERE item_id = %d AND session_id = %s",
        // Old Code:                $poll_id,
        // Old Code:                $session_id
        // Old Code:            ), ARRAY_A);
        // Old Code:            if (!is_array($rows)) $rows = array();
        // Old Code:        }
        // [$rows] still from query above; Cron updates DB for poll awards — not on this GET.

        $winning_option = null;
        if ($winning_index >= 0 && isset($raw_options[$winning_index])) {
            $opt = self::normalize_option($raw_options[$winning_index]);
            $winning_option = array(
                'text' => $opt['text'],
                'media_url' => $opt['media_url'],
                'media_type' => $opt['media_type'],
            );
        }

        $user_won = false;
        $points_earned = 0;
        $current_balance = 0;
        $user_bet_pnp = 0;
        $user_detailed_bets = array(); // NEW: Store exact breakdown

        if ($requesting_user_id > 0 && $winning_index >= 0) {
            foreach ($rows as $row) {
                if (!is_array($row)) continue;
                if ((int) ($row['user_id'] ?? 0) !== $requesting_user_id) continue;

                if (class_exists('TWork_Rewards_System') && method_exists('TWork_Rewards_System', 'calculate_poll_user_bet_amount_pnp')) {
                    $user_bet_pnp = (int) TWork_Rewards_System::calculate_poll_user_bet_amount_pnp($quiz_data, $row);
                }
                
                $value = trim((string) ($row['interaction_value'] ?? ''));
                if ($value === '') continue;

                // Per-option **Amount** units (1, 2, 3…), not PNP — clients display the raw multiplier.
                $bet_amt = isset($row['bet_amount']) ? max(1, (int) $row['bet_amount']) : 1;
                $per_opt_json = isset($row['bet_amount_per_option']) ? json_decode($row['bet_amount_per_option'], true) : array();
                $allow_user_amount = !isset($quiz_data['allow_user_amount']) || $quiz_data['allow_user_amount'] === true || $quiz_data['allow_user_amount'] === 1 || $quiz_data['allow_user_amount'] === '1';

                $selected_parts = array_unique(array_map('trim', explode(',', $value))); // Prevent duplicates
                foreach ($selected_parts as $part) {
                    if ($part !== '' && is_numeric($part)) {
                        $idx = (int) $part;
                        if (isset($raw_options[$idx])) {
                            $opt_label = self::normalize_option($raw_options[$idx])['text'];
                            if ($allow_user_amount) {
                                if (is_array($per_opt_json) && isset($per_opt_json[(string)$idx])) {
                                    $units = max(1, (int)$per_opt_json[(string)$idx]);
                                    $user_detailed_bets[$opt_label] = $units;
                                } else {
                                    $user_detailed_bets[$opt_label] = $bet_amt;
                                }
                            } else {
                                $user_detailed_bets[$opt_label] = 1;
                            }
                        }
                    }
                }
                
                foreach ($selected_parts as $part) {
                    if ($part !== '' && is_numeric($part) && (int) $part === $winning_index) {
                        $user_won = true;
                        
                        // Fetch EXACT points awarded from DB
                        $points_earned = isset($row['points_awarded']) ? (int) $row['points_awarded'] : 0;
                            
                        // Fetch TRUE real-time balance
                        if (class_exists('TWork_Points_System')) {
                            $pts = TWork_Points_System::get_instance();
                            $current_balance = method_exists($pts, 'get_user_point_balance') ? (int) $pts->get_user_point_balance($requesting_user_id) : 0;
                        } else if (class_exists('TWork_Poll_PNP')) {
                            $current_balance = (int) TWork_Poll_PNP::get_user_pnp($requesting_user_id);
                        } else {
                            $current_balance = (int) get_user_meta($requesting_user_id, 'points_balance', true);
                        }
                        break;
                    }
                }
                break; // Process only the exact row for this user
            }
        }

        $response_data = array(
            'session_id' => $session_id,
            'winning_option' => $winning_option,
            'winning_index' => (int) $winning_index,
        );
        if ($requesting_user_id > 0) {
            $response_data['user_won'] = $user_won;
            $response_data['points_earned'] = $points_earned;
            $response_data['current_balance'] = $current_balance;
            $response_data['user_bet_pnp'] = (int) $user_bet_pnp;
            $response_data['user_detailed_bets'] = $user_detailed_bets; // SEND EXACT MAP TO APP
        }

        return new WP_REST_Response(array(
            'success' => true,
            'data' => $response_data,
        ), 200);
    }
}
