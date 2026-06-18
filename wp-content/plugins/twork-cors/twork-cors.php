<?php
/**
 * Plugin Name: T-Work CORS for Flutter Web
 * Description: Flutter web — REST API CORS + hotlink-safe media (uploads CORS headers, referer allowlist, media proxy).
 * Version: 1.2.0
 * Author: T-Work System
 * License: MIT
 */

if (!defined('ABSPATH')) {
    exit;
}

const TWORK_CORS_VERSION = '1.2.0';
const TWORK_CORS_HTACCESS_MARKER = 'TWork CORS Hotlink';
const TWORK_CORS_UPLOADS_HTACCESS_MARKER = 'T-Work CORS — Flutter web media';

/**
 * Allowed browser origins for cross-origin API + media access.
 * Filter with `twork_cors_allowed_origins` to add staging domains.
 */
function twork_cors_allowed_origins(): array
{
    $origins = [
        'https://mingalarbuy.com',
        'https://www.mingalarbuy.com',
        'https://app.mingalarbuy.com',
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

/**
 * Referer patterns for Apache hotlink allowlist (auto-built from origins).
 *
 * @return string[] Regex fragments (without delimiters) for %{HTTP_REFERER} matches.
 */
function twork_cors_hotlink_referer_patterns(): array
{
    $patterns = [
        '', // empty Referer — browser `referrerpolicy="no-referrer"`
    ];

    foreach (twork_cors_allowed_origins() as $origin) {
        $parts = wp_parse_url($origin);
        if (!is_array($parts) || empty($parts['host'])) {
            continue;
        }

        $host = preg_quote($parts['host'], '/');
        $scheme = $parts['scheme'] ?? 'https';
        $patterns[] = '^' . preg_quote($scheme, '/') . '://' . $host . '(/|$)';
    }

    // Local dev referers (any port).
    $patterns[] = '^http://localhost(:\d+)?(/|$)';
    $patterns[] = '^http://127\.0\.0\.1(:\d+)?(/|$)';
    $patterns[] = '^http://\[::1\](:\d+)?(/|$)';

    return apply_filters('twork_cors_hotlink_referer_patterns', $patterns);
}

function twork_cors_default_allow_headers(): string
{
    return 'Authorization, Content-Type, Accept, Accept-Language, User-Agent, '
        . 'X-WP-Nonce, X-Requested-With, Idempotency-Key, '
        . 'X-PlanetMM-Client, X-PlanetMM-Version, X-PlanetMM-Build, X-PlanetMM-Platform';
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
        header('Access-Control-Allow-Headers: ' . twork_cors_default_allow_headers());
    }

    header('Access-Control-Max-Age: 86400');
}

/**
 * CORS headers for cross-origin <img> / fetch on media responses.
 */
function twork_cors_send_media_headers(?string $origin): void
{
    if ($origin !== null && twork_cors_is_allowed_origin($origin)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Credentials: true');
        header('Vary: Origin', false);
    }

    header('Cross-Origin-Resource-Policy: cross-origin');
    header('Timing-Allow-Origin: *');
}

function twork_cors_is_uploads_request(string $uri): bool
{
    return (bool) preg_match('#/wp-content/uploads/#i', $uri);
}

/**
 * CORS response headers for image files (used in uploads/.htaccess).
 *
 * @return string[]
 */
function twork_cors_build_uploads_cors_htaccess_rules(): array
{
    $rules = [
        '<IfModule mod_headers.c>',
        '  <FilesMatch "\.(jpe?g|png|gif|webp|svg|ico|avif)$">',
    ];

    $index = 0;
    foreach (twork_cors_allowed_origins() as $allowed_origin) {
        $escaped = preg_quote($allowed_origin, '#');
        $env = 'TWORK_CORS_ORIGIN_' . $index;
        $rules[] = '    SetEnvIfExpr "%{HTTP:Origin} =~ m#^' . $escaped . '$#" ' . $env . '=1';
        $rules[] = '    Header always set Access-Control-Allow-Origin "' . $allowed_origin . '" env=' . $env;
        ++$index;
    }

    $rules[] = '    SetEnvIfExpr "%{HTTP:Origin} =~ m#^http://localhost(:\\d+)?$#" TWORK_CORS_LOCAL=1';
    $rules[] = '    Header always set Access-Control-Allow-Origin "%{HTTP:Origin}e" env=TWORK_CORS_LOCAL';
    $rules[] = '    SetEnvIfExpr "%{HTTP:Origin} =~ m#^http://127\\.0\\.0\\.1(:\\d+)?$#" TWORK_CORS_LOCAL2=1';
    $rules[] = '    Header always set Access-Control-Allow-Origin "%{HTTP:Origin}e" env=TWORK_CORS_LOCAL2';
    $rules[] = '    Header always set Cross-Origin-Resource-Policy "cross-origin"';
    $rules[] = '  </FilesMatch>';
    $rules[] = '</IfModule>';

    return $rules;
}

/**
 * Root .htaccess: allow Flutter web referers on /wp-content/uploads/ (hotlink bypass).
 *
 * @return string[]
 */
function twork_cors_build_root_hotlink_htaccess_rules(): array
{
    $patterns = twork_cors_hotlink_referer_patterns();
    if ($patterns === []) {
        return [];
    }

    $rules = [
        '<IfModule mod_rewrite.c>',
        'RewriteEngine On',
        'RewriteCond %{REQUEST_URI} ^/wp-content/uploads/ [NC]',
    ];

    $total = count($patterns);
    foreach ($patterns as $i => $pattern) {
        if ($pattern === '') {
            $cond = 'RewriteCond %{HTTP_REFERER} ^$';
        } else {
            $cond = 'RewriteCond %{HTTP_REFERER} ' . $pattern . ' [NC]';
        }
        if ($i < $total - 1) {
            $cond .= ' [OR]';
        }
        $rules[] = $cond;
    }

    $rules[] = 'RewriteRule . - [L]';
    $rules[] = '</IfModule>';

    return $rules;
}

/**
 * Write wp-content/uploads/.htaccess with CORS + hotlink allow rules.
 */
function twork_cors_write_uploads_htaccess(): bool
{
    $upload_dir = wp_get_upload_dir();
    if (!empty($upload_dir['error']) || empty($upload_dir['basedir'])) {
        return false;
    }

    $path = trailingslashit($upload_dir['basedir']) . '.htaccess';
    $lines = [
        '# ' . TWORK_CORS_UPLOADS_HTACCESS_MARKER . ' (auto-generated v' . TWORK_CORS_VERSION . ')',
        '# Deactivate/reactivate twork-cors plugin to regenerate.',
        '',
    ];

    $lines = array_merge($lines, twork_cors_build_uploads_cors_htaccess_rules());
    $content = implode("\n", $lines) . "\n";

    if (file_exists($path)) {
        $existing = (string) file_get_contents($path);
        if (strpos($existing, TWORK_CORS_UPLOADS_HTACCESS_MARKER) !== false) {
            $existing = preg_replace(
                '/# ' . preg_quote(TWORK_CORS_UPLOADS_HTACCESS_MARKER, '/') . '.*$/s',
                '',
                $existing
            );
            $existing = trim($existing);
            $content = $existing !== '' ? $existing . "\n\n" . $content : $content;
        }
    }

    return (bool) file_put_contents($path, $content);
}

function twork_cors_install_hotlink_rules(): void
{
    twork_cors_write_uploads_htaccess();

    if (!function_exists('insert_with_markers')) {
        require_once ABSPATH . 'wp-admin/includes/misc.php';
    }

    insert_with_markers(
        ABSPATH . '.htaccess',
        TWORK_CORS_HTACCESS_MARKER,
        twork_cors_build_root_hotlink_htaccess_rules()
    );
}

function twork_cors_remove_hotlink_rules(): void
{
    $upload_dir = wp_get_upload_dir();
    if (empty($upload_dir['error']) && !empty($upload_dir['basedir'])) {
        $path = trailingslashit($upload_dir['basedir']) . '.htaccess';
        if (file_exists($path)) {
            $existing = (string) file_get_contents($path);
            if (strpos($existing, TWORK_CORS_UPLOADS_HTACCESS_MARKER) !== false) {
                $cleaned = preg_replace(
                    '/# ' . preg_quote(TWORK_CORS_UPLOADS_HTACCESS_MARKER, '/') . '.*$/s',
                    '',
                    $existing
                );
                $cleaned = trim((string) $cleaned);
                if ($cleaned === '') {
                    wp_delete_file($path);
                } else {
                    file_put_contents($path, $cleaned . "\n");
                }
            }
        }
    }

    if (!function_exists('extract_from_markers')) {
        require_once ABSPATH . 'wp-admin/includes/misc.php';
    }

    insert_with_markers(ABSPATH . '.htaccess', TWORK_CORS_HTACCESS_MARKER, []);
}

/**
 * Validate media URL for proxy — same host, uploads path only.
 */
function twork_cors_validate_media_src(string $src): ?string
{
    $src = trim($src);
    if ($src === '') {
        return null;
    }

    $parsed = wp_parse_url($src);
    if (!is_array($parsed) || empty($parsed['host']) || empty($parsed['path'])) {
        return null;
    }

    $site_host = wp_parse_url(home_url(), PHP_URL_HOST);
    if (!$site_host || strcasecmp((string) $parsed['host'], (string) $site_host) !== 0) {
        return null;
    }

    if (!twork_cors_is_uploads_request($parsed['path'])) {
        return null;
    }

    $scheme = strtolower($parsed['scheme'] ?? 'https');
    if (!in_array($scheme, ['http', 'https'], true)) {
        return null;
    }

    return $scheme . '://' . $parsed['host'] . $parsed['path']
        . (isset($parsed['query']) ? '?' . $parsed['query'] : '');
}

/**
 * Public media-proxy URL helper for themes / other plugins.
 */
function twork_cors_media_proxy_url(string $attachment_url): string
{
    $validated = twork_cors_validate_media_src($attachment_url);
    if ($validated === null) {
        return $attachment_url;
    }

    return add_query_arg(
        'src',
        rawurlencode($validated),
        rest_url('twork/v1/media-proxy')
    );
}

/**
 * Stream proxied media (bypasses Referer-based hotlink blocks).
 */
function twork_cors_serve_media_proxy(string $src): void
{
    $validated = twork_cors_validate_media_src($src);
    if ($validated === null) {
        status_header(400);
        header('Content-Type: application/json; charset=utf-8');
        echo wp_json_encode(['code' => 'invalid_src', 'message' => 'Invalid or disallowed media URL.']);
        exit;
    }

    $response = wp_remote_get($validated, [
        'timeout' => 20,
        'redirection' => 2,
        'headers' => [
            'Accept' => 'image/*,*/*;q=0.8',
            'User-Agent' => 'T-Work-Media-Proxy/' . TWORK_CORS_VERSION,
        ],
    ]);

    if (is_wp_error($response)) {
        status_header(502);
        header('Content-Type: application/json; charset=utf-8');
        echo wp_json_encode(['code' => 'proxy_failed', 'message' => $response->get_error_message()]);
        exit;
    }

    $code = (int) wp_remote_retrieve_response_code($response);
    if ($code < 200 || $code >= 300) {
        status_header($code > 0 ? $code : 404);
        header('Content-Type: application/json; charset=utf-8');
        echo wp_json_encode(['code' => 'upstream_error', 'message' => 'Media not available.', 'status' => $code]);
        exit;
    }

    $body = wp_remote_retrieve_body($response);
    $content_type = wp_remote_retrieve_header($response, 'content-type');
    if (!$content_type) {
        $content_type = wp_check_filetype($validated)['type'] ?: 'application/octet-stream';
    }

    $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
    status_header(200);
    header('Content-Type: ' . $content_type);
    header('Cache-Control: public, max-age=86400, stale-while-revalidate=604800');
    header('X-Content-Type-Options: nosniff');
    twork_cors_send_media_headers($origin);
    echo $body;
    exit;
}

register_activation_hook(__FILE__, 'twork_cors_install_hotlink_rules');
register_deactivation_hook(__FILE__, 'twork_cors_remove_hotlink_rules');

/**
 * Regenerate Apache rules when allowed origins change (optional staging domains).
 */
add_action('upgrader_process_complete', function ($upgrader, $options) {
    if (($options['type'] ?? '') === 'plugin' && ($options['action'] ?? '') === 'update') {
        twork_cors_install_hotlink_rules();
    }
}, 10, 2);

/**
 * WordPress REST preflight uses rest_allowed_cors_headers — merge PlanetMM headers here.
 */
add_filter('rest_allowed_cors_headers', function ($headers) {
    $extra = [
        'Idempotency-Key',
        'Accept-Language',
        'X-PlanetMM-Client',
        'X-PlanetMM-Version',
        'X-PlanetMM-Build',
        'X-PlanetMM-Platform',
    ];
    foreach ($extra as $name) {
        if (!in_array($name, $headers, true)) {
            $headers[] = $name;
        }
    }
    return $headers;
}, 15);

/**
 * REST: media proxy + CORS on wp-json.
 */
add_action('rest_api_init', function () {
    remove_filter('rest_pre_serve_request', 'rest_send_cors_headers');

    register_rest_route('twork/v1', '/media-proxy', [
        'methods' => ['GET', 'HEAD', 'OPTIONS'],
        'callback' => function (WP_REST_Request $request) {
            if ($request->get_method() === 'OPTIONS') {
                $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
                if (twork_cors_is_allowed_origin($origin)) {
                    twork_cors_send_media_headers($origin);
                    status_header(204);
                    exit;
                }
                return new WP_REST_Response(null, 204);
            }

            if ($request->get_method() === 'HEAD') {
                $src = (string) $request->get_param('src');
                $validated = twork_cors_validate_media_src($src);
                if ($validated === null) {
                    return new WP_Error('invalid_src', 'Invalid media URL.', ['status' => 400]);
                }
                return new WP_REST_Response(null, 200);
            }

            twork_cors_serve_media_proxy((string) $request->get_param('src'));
            return null;
        },
        'permission_callback' => '__return_true',
        'args' => [
            'src' => [
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'esc_url_raw',
            ],
        ],
    ]);

    add_filter('rest_pre_serve_request', function ($value, $result, $request, $server) {
        $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
        $route = $request instanceof WP_REST_Request ? $request->get_route() : '';

        if ($route === '/twork/v1/media-proxy') {
            return $value;
        }

        twork_cors_send_headers($origin);
        return $value;
    }, 15, 4);
}, 15);

/**
 * Early OPTIONS preflight for wp-json routes.
 */
add_action('init', function () {
    $method = $_SERVER['REQUEST_METHOD'] ?? '';
    $uri = $_SERVER['REQUEST_URI'] ?? '';
    $origin = $_SERVER['HTTP_ORIGIN'] ?? null;

    if ($method === 'OPTIONS' && strpos($uri, '/wp-json/') !== false) {
        if (twork_cors_is_allowed_origin($origin)) {
            twork_cors_send_headers($origin);
            status_header(204);
            exit;
        }
        return;
    }

    // PHP-handled upload paths (when not served as static files).
    if (twork_cors_is_uploads_request($uri) && twork_cors_is_allowed_origin($origin)) {
        twork_cors_send_media_headers($origin);

        if ($method === 'OPTIONS') {
            header('Access-Control-Allow-Methods: GET, HEAD, OPTIONS');
            header('Access-Control-Max-Age: 86400');
            status_header(204);
            exit;
        }
    }
}, 1);

/**
 * WooCommerce REST product images — optional proxy URLs for cross-origin web clients.
 * Enable with: add_filter('twork_cors_rewrite_product_image_urls', '__return_true');
 */
add_filter('woocommerce_rest_prepare_product_object', function ($response, $product, $request) {
    if (!apply_filters('twork_cors_rewrite_product_image_urls', false)) {
        return $response;
    }

    $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
    if (!twork_cors_is_allowed_origin($origin)) {
        return $response;
    }

    $data = $response->get_data();

    if (!empty($data['images']) && is_array($data['images'])) {
        foreach ($data['images'] as $i => $image) {
            if (!empty($image['src'])) {
                $data['images'][$i]['src'] = twork_cors_media_proxy_url($image['src']);
            }
        }
    }

    $response->set_data($data);
    return $response;
}, 20, 3);
