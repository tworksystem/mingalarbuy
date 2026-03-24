<?php
/**
 * Flush WordPress Permalinks and Re-register Routes
 * 
 * This script will:
 * 1. Load WordPress
 * 2. Flush rewrite rules
 * 3. Re-trigger REST API initialization
 * 4. Verify engagement routes are registered
 * 
 * Usage: Place in WordPress root and access via browser
 * https://your-site.com/flush_permalinks.php
 */

require_once('wp-load.php');

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Flush Permalinks & Register Routes</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        h1 { color: #0073aa; border-bottom: 3px solid #0073aa; padding-bottom: 10px; }
        .success { color: #46b450; font-weight: bold; font-size: 18px; }
        .error { color: #dc3232; font-weight: bold; font-size: 18px; }
        .info { background: #e5f5fa; padding: 15px; border-left: 4px solid #00a0d2; margin: 15px 0; }
        code { background: #f0f0f0; padding: 3px 8px; border-radius: 3px; font-family: monospace; }
        .step { margin: 20px 0; padding: 15px; background: #f9f9f9; border-radius: 5px; }
        .step h3 { margin-top: 0; color: #0073aa; }
        ul { line-height: 1.8; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Flush Permalinks & Register Routes</h1>
        
        <?php
        // Step 1: Flush rewrite rules
        echo '<div class="step">';
        echo '<h3>Step 1: Flushing Rewrite Rules</h3>';
        flush_rewrite_rules(true);
        echo '<p class="success">✓ Rewrite rules flushed successfully!</p>';
        echo '</div>';
        
        // Step 2: Re-trigger REST API initialization
        echo '<div class="step">';
        echo '<h3>Step 2: Re-initializing REST API</h3>';
        do_action('rest_api_init');
        echo '<p class="success">✓ REST API re-initialized!</p>';
        echo '</div>';
        
        // Step 3: Check if plugin is active
        echo '<div class="step">';
        echo '<h3>Step 3: Checking Plugin Status</h3>';
        $plugin_file = 'twork-rewards-system/twork-rewards-system.php';
        if (is_plugin_active($plugin_file)) {
            echo '<p class="success">✓ TWork Rewards System plugin is ACTIVE</p>';
        } else {
            echo '<p class="error">✗ TWork Rewards System plugin is NOT ACTIVE</p>';
            echo '<p>Please activate the plugin from WordPress Admin → Plugins</p>';
        }
        echo '</div>';
        
        // Step 4: Verify routes are registered
        echo '<div class="step">';
        echo '<h3>Step 4: Verifying Engagement Routes</h3>';
        
        $rest_server = rest_get_server();
        $routes = $rest_server->get_routes();
        
        $engagement_feed_exists = isset($routes['/twork/v1/engagement/feed']);
        $engagement_interact_exists = isset($routes['/twork/v1/engagement/interact']);
        
        if ($engagement_feed_exists) {
            echo '<p class="success">✓ Route <code>/twork/v1/engagement/feed</code> is registered</p>';
            
            // Show allowed methods
            $methods = $routes['/twork/v1/engagement/feed'];
            echo '<p>Allowed methods: ';
            foreach ($methods as $method) {
                if (isset($method['methods'])) {
                    $method_list = is_array($method['methods']) ? $method['methods'] : [$method['methods']];
                    echo '<code>' . implode(', ', array_keys($method_list)) . '</code> ';
                }
            }
            echo '</p>';
        } else {
            echo '<p class="error">✗ Route <code>/twork/v1/engagement/feed</code> is NOT registered</p>';
        }
        
        if ($engagement_interact_exists) {
            echo '<p class="success">✓ Route <code>/twork/v1/engagement/interact</code> is registered</p>';
        } else {
            echo '<p class="error">✗ Route <code>/twork/v1/engagement/interact</code> is NOT registered</p>';
        }
        echo '</div>';
        
        // Step 5: Test the endpoint
        echo '<div class="step">';
        echo '<h3>Step 5: Testing Engagement Feed Endpoint</h3>';
        
        $test_url = rest_url('twork/v1/engagement/feed');
        echo '<p>Testing: <code>' . $test_url . '?user_id=1</code></p>';
        
        $response = wp_remote_get($test_url . '?user_id=1', array(
            'timeout' => 15,
        ));
        
        if (is_wp_error($response)) {
            echo '<p class="error">✗ Request failed: ' . $response->get_error_message() . '</p>';
        } else {
            $status_code = wp_remote_retrieve_response_code($response);
            $body = wp_remote_retrieve_body($response);
            
            if ($status_code === 200) {
                echo '<p class="success">✓ Endpoint returned 200 OK</p>';
                
                $data = json_decode($body, true);
                if (isset($data['success']) && $data['success']) {
                    $item_count = isset($data['data']) ? count($data['data']) : 0;
                    echo '<p class="success">✓ API returned ' . $item_count . ' engagement items</p>';
                    
                    if ($item_count > 0) {
                        echo '<p><strong>Sample item:</strong></p>';
                        echo '<pre style="background: #f0f0f0; padding: 10px; border-radius: 5px; overflow-x: auto;">';
                        echo json_encode($data['data'][0], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
                        echo '</pre>';
                    }
                } else {
                    echo '<p class="error">✗ API returned error: ' . ($data['message'] ?? 'Unknown error') . '</p>';
                }
            } elseif ($status_code === 404) {
                echo '<p class="error">✗ Endpoint returned 404 NOT FOUND</p>';
                echo '<p>This means the route is still not registered. Try:</p>';
                echo '<ul>';
                echo '<li>Deactivate and reactivate the plugin</li>';
                echo '<li>Check if there are any PHP errors in the plugin file</li>';
                echo '<li>Verify the plugin file is not corrupted</li>';
                echo '</ul>';
            } else {
                echo '<p class="error">✗ Endpoint returned status code: ' . $status_code . '</p>';
                echo '<pre style="background: #f0f0f0; padding: 10px; border-radius: 5px; overflow-x: auto;">';
                echo esc_html(substr($body, 0, 500));
                echo '</pre>';
            }
        }
        echo '</div>';
        
        // Summary and next steps
        echo '<div class="info">';
        echo '<h3>📋 Summary</h3>';
        
        if ($engagement_feed_exists && $status_code === 200) {
            echo '<p class="success"><strong>✓ Everything looks good!</strong></p>';
            echo '<p>The engagement feed endpoint is now working. Try these steps:</p>';
            echo '<ul>';
            echo '<li>Restart your mobile app completely (kill and reopen)</li>';
            echo '<li>Clear app cache if available</li>';
            echo '<li>Check app console logs for "Engagement feed loaded" message</li>';
            echo '</ul>';
        } else {
            echo '<p class="error"><strong>⚠ Issues detected</strong></p>';
            echo '<p>Please try these steps:</p>';
            echo '<ul>';
            echo '<li>Go to WordPress Admin → Plugins</li>';
            echo '<li>Deactivate "TWork Rewards System"</li>';
            echo '<li>Reactivate "TWork Rewards System"</li>';
            echo '<li>Run this script again</li>';
            echo '</ul>';
        }
        echo '</div>';
        
        // Additional info
        echo '<div class="info">';
        echo '<h3>🔗 Useful Links</h3>';
        echo '<ul>';
        echo '<li><a href="' . admin_url('options-permalink.php') . '">WordPress Permalinks Settings</a></li>';
        echo '<li><a href="' . admin_url('plugins.php') . '">WordPress Plugins</a></li>';
        echo '<li><a href="' . rest_url() . '" target="_blank">REST API Index</a></li>';
        echo '<li><a href="' . rest_url('twork/v1/engagement/feed?user_id=1') . '" target="_blank">Test Engagement Feed</a></li>';
        echo '</ul>';
        echo '</div>';
        ?>
        
        <p style="text-align: center; margin-top: 30px; color: #666;">
            <small>After fixing the issue, you can delete this file for security.</small>
        </p>
    </div>
</body>
</html>

