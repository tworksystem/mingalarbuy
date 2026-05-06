<?php
/**
 * Plugin Name: T-Work FCM Notify
 * Plugin URI: https://github.com/tworksystem/twork-fcm-notify
 * Description: Store FCM tokens and send push notifications on WooCommerce order status changes using Firebase Cloud Messaging v1 API.
 * Version: 1.0.0
 * Author: T-Work System
 * Author URI: https://github.com/tworksystem
 * License: Proprietary
 * Text Domain: twork-fcm-notify
 * Domain Path: /languages
 * Requires at least: 5.0
 * Requires PHP: 7.4
 * WC requires at least: 3.0
 * WC tested up to: 8.0
 */

if (!defined('ABSPATH')) exit;

// HTTP v1 (recommended): set your Firebase project id and the path to the
// downloaded service account JSON (Firebase Console → Project Settings →
// Service accounts → Generate new private key)
define('TWORK_FCM_PROJECT_ID', 'twork-commerce'); // e.g. twork-commerce
define('TWORK_FCM_SERVICE_ACCOUNT_JSON', __DIR__ . '/serviceAccountKey.json');

// 1) REST route to register/update device token
add_action('rest_api_init', function () {
    register_rest_route('twork/v1', '/register-token', [
        'methods'  => 'POST',
        'callback' => 'twork_register_fcm_token',
        'permission_callback' => '__return_true',
    ]);
});

function twork_register_fcm_token(WP_REST_Request $request) {
    $user_id  = sanitize_text_field($request->get_param('userId'));
    $token    = sanitize_text_field($request->get_param('fcmToken'));
    $platform = sanitize_text_field($request->get_param('platform')) ?: 'android';

    // Validation
    if (empty($user_id) || empty($token)) {
        return new WP_REST_Response(['success' => false, 'error' => 'userId and fcmToken required'], 400);
    }

    // Validate user ID is numeric and user exists
    $user_id = absint($user_id);
    if (!$user_id || !get_user_by('ID', $user_id)) {
        return new WP_REST_Response(['success' => false, 'error' => 'Invalid userId'], 400);
    }

    // Validate platform
    $platform = strtolower($platform);
    if (!in_array($platform, ['android', 'ios'], true)) {
        $platform = 'android';
    }

    // Validate token format (basic validation - FCM tokens are typically long strings)
    if (strlen($token) < 10) {
        return new WP_REST_Response(['success' => false, 'error' => 'Invalid fcmToken format'], 400);
    }

    $meta_key = 'twork_fcm_tokens';
    $tokens = get_user_meta($user_id, $meta_key, true);
    if (!is_array($tokens)) {
        $tokens = [];
    }

    // De-duplicate per platform and remove old/invalid entries
    $tokens = array_values(array_filter($tokens, function ($t) use ($platform, $token) {
        // Remove if same platform and token (duplicate)
        if (isset($t['platform']) && isset($t['token']) && $t['platform'] === $platform && $t['token'] === $token) {
            return false;
        }
        // Keep only valid entries
        return isset($t['token']) && isset($t['platform']) && !empty($t['token']);
    }));

    // Add new token
    $tokens[] = [
        'token' => sanitize_text_field($token),
        'platform' => sanitize_text_field($platform),
        'updated_at' => time()
    ];

    // Limit to 10 tokens per user to prevent excessive storage
    if (count($tokens) > 10) {
        // Sort by updated_at and keep most recent
        usort($tokens, function($a, $b) {
            return ($b['updated_at'] ?? 0) - ($a['updated_at'] ?? 0);
        });
        $tokens = array_slice($tokens, 0, 10);
    }

    $result = update_user_meta($user_id, $meta_key, $tokens);

    if ($result === false) {
        return new WP_REST_Response(['success' => false, 'error' => 'Failed to save token'], 500);
    }

    return new WP_REST_Response([
        'success' => true,
        'tokenCount' => count($tokens),
        'platform' => $platform
    ], 200);
}

// 2) Debug endpoint to view saved tokens (for development/debugging)
add_action('rest_api_init', function () {
    register_rest_route('twork/v1', '/debug/tokens/(?P<user_id>\\d+)', [
        'methods'  => 'GET',
        'callback' => function (WP_REST_Request $request) {
            $user_id = absint($request->get_param('user_id'));
            
            if (!$user_id) {
                return new WP_REST_Response(['error' => 'Invalid user_id'], 400);
            }

            $tokens = get_user_meta($user_id, 'twork_fcm_tokens', true);
            if (!is_array($tokens)) {
                $tokens = [];
            }

            // Mask tokens for security (show only first 25 characters)
            $masked = array_map(function ($t) {
                if (isset($t['token']) && strlen($t['token']) > 25) {
                    $t['token'] = substr($t['token'], 0, 25) . '...';
                }
                return $t;
            }, $tokens);

            return new WP_REST_Response([
                'userId' => $user_id,
                'tokenCount' => count($tokens),
                'tokens' => $masked
            ], 200);
        },
        'permission_callback' => '__return_true',
    ]);
});

// 3) Hook: send push when order status changes
add_action('woocommerce_order_status_changed', function ($order_id, $old_status, $new_status, $order) {
    if (!$order instanceof WC_Order) $order = wc_get_order($order_id);
    if (!$order) return;

    $customer_id = $order->get_customer_id();
    if (!$customer_id) return;

    $tokens = get_user_meta($customer_id, 'twork_fcm_tokens', true);
    if (!is_array($tokens) || empty($tokens)) return;

    $title = sprintf('Order #%d %s', $order_id, twork_status_message($new_status));
    $body  = sprintf('Your order total is %s %s', $order->get_currency(), $order->get_total());

    $data = [
        'orderId' => (string)$order_id,
        'status'  => $new_status,
        'total'   => (string)$order->get_total(),
        'currency'=> $order->get_currency(),
        'type'    => 'order_status_update',
        'userId'  => (string)$customer_id, // PROFESSIONAL SECURITY: Include userId for verification
        'user_id' => (string)$customer_id, // Also include user_id for compatibility
    ];

    foreach ($tokens as $t) {
        twork_send_fcm($t['token'], $title, $body, $data);
    }
}, 10, 4);

function twork_status_message($status) {
    $map = [
        'pending'    => 'is being processed',
        'processing' => 'is being prepared',
        'on-hold'    => 'is on hold',
        'completed'  => 'has been completed',
        'cancelled'  => 'has been cancelled',
        'refunded'   => 'has been refunded',
        'failed'     => 'payment failed',
        'shipped'    => 'has been shipped',
    ];
    return $map[$status] ?? 'status has been updated';
}

function twork_get_access_token_from_sa() {
    // Security: Check file exists and has proper permissions
    if (!file_exists(TWORK_FCM_SERVICE_ACCOUNT_JSON)) {
        error_log('[T-Work FCM] Error: serviceAccountKey.json not found at ' . TWORK_FCM_SERVICE_ACCOUNT_JSON);
        error_log('[T-Work FCM] Hint: Copy serviceAccountKey.json.example to serviceAccountKey.json and add your Firebase credentials');
        return null;
    }

    // Security: Check file permissions (should not be world-readable)
    $file_perms = fileperms(TWORK_FCM_SERVICE_ACCOUNT_JSON);
    if ($file_perms && ($file_perms & 0044)) {
        error_log('[T-Work FCM] Warning: serviceAccountKey.json has world-readable permissions. Consider: chmod 600 ' . TWORK_FCM_SERVICE_ACCOUNT_JSON);
    }

    // Security: Read file safely
    $json_content = @file_get_contents(TWORK_FCM_SERVICE_ACCOUNT_JSON);
    if ($json_content === false) {
        error_log('[T-Work FCM] Error: Cannot read serviceAccountKey.json. Check file permissions.');
        return null;
    }

    $sa = json_decode($json_content, true);
    if (!is_array($sa) || empty($sa['client_email']) || empty($sa['private_key'])) {
        error_log('[T-Work FCM] Error: Invalid service account JSON. Missing required fields (client_email, private_key)');
        error_log('[T-Work FCM] Hint: Ensure serviceAccountKey.json contains valid Firebase service account credentials');
        return null;
    }

    // Security: Validate email format
    if (!filter_var($sa['client_email'], FILTER_VALIDATE_EMAIL)) {
        error_log('[T-Work FCM] Error: Invalid client_email format in serviceAccountKey.json');
        return null;
    }

    $now = time();
    $jwtHeader = ['alg' => 'RS256', 'typ' => 'JWT'];
    $jwtClaim = [
        'iss' => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    ];

    $b64u = function ($data) {
        return rtrim(strtr(base64_encode(is_string($data) ? $data : json_encode($data)), '+/', '-_'), '=');
    };

    $toSign = $b64u($jwtHeader) . '.' . $b64u($jwtClaim);
    $privateKey = openssl_pkey_get_private($sa['private_key']);
    if (!$privateKey) { error_log('FCM v1: cannot load private key'); return null; }
    openssl_sign($toSign, $signature, $privateKey, 'sha256WithRSAEncryption');
    $jwt = $toSign . '.' . $b64u($signature);

    $resp = wp_remote_post('https://oauth2.googleapis.com/token', [
        'headers' => ['Content-Type' => 'application/x-www-form-urlencoded'],
        'body' => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
        'timeout' => 20,
    ]);
    if (is_wp_error($resp)) return null;
    $body = json_decode(wp_remote_retrieve_body($resp), true);
    return $body['access_token'] ?? null;
}

function twork_send_fcm($token, $title, $body, $data = []) {
    /*
    Old Code — backend-wide kill switch: every FCM send returned false, so poll/quiz wins
    could never reach the device (My PNP could not real-time sync from push).
    // Disabled notification for backend-wide suppression.
    // Old FCM transport logic is intentionally kept below to preserve rollback safety.
    return false;
    */

    // New Code: allow FCM v1 delivery (points / engagement payloads depend on this).

    // Silent Update: admin saves (e.g. Engagement Hub) can suppress all FCM sends for this request.
    if (isset($_POST['twork_skip_fcm_notify']) && (string) wp_unslash($_POST['twork_skip_fcm_notify']) === '1') {
        return false;
    }

    // Validate configuration
    if (!defined('TWORK_FCM_PROJECT_ID') || TWORK_FCM_PROJECT_ID === 'YOUR_FIREBASE_PROJECT_ID') {
        error_log('[T-Work FCM] Error: TWORK_FCM_PROJECT_ID not set');
        return false;
    }

    // Validate token
    if (empty($token) || !is_string($token)) {
        error_log('[T-Work FCM] Error: Invalid token provided');
        return false;
    }

    // Get access token
    $accessToken = twork_get_access_token_from_sa();
    if (!$accessToken) {
        error_log('[T-Work FCM] Error: Failed to obtain access token');
        return false;
    }

    // Sanitize title and body for notification
    $title = sanitize_text_field($title);
    $body = sanitize_text_field($body);

    /*
    Old Code — sanitize_key() lowercases keys and breaks camelCase contracts with Flutter
    (e.g. currentBalance -> currentbalance), so the app could not read currentBalance / userId.
    $sanitized_data = [];
    foreach ($data as $key => $value) {
        $sanitized_key = sanitize_key($key);
        $sanitized_data[$sanitized_key] = is_string($value) ? sanitize_text_field($value) : $value;
    }
    */

    // New Code: preserve stable keys; FCM v1 `data` values MUST be strings.
    $sanitized_data = array();
    foreach ($data as $key => $value) {
        if (!is_string($key) || $key === '') {
            continue;
        }
        $k = preg_replace('/[^A-Za-z0-9_\-]/', '', $key);
        if ($k === '') {
            continue;
        }
        if (is_array($value) || is_object($value)) {
            $encoded = wp_json_encode($value);
            $sanitized_data[ $k ] = is_string($encoded) ? $encoded : '';
        } elseif (is_bool($value)) {
            $sanitized_data[ $k ] = $value ? '1' : '0';
        } elseif (is_int($value) || is_float($value)) {
            $sanitized_data[ $k ] = (string) $value;
        } else {
            $sanitized_data[ $k ] = sanitize_text_field((string) $value);
        }
    }

    // Build FCM API URL
    $url = 'https://fcm.googleapis.com/v1/projects/' . esc_attr(TWORK_FCM_PROJECT_ID) . '/messages:send';
    
    // Build payload
    $payload = [
        'message' => [
            'token' => sanitize_text_field($token),
            'notification' => [
                'title' => $title,
                'body' => $body
            ],
            'data' => $sanitized_data,
            'android' => [
                'priority' => 'HIGH'
            ],
            'apns' => [
                'headers' => [
                    'apns-priority' => '10'
                ],
                'payload' => [
                    'aps' => [
                        'sound' => 'default',
                        'content-available' => 1,
                        'badge' => 1
                    ]
                ]
            ],
        ],
    ];

    // Send request
    $resp = wp_remote_post($url, [
        'headers' => [
            'Authorization' => 'Bearer ' . $accessToken,
            'Content-Type' => 'application/json',
        ],
        'body' => wp_json_encode($payload),
        'timeout' => 20,
        'sslverify' => true,
    ]);

    // Handle response
    if (is_wp_error($resp)) {
        error_log('[T-Work FCM] Error: ' . $resp->get_error_message());
        return false;
    }

    $response_code = wp_remote_retrieve_response_code($resp);
    $response_body = wp_remote_retrieve_body($resp);

    if ($response_code !== 200) {
        error_log('[T-Work FCM] Error: HTTP ' . $response_code . ' - ' . $response_body);
        return false;
    }

    return true;
}