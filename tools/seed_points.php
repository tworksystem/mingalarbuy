<?php

/**
 * Seeds baseline configuration for the T-Work Points System.
 *
 * Usage:
 *   wp eval-file tools/seed_points.php
 */

if (! defined('ABSPATH')) {
    exit;
}

update_option('twork_points_rate', 1.0);
update_option('twork_points_redemption_rate', 100);
update_option('twork_points_signup_bonus', 100);
update_option('twork_points_referral_bonus', 500);
update_option('twork_points_birthday_bonus', 200);
update_option('twork_points_min_redemption', 100);
update_option('twork_points_max_redemption_percent', 50);
update_option('twork_points_expiration_days', 365);

// Seed tier metadata (stored as option for reference in UI).
update_option(
    'twork_points_tiers',
    array(
        array(
            'key' => 'bronze',
            'label' => 'Bronze',
            'threshold' => 5000,
            'multiplier' => 1.1,
            'benefits' => array(
                '5% bonus earn rate',
                'Birthday surprise points',
            ),
        ),
        array(
            'key' => 'silver',
            'label' => 'Silver',
            'threshold' => 10000,
            'multiplier' => 1.2,
            'benefits' => array(
                'Priority customer support',
                'Exclusive product previews',
            ),
        ),
        array(
            'key' => 'gold',
            'label' => 'Gold',
            'threshold' => 20000,
            'multiplier' => 1.3,
            'benefits' => array(
                'Free expedited shipping',
                'Early access to sales',
            ),
        ),
        array(
            'key' => 'platinum',
            'label' => 'Platinum',
            'threshold' => 50000,
            'multiplier' => 1.5,
            'benefits' => array(
                'Dedicated concierge',
                'Quarterly elite offers',
            ),
        ),
    )
);

echo "T-Work Points base configuration seeded.\n";

