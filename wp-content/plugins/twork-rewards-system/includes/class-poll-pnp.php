<?php
/**
 * PNP Virtual Currency Helpers for Poll Betting System.
 * Modular design: uses Actual Point Balance (twork-points-system) when available,
 * otherwise falls back to legacy _user_pnp_balance meta.
 *
 * @package TWork_Rewards
 */

if (!defined('ABSPATH')) {
    exit;
}

class TWork_Poll_PNP {

    const USER_META_BALANCE = '_user_pnp_balance';

    /**
     * Get user PNP/Point balance.
     * Uses actual point balance (points_balance / my_points) when twork-points-system is active.
     *
     * @param int $user_id User ID
     * @return int Balance (0 if not set)
     */
    public static function get_user_pnp($user_id)
    {
        if (!$user_id || $user_id <= 0) {
            return 0;
        }
        // Use actual point balance from T-Work Points System when available
        if (class_exists('TWork_Points_System')) {
            $instance = TWork_Points_System::get_instance();
            if (method_exists($instance, 'get_user_point_balance')) {
                return max(0, (int) $instance->get_user_point_balance($user_id));
            }
        }
        // Fallback to legacy PNP meta
        $balance = get_user_meta($user_id, self::USER_META_BALANCE, true);
        if ($balance === '' || $balance === false) {
            return 0;
        }
        return max(0, (int) $balance);
    }

    /**
     * Update user PNP/Point balance (add or subtract).
     * Uses TWork_Rewards_System (sync_user_points → twork_point_transactions) when available,
     * so points appear in actual balance. Deduct uses TWork_Points_System when available.
     *
     * @param int $user_id User ID
     * @param int $amount Amount to add (positive) or subtract (negative)
     * @param string $order_id Optional order ID for transaction tracking
     * @param string $description Optional description for the transaction
     * @return int|false New balance, or false on failure
     */
    public static function update_user_pnp($user_id, $amount, $order_id = '', $description = '')
    {
        if (!$user_id || $user_id <= 0) {
            return false;
        }
        $amount_int = (int) $amount;

        // Add points via TWork_Rewards_System (creates transaction, updates actual balance)
        if ($amount_int > 0 && class_exists('TWork_Rewards_System')) {
            $rewards = TWork_Rewards_System::get_instance();
            if (method_exists($rewards, 'award_engagement_points_to_user')) {
                $oid = $order_id ?: 'pnp_poll:' . $user_id . ':' . time();
                $desc = $description ?: sprintf('Poll winner reward (+%d PNP)', $amount_int);
                return $rewards->award_engagement_points_to_user(
                    $user_id,
                    $amount_int,
                    $oid,
                    $desc,
                    'poll',
                    'Poll'
                );
            }
        }

        // Deduct from actual point balance when twork-points-system is active
        if ($amount_int < 0 && class_exists('TWork_Points_System')) {
            $instance = TWork_Points_System::get_instance();
            if (method_exists($instance, 'deduct_for_poll_vote')) {
                $points_to_deduct = abs($amount_int);
                $desc = $description ?: 'Poll vote';
                $new_balance = $instance->deduct_for_poll_vote($user_id, $points_to_deduct, $desc);
                return $new_balance;
            }
        }

        // Fallback to legacy PNP meta when no integration available
        $current = self::get_user_pnp($user_id);
        $new_balance = max(0, $current + $amount_int);
        update_user_meta($user_id, self::USER_META_BALANCE, (string) $new_balance);
        return $new_balance;
    }

    /**
     * Get effective base for reward calculation.
     * Base Cost mode: poll_base_cost (admin PNP per option).
     * User Amount mode: bet_amount_step (PNP per unit of the amount selector).
     *
     * @param array<string, mixed> $quiz_data Quiz/poll config from engagement item
     * @return int Effective base (0 if not configured)
     */
    public static function get_effective_reward_base($quiz_data)
    {
        if (!is_array($quiz_data)) {
            return 0;
        }
        $poll_base_cost = isset($quiz_data['poll_base_cost']) ? max(0, (int) $quiz_data['poll_base_cost']) : 0;
        $allow_user_amount = !isset($quiz_data['allow_user_amount']) || $quiz_data['allow_user_amount'] === true
            || $quiz_data['allow_user_amount'] === 1 || $quiz_data['allow_user_amount'] === '1';

        if (!$allow_user_amount || $poll_base_cost > 0) {
            return $poll_base_cost;
        }
        if (isset($quiz_data['bet_amount_step'])) {
            return max(1, (int) $quiz_data['bet_amount_step']);
        }
        return 1000;
    }

    /**
     * Set user PNP balance (absolute value).
     *
     * @param int $user_id User ID
     * @param int $balance New balance (must be >= 0)
     * @return bool Success
     */
    public static function set_user_pnp($user_id, $balance)
    {
        if (!$user_id || $user_id <= 0) {
            return false;
        }
        $balance = max(0, (int) $balance);
        update_user_meta($user_id, self::USER_META_BALANCE, (string) $balance);
        return true;
    }
}
