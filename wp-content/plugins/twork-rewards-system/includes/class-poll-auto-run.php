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
        $require_confirmation = !isset($quiz_data['require_confirmation']) || $quiz_data['require_confirmation'] === true
            || $quiz_data['require_confirmation'] === 1 || $quiz_data['require_confirmation'] === '1';
        $allow_user_amount = !isset($quiz_data['allow_user_amount']) || $quiz_data['allow_user_amount'] === true
            || $quiz_data['allow_user_amount'] === 1 || $quiz_data['allow_user_amount'] === '1';

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

        if (!$item) {
            return new WP_REST_Response(array(
                'success' => false,
                'message' => 'Poll not found',
            ), 404);
        }

        $quiz_data = json_decode($item['quiz_data'], true);
        $raw_options = $quiz_data['options'] ?? array();
        $num_options = count($raw_options);

        $vote_counts = array();
        for ($i = 0; $i < $num_options; $i++) {
            $vote_counts[$i] = 0;
        }

        $rows = $wpdb->get_results($wpdb->prepare(
            "SELECT user_id, interaction_value, bet_amount, bet_amount_per_option FROM $table_interactions WHERE item_id = %d AND session_id = %s",
            $poll_id,
            $session_id
        ), ARRAY_A);

        foreach ($rows as $row) {
            $value = trim($row['interaction_value'] ?? '');
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

        // Determine winning index:
        // - AUTO_RUN: optional transient lock, else admin override (auto_run_override_index),
        //   else pure random (equal chance per option, vote counts ignored); ignores correct_index.
        // - Other modes: honour explicit correct_index when present, otherwise
        //   fall back to vote-based winner (and persist for future calls).
        $winning_index = 0;

        if ($is_auto_run) {
            $transient_key = 'twork_auto_run_winner_' . (int) $poll_id . '_' . md5((string) $session_id);
            $saved_winner = get_transient($transient_key);
            if ($saved_winner !== false) {
                $winning_index = (int) $saved_winner;
            } else {
                $override_index = isset($quiz_data['auto_run_override_index']) ? (int) $quiz_data['auto_run_override_index'] : -1;

                // 1. CHECK IF ADMIN TRIGGERED A LIVE OVERRIDE
                if ($override_index >= 0 && $override_index < $num_options) {
                    $winning_index = $override_index;
                } else {
                    // 2. PURE RANDOM BEHAVIOR (True Probability)
                    // Ignore vote counts. Give every option an equal chance to win.
                    if ($num_options > 0) {
                        $hash = md5($poll_id . '_' . $session_id . '_true_random');
                        $hash_num = hexdec(substr($hash, 0, 8));
                        $winning_index = $hash_num % $num_options;
                    } else {
                        $winning_index = 0; // Fallback if no options exist
                    }
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

        // User Amount mode: reward = (user's bet on winning option, in PNP) × multiplier
        //   e.g. User bet 4,000 PNP on Option B, multiplier 4 → 4,000 × 4 = 16,000 PNP
        //   user_bet_amount = units (e.g. 4); user_bet_pnp = bet_amount_step × user_bet_amount = 4,000
        // Base Cost mode: fixed reward = poll_base_cost × reward_multiplier
        $effective_base = class_exists('TWork_Poll_PNP') ? TWork_Poll_PNP::get_effective_reward_base($quiz_data) : 0;
        $reward_multiplier = isset($quiz_data['reward_multiplier']) ? max(0, (float) $quiz_data['reward_multiplier']) : 4;
        $bet_amount_step = isset($quiz_data['bet_amount_step']) ? max(1, (int) $quiz_data['bet_amount_step']) : 1000;
        $allow_user_amount = !isset($quiz_data['allow_user_amount']) || $quiz_data['allow_user_amount'] === true
            || $quiz_data['allow_user_amount'] === 1 || $quiz_data['allow_user_amount'] === '1';
        $reward_amount = ($effective_base > 0 && $reward_multiplier > 0) ? (int) round($effective_base * $reward_multiplier) : 0;
        $item_title = $item['title'] ?? 'Poll #' . $poll_id;

        $user_won = false;
        $points_earned = 0;
        $current_balance = 0;

        if ($is_auto_run && $reward_amount > 0 && class_exists('TWork_Rewards_System')) {
            $table_rewards = $wpdb->prefix . 'twork_poll_session_rewards';
            $already_distributed = $wpdb->get_var($wpdb->prepare(
                "SELECT rewards_distributed FROM $table_rewards WHERE poll_id = %d AND session_id = %s",
                $poll_id,
                $session_id
            ));
            if ($already_distributed === null || (int) $already_distributed !== 1) {
                    $rewards = TWork_Rewards_System::get_instance();
                foreach ($rows as $row) {
                    $value = trim($row['interaction_value'] ?? '');
                    if ($value === '') {
                        continue;
                    }
                    $voted_winning = false;
                    foreach (array_map('trim', explode(',', $value)) as $part) {
                        if ($part !== '' && is_numeric($part) && (int) $part === $winning_index) {
                            $voted_winning = true;
                            break;
                        }
                    }
                    if ($voted_winning) {
                        $uid = (int) ($row['user_id'] ?? 0);
                        if ($uid > 0) {
                            // User Amount: reward = (PNP user bet on winning option) × multiplier
                            // user_bet_amount = units; user_bet_pnp = bet_amount_step × user_bet_amount
                            $user_bet_amount = self::resolve_bet_amount_for_winner($row, $winning_index);
                            $user_bet_pnp = $bet_amount_step * $user_bet_amount;
                            $user_reward = $allow_user_amount
                                ? (int) round($user_bet_pnp * $reward_multiplier)
                                : $reward_amount;

                            $order_id = 'engagement:poll:' . $poll_id . ':session:' . $session_id . ':' . $uid;
                            $description = sprintf('Poll winner: %s (+%d PNP)', $item_title, $user_reward);
                            $new_bal = $rewards->award_engagement_points_to_user(
                                $uid,
                                $user_reward,
                                $order_id,
                                $description,
                                'poll',
                                $item_title
                            );
                            if ($uid === $requesting_user_id) {
                                $user_won = true;
                                $points_earned = $user_reward;
                                $current_balance = $new_bal;
                            }
                        }
                    }
                }
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
            } elseif ($requesting_user_id > 0) {
                // Award already done (by main plugin); still return user_won for client popup + sync
                foreach ($rows as $row) {
                    if ((int) ($row['user_id'] ?? 0) !== $requesting_user_id) continue;
                    $value = trim($row['interaction_value'] ?? '');
                    if ($value === '') continue;
                        foreach (array_map('trim', explode(',', $value)) as $part) {
                        if ($part !== '' && is_numeric($part) && (int) $part === $winning_index) {
                            $user_won = true;
                            $user_bet_amount = self::resolve_bet_amount_for_winner($row, $winning_index);
                            $user_bet_pnp = $bet_amount_step * $user_bet_amount;
                            $points_earned = $allow_user_amount
                                ? (int) round($user_bet_pnp * $reward_multiplier)
                                : $reward_amount;
                            $current_balance = class_exists('TWork_Poll_PNP') ? (int) TWork_Poll_PNP::get_user_pnp($requesting_user_id) : 0;
                            break 2;
                        }
                    }
                }
            }
        } elseif (!$is_auto_run && $reward_amount > 0) {
            $table_rewards = $wpdb->prefix . 'twork_poll_session_rewards';
            $already_distributed = $wpdb->get_var($wpdb->prepare(
                "SELECT rewards_distributed FROM $table_rewards WHERE poll_id = %d AND session_id = %s",
                $poll_id,
                $session_id
            ));
            $use_rewards_system = class_exists('TWork_Rewards_System');
            $use_pnp_fallback = class_exists('TWork_Poll_PNP');

            if (($use_rewards_system || $use_pnp_fallback) &&
                ($already_distributed === null || (int) $already_distributed !== 1)) {
                foreach ($rows as $row) {
                    $value = trim($row['interaction_value'] ?? '');
                    if ($value === '') continue;
                    $voted_winning = false;
                    foreach (array_map('trim', explode(',', $value)) as $part) {
                        if ($part !== '' && is_numeric($part) && (int) $part === $winning_index) {
                            $voted_winning = true;
                            break;
                        }
                    }
                    if ($voted_winning) {
                        $uid = (int) ($row['user_id'] ?? 0);
                        if ($uid > 0) {
                            $user_bet_amount = self::resolve_bet_amount_for_winner($row, $winning_index);
                            $user_bet_pnp = $bet_amount_step * $user_bet_amount;
                            $user_reward = $allow_user_amount
                                ? (int) round($user_bet_pnp * $reward_multiplier)
                                : $reward_amount;

                            if ($use_rewards_system) {
                                $rewards = TWork_Rewards_System::get_instance();
                                $order_id = 'engagement:poll:' . $poll_id . ':session:' . $session_id . ':' . $uid;
                                $description = sprintf('Poll winner: %s (+%d PNP)', $item_title, $user_reward);
                                $rewards->award_engagement_points_to_user(
                                    $uid,
                                    $user_reward,
                                    $order_id,
                                    $description,
                                    'poll',
                                    $item_title
                                );
                            } else {
                                TWork_Poll_PNP::update_user_pnp($uid, $user_reward);
                            }
                        }
                    }
                }
                $wpdb->replace($table_rewards, array(
                    'poll_id' => $poll_id, 'session_id' => $session_id,
                    'rewards_distributed' => 1, 'distributed_at' => current_time('mysql'),
                ), array('%d', '%s', '%d', '%s'));
            }
            // Manual/schedule: award path never set user_won for JSON — client needs it for winner popup.
            if ( $requesting_user_id > 0 && $reward_amount > 0 && ! $user_won ) {
                foreach ( $rows as $row ) {
                    if ( (int) ( $row['user_id'] ?? 0 ) !== $requesting_user_id ) {
                        continue;
                    }
                    $value = trim( $row['interaction_value'] ?? '' );
                    if ( $value === '' ) {
                        continue;
                    }
                    foreach ( array_map( 'trim', explode( ',', $value ) ) as $part ) {
                        if ( $part !== '' && is_numeric( $part ) && (int) $part === $winning_index ) {
                            $user_won     = true;
                            $user_bet_amount = self::resolve_bet_amount_for_winner($row, $winning_index);
                            $user_bet_pnp = $bet_amount_step * $user_bet_amount;
                            $points_earned = $allow_user_amount
                                ? (int) round($user_bet_pnp * $reward_multiplier)
                                : $reward_amount;
                            $current_balance = class_exists( 'TWork_Poll_PNP' )
                                ? (int) TWork_Poll_PNP::get_user_pnp( $requesting_user_id )
                                : 0;
                            break 2;
                        }
                    }
                }
            }
        }

        $response_data = array(
            'session_id' => $session_id,
            'winning_option' => $winning_option,
        );
        if ($requesting_user_id > 0) {
            $response_data['user_won'] = $user_won;
            $response_data['points_earned'] = $points_earned;
            $response_data['current_balance'] = $current_balance;
        }

        return new WP_REST_Response(array(
            'success' => true,
            'data' => $response_data,
        ), 200);
    }
}
