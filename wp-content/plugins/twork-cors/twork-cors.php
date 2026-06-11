<?php
/**
 * Plugin Name: T-Work CORS for Flutter Web
 * Description: Allows PlanetMM / Mingalarbuy Flutter web app to call WordPress & WooCommerce REST APIs from the browser (local dev + production web).
 * Version: 1.0.0
 * Author: T-Work System
 * License: MIT
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Allowed browser origins for cross-origin API access.
 * Filter with `twork_cors_allowed_origins` to add staging domains.
 */
function twork_cors_allowed_origins(): array
{
    $origins = [
        'https://mingalarbuy.com',
        'https://www.mingalarbuy.com',
    ];

    return apply_filters('twork_cors_allowed_origins', $origins);
}

function twork_cors_is_allowed_origin(?string $origin): bool
{
    if ($origin === null || $origin === '') {
        return false;
    }

    $origin = rtrim($origin, '/');

    foreach (twork_cors_allowed_origins() as $allowed) {
        if (strcasecmp(rtrim($allowed, '/'), $origin) === 0) {
            return true;
        }
    }

    // Local Flutter web dev: http://localhost:PORT or http://127.0.0.1:PORT
    $parts = wp_parse_url($origin);
    if (!is_array($parts)) {
        return false;
    }

    $scheme = $parts['scheme'] ?? '';
    $host = strtolower($parts['host'] ?? '');

    if ($scheme !== 'http') {
        return false;
    }

    return in_array($host, ['localhost', '127.0.0.1', '[::1]'], true);
}

function twork_cors_send_headers(?string $origin): void
{
    if ($origin !== null && twork_cors_is_allowed_origin($origin)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Credentials: true');
        header('Vary: Origin', false);
    }

    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');

    $requested = trim((string) ($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'] ?? ''));
    if ($requested !== '') {
        header('Access-Control-Allow-Headers: ' . $requested);
    } else {
        header(
            'Access-Control-Allow-Headers: Authorization, Content-Type, Accept, User-Agent, '
            . 'X-WP-Nonce, X-Requested-With, X-PlanetMM-Client, X-PlanetMM-Version, '
            . 'X-PlanetMM-Build, X-PlanetMM-Platform'
        );
    }

    header('Access-Control-Max-Age: 86400');
}

/**
 * WordPress REST API responses (wp-json/*).
 */
add_action('rest_api_init', function () {
    remove_filter('rest_pre_serve_request', 'rest_send_cors_headers');

    add_filter('rest_pre_serve_request', function ($value) {
        $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
        twork_cors_send_headers($origin);
        return $value;
    }, 15);
}, 15);

/**
 * Early OPTIONS preflight for wp-json routes.
 */
add_action('init', function () {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'OPTIONS') {
        return;
    }

    $uri = $_SERVER['REQUEST_URI'] ?? '';
    if (strpos($uri, '/wp-json/') === false) {
        return;
    }

    $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
    if (!twork_cors_is_allowed_origin($origin)) {
        return;
    }

    twork_cors_send_headers($origin);
    status_header(204);
    exit;
}, 1);
