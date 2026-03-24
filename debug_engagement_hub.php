<?php
/**
 * Engagement Hub Debug Script
 * 
 * Place this file in your WordPress root directory and access it via browser:
 * https://your-site.com/debug_engagement_hub.php
 * 
 * This will help diagnose why Engagement Hub data is not loading
 */

// Load WordPress
require_once('wp-load.php');

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Engagement Hub Debug</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0073aa; padding-bottom: 10px; }
        h2 { color: #0073aa; margin-top: 30px; }
        .success { color: #46b450; font-weight: bold; }
        .error { color: #dc3232; font-weight: bold; }
        .warning { color: #f56e28; font-weight: bold; }
        .info { background: #e5f5fa; padding: 10px; border-left: 4px solid #00a0d2; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #0073aa; color: white; }
        tr:hover { background: #f5f5f5; }
        code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; }
        .json { background: #f9f9f9; padding: 15px; border-radius: 5px; overflow-x: auto; }
        pre { margin: 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Engagement Hub Debug Report</h1>
        <p>Generated: <?php echo date('Y-m-d H:i:s'); ?></p>

        <?php
        global $wpdb;
        $issues = [];
        $warnings = [];

        // 1. Check Plugin Activation
        echo '<h2>1. Plugin Activation Check</h2>';
        $plugin_file = 'twork-rewards-system/twork-rewards-system.php';
        if (is_plugin_active($plugin_file)) {
            echo '<p class="success">✓ TWork Rewards System plugin is ACTIVE</p>';
        } else {
            echo '<p class="error">✗ TWork Rewards System plugin is NOT ACTIVE</p>';
            $issues[] = 'Plugin is not activated. Please activate it from WordPress Admin → Plugins.';
        }

        // 2. Check Database Tables
        echo '<h2>2. Database Tables Check</h2>';
        $table_items = $wpdb->prefix . 'twork_engagement_items';
        $table_interactions = $wpdb->prefix . 'twork_user_interactions';
        
        $items_exists = $wpdb->get_var("SHOW TABLES LIKE '$table_items'") === $table_items;
        $interactions_exists = $wpdb->get_var("SHOW TABLES LIKE '$table_interactions'") === $table_interactions;
        
        if ($items_exists) {
            echo '<p class="success">✓ Table <code>' . $table_items . '</code> EXISTS</p>';
        } else {
            echo '<p class="error">✗ Table <code>' . $table_items . '</code> DOES NOT EXIST</p>';
            $issues[] = 'Engagement items table is missing. The plugin may not have been properly installed.';
        }
        
        if ($interactions_exists) {
            echo '<p class="success">✓ Table <code>' . $table_interactions . '</code> EXISTS</p>';
        } else {
            echo '<p class="error">✗ Table <code>' . $table_interactions . '</code> DOES NOT EXIST</p>';
            $issues[] = 'User interactions table is missing. The plugin may not have been properly installed.';
        }

        // 3. Check Engagement Items
        if ($items_exists) {
            echo '<h2>3. Engagement Items in Database</h2>';
            
            $total_items = $wpdb->get_var("SELECT COUNT(*) FROM $table_items");
            echo '<p>Total items in database: <strong>' . $total_items . '</strong></p>';
            
            $active_items = $wpdb->get_var("SELECT COUNT(*) FROM $table_items WHERE status = 'active'");
            echo '<p>Active items: <strong>' . $active_items . '</strong></p>';
            
            $current_time = current_time('mysql');
            $valid_items = $wpdb->get_var($wpdb->prepare(
                "SELECT COUNT(*) FROM $table_items 
                 WHERE status = 'active' 
                 AND (start_date IS NULL OR start_date <= %s)
                 AND (end_date IS NULL OR end_date >= %s)",
                $current_time,
                $current_time
            ));
            echo '<p>Valid items (active + within date range): <strong>' . $valid_items . '</strong></p>';
            
            if ($valid_items == 0) {
                if ($total_items == 0) {
                    $issues[] = 'No engagement items exist in database. Please create items from WordPress Admin → Engagement Hub.';
                } elseif ($active_items == 0) {
                    $warnings[] = 'Items exist but none are active. Please set status to "active" in database or admin panel.';
                } else {
                    $warnings[] = 'Active items exist but none are within valid date range. Check start_date and end_date.';
                }
            }
            
            // Show all items
            echo '<h3>All Engagement Items:</h3>';
            $all_items = $wpdb->get_results("SELECT * FROM $table_items ORDER BY created_at DESC");
            
            if ($all_items) {
                echo '<table>';
                echo '<tr><th>ID</th><th>Type</th><th>Title</th><th>Status</th><th>Start Date</th><th>End Date</th><th>Reward Points</th><th>Created</th></tr>';
                foreach ($all_items as $item) {
                    $status_class = $item->status === 'active' ? 'success' : 'error';
                    echo '<tr>';
                    echo '<td>' . $item->id . '</td>';
                    echo '<td>' . $item->type . '</td>';
                    echo '<td>' . esc_html($item->title) . '</td>';
                    echo '<td class="' . $status_class . '">' . $item->status . '</td>';
                    echo '<td>' . ($item->start_date ?: 'N/A') . '</td>';
                    echo '<td>' . ($item->end_date ?: 'N/A') . '</td>';
                    echo '<td>' . $item->reward_points . '</td>';
                    echo '<td>' . $item->created_at . '</td>';
                    echo '</tr>';
                }
                echo '</table>';
            } else {
                echo '<p class="warning">No items found in database.</p>';
            }
        }

        // 4. Check REST API Route
        echo '<h2>4. REST API Route Check</h2>';
        $rest_url = rest_url('twork/v1/engagement/feed');
        echo '<p>REST API Endpoint: <code>' . $rest_url . '</code></p>';
        
        // Test the endpoint
        echo '<h3>Testing Endpoint (GET method):</h3>';
        $test_user_id = 1; // Test with user ID 1
        $test_url = add_query_arg('user_id', $test_user_id, $rest_url);
        
        $response = wp_remote_get($test_url, array(
            'timeout' => 15,
            'headers' => array(
                'Content-Type' => 'application/json',
            ),
        ));
        
        if (is_wp_error($response)) {
            echo '<p class="error">✗ Request failed: ' . $response->get_error_message() . '</p>';
            $issues[] = 'REST API request failed: ' . $response->get_error_message();
        } else {
            $status_code = wp_remote_retrieve_response_code($response);
            $body = wp_remote_retrieve_body($response);
            
            echo '<p>Status Code: <strong>' . $status_code . '</strong></p>';
            
            if ($status_code === 200) {
                echo '<p class="success">✓ Endpoint is accessible and returned 200 OK</p>';
                
                $data = json_decode($body, true);
                echo '<h4>Response Data:</h4>';
                echo '<div class="json"><pre>' . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . '</pre></div>';
                
                if (isset($data['success']) && $data['success'] === true) {
                    $item_count = isset($data['data']) ? count($data['data']) : 0;
                    echo '<p class="success">✓ API returned success with ' . $item_count . ' items</p>';
                    
                    if ($item_count === 0) {
                        $warnings[] = 'API works but returned 0 items. Check database items and date ranges.';
                    }
                } else {
                    echo '<p class="error">✗ API returned success=false</p>';
                    $issues[] = 'API endpoint works but returned error: ' . ($data['message'] ?? 'Unknown error');
                }
            } elseif ($status_code === 404) {
                echo '<p class="error">✗ Endpoint returned 404 NOT FOUND</p>';
                $issues[] = 'REST API route is not registered. Try flushing permalinks: WordPress Admin → Settings → Permalinks → Save Changes';
            } else {
                echo '<p class="error">✗ Endpoint returned error code: ' . $status_code . '</p>';
                echo '<div class="json"><pre>' . esc_html($body) . '</pre></div>';
                $issues[] = 'REST API returned error code ' . $status_code;
            }
        }

        // 5. Check WordPress Permalinks
        echo '<h2>5. WordPress Configuration</h2>';
        $permalink_structure = get_option('permalink_structure');
        if (empty($permalink_structure)) {
            echo '<p class="warning">⚠ Permalinks are set to "Plain". REST API may not work properly.</p>';
            $warnings[] = 'Consider changing permalink structure to "Post name" for better REST API compatibility.';
        } else {
            echo '<p class="success">✓ Permalinks are configured: <code>' . $permalink_structure . '</code></p>';
        }

        // 6. Summary
        echo '<h2>📋 Summary</h2>';
        
        if (empty($issues) && empty($warnings)) {
            echo '<div class="info">';
            echo '<p class="success"><strong>✓ All checks passed!</strong></p>';
            echo '<p>If the app still doesn\'t show data, check:</p>';
            echo '<ul>';
            echo '<li>App backend URL configuration (AppConfig.baseUrl)</li>';
            echo '<li>User authentication token is valid</li>';
            echo '<li>Network connectivity from app to server</li>';
            echo '<li>App console logs for detailed error messages</li>';
            echo '</ul>';
            echo '</div>';
        } else {
            if (!empty($issues)) {
                echo '<h3 class="error">❌ Critical Issues Found:</h3>';
                echo '<ul>';
                foreach ($issues as $issue) {
                    echo '<li class="error">' . $issue . '</li>';
                }
                echo '</ul>';
            }
            
            if (!empty($warnings)) {
                echo '<h3 class="warning">⚠️ Warnings:</h3>';
                echo '<ul>';
                foreach ($warnings as $warning) {
                    echo '<li class="warning">' . $warning . '</li>';
                }
                echo '</ul>';
            }
        }

        // 7. Quick Fixes
        echo '<h2>🔧 Quick Fixes</h2>';
        echo '<div class="info">';
        echo '<h3>If you see 404 errors:</h3>';
        echo '<ol>';
        echo '<li>Go to WordPress Admin → Settings → Permalinks</li>';
        echo '<li>Click "Save Changes" (no need to change anything)</li>';
        echo '<li>This will flush rewrite rules and re-register REST API routes</li>';
        echo '</ol>';
        
        echo '<h3>If no items are showing:</h3>';
        echo '<ol>';
        echo '<li>Go to WordPress Admin → Engagement Hub</li>';
        echo '<li>Create a new engagement item (Banner, Quiz, etc.)</li>';
        echo '<li>Set Status to "Active"</li>';
        echo '<li>Leave Start Date and End Date empty (or set valid dates)</li>';
        echo '<li>Save the item</li>';
        echo '</ol>';
        
        echo '<h3>If tables are missing:</h3>';
        echo '<ol>';
        echo '<li>Deactivate the TWork Rewards System plugin</li>';
        echo '<li>Reactivate the plugin</li>';
        echo '<li>This will trigger table creation</li>';
        echo '</ol>';
        echo '</div>';
        ?>
    </div>
</body>
</html>

