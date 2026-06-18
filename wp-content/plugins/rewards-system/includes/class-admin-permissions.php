<?php
/**
 * Rewards admin page access control (per-user and per-role).
 *
 * App-facing REST routes and twork_* storage are intentionally untouched.
 *
 * @package Rewards_System
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Admin-only permissions for Rewards plugin screens.
 */
final class Rewards_Admin_Permissions
{
    public const USER_META_KEY = 'rewards_admin_page_access';
    public const OPTION_ROLE_PERMISSIONS = 'rewards_admin_role_permissions';
    public const OPTION_STRICT_MODE = 'rewards_admin_strict_mode';

    /**
     * Page registry: permission key => config.
     *
     * @return array<string, array<string, mixed>>
     */
    public static function get_pages()
    {
        return array(
            'transactions' => array(
                'label' => __('Transactions', 'twork-rewards'),
                'menu_slug' => 'twork-rewards',
                'hidden_slugs' => array('twork-rewards-transaction-edit'),
            ),
            'engagement' => array(
                'label' => __('Engagement Hub', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-engagement',
                'hidden_slugs' => array(),
            ),
            'users' => array(
                'label' => __('Users', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-users',
                'hidden_slugs' => array('twork-rewards-user-detail'),
            ),
            'point_transactions' => array(
                'label' => __('Point Transactions', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-point-transactions',
                'hidden_slugs' => array(),
            ),
            'usage' => array(
                'label' => __('Usage Analytics', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-usage',
                'hidden_slugs' => array(),
            ),
            'exchange_requests' => array(
                'label' => __('Exchange Requests', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-exchange-requests',
                'hidden_slugs' => array('twork-rewards-exchange-edit'),
            ),
            'page_content' => array(
                'label' => __('Page Content', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-page-content',
                'hidden_slugs' => array(),
            ),
            'faq' => array(
                'label' => __('FAQ Management', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-faq',
                'hidden_slugs' => array(),
            ),
            'about_us' => array(
                'label' => __('About Us', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-about-us',
                'hidden_slugs' => array(),
            ),
            'settings' => array(
                'label' => __('Settings', 'twork-rewards'),
                'menu_slug' => 'twork-rewards-settings',
                'hidden_slugs' => array(),
            ),
            'access_control' => array(
                'label' => __('Access Control', 'twork-rewards'),
                'menu_slug' => 'rewards-access-control',
                'hidden_slugs' => array(),
                'super_admin_only' => true,
            ),
        );
    }

    /**
     * Assignable page keys (excludes access_control).
     *
     * @return string[]
     */
    public static function get_assignable_page_keys()
    {
        $keys = array();
        foreach (self::get_pages() as $key => $config) {
            if (!empty($config['super_admin_only'])) {
                continue;
            }
            $keys[] = $key;
        }
        return $keys;
    }

    /**
     * Minimum capability used to register Rewards admin menus.
     *
     * @return string
     */
    public static function menu_capability()
    {
        return 'read';
    }

    /**
     * Super administrators always have full plugin admin access.
     *
     * @param int $user_id User ID.
     * @return bool
     */
    public static function is_super_admin($user_id = 0)
    {
        if ($user_id <= 0) {
            $user_id = get_current_user_id();
        }
        return user_can($user_id, 'manage_options');
    }

    /**
     * Whether strict per-user/role permissions are enforced.
     *
     * @return bool
     */
    public static function is_strict_mode()
    {
        return (bool) get_option(self::OPTION_STRICT_MODE, false);
    }

    /**
     * Resolve admin ?page= slug to permission key.
     *
     * @param string $menu_slug Admin page slug.
     * @return string Empty when unknown.
     */
    public static function page_key_from_slug($menu_slug)
    {
        $menu_slug = sanitize_key($menu_slug);
        if ($menu_slug === '') {
            return '';
        }

        foreach (self::get_pages() as $key => $config) {
            if (!empty($config['menu_slug']) && $config['menu_slug'] === $menu_slug) {
                return $key;
            }
            if (!empty($config['hidden_slugs']) && in_array($menu_slug, $config['hidden_slugs'], true)) {
                return $key;
            }
        }

        return '';
    }

    /**
     * Allowed page keys for a user.
     *
     * @param int $user_id User ID.
     * @return string[]
     */
    public static function get_allowed_page_keys_for_user($user_id)
    {
        $user_id = absint($user_id);
        if ($user_id <= 0) {
            return array();
        }

        if (self::is_super_admin($user_id)) {
            return array_keys(self::get_pages());
        }

        $user_override = get_user_meta($user_id, self::USER_META_KEY, true);
        if (is_array($user_override)) {
            $sanitized = array();
            $assignable = self::get_assignable_page_keys();
            foreach ($user_override as $page_key) {
                $page_key = sanitize_key((string) $page_key);
                if ($page_key !== '' && in_array($page_key, $assignable, true)) {
                    $sanitized[] = $page_key;
                }
            }
            $sanitized = array_values(array_unique($sanitized));
            if (!empty($sanitized) || self::user_has_explicit_empty_grant($user_id)) {
                return $sanitized;
            }
        }

        $role_permissions = self::get_role_permissions();
        $user = get_userdata($user_id);
        if ($user && !empty($user->roles)) {
            $merged = array();
            foreach ((array) $user->roles as $role) {
                if (!empty($role_permissions[$role]) && is_array($role_permissions[$role])) {
                    $merged = array_merge($merged, $role_permissions[$role]);
                }
            }
            $merged = array_values(array_unique(array_map('sanitize_key', $merged)));
            if (!empty($merged)) {
                return $merged;
            }
        }

        if (!self::is_strict_mode() && user_can($user_id, 'manage_woocommerce')) {
            return self::get_assignable_page_keys();
        }

        return array();
    }

    /**
     * User meta exists but grants zero pages (explicit deny-all for that user).
     *
     * @param int $user_id User ID.
     * @return bool
     */
    private static function user_has_explicit_empty_grant($user_id)
    {
        $raw = get_user_meta($user_id, self::USER_META_KEY, true);
        return is_array($raw);
    }

    /**
     * @return array<string, string[]>
     */
    public static function get_role_permissions()
    {
        $stored = get_option(self::OPTION_ROLE_PERMISSIONS, array());
        if (!is_array($stored)) {
            return array();
        }

        $assignable = self::get_assignable_page_keys();
        $normalized = array();
        foreach ($stored as $role => $pages) {
            $role = sanitize_key((string) $role);
            if ($role === '' || !is_array($pages)) {
                continue;
            }
            $normalized[$role] = array_values(array_intersect(
                array_map('sanitize_key', $pages),
                $assignable
            ));
        }

        return $normalized;
    }

    /**
     * @param array<string, string[]> $role_permissions Role => page keys.
     * @return void
     */
    public static function save_role_permissions($role_permissions)
    {
        if (!is_array($role_permissions)) {
            $role_permissions = array();
        }
        update_option(self::OPTION_ROLE_PERMISSIONS, self::sanitize_role_permissions_input($role_permissions), false);
    }

    /**
     * @param array<string, string[]> $input Raw POST role permissions.
     * @return array<string, string[]>
     */
    public static function sanitize_role_permissions_input($input)
    {
        $assignable = self::get_assignable_page_keys();
        $output = array();
        if (!is_array($input)) {
            return $output;
        }

        foreach ($input as $role => $pages) {
            $role = sanitize_key((string) $role);
            if ($role === '') {
                continue;
            }
            if (!is_array($pages)) {
                $pages = array();
            }
            $output[$role] = array_values(array_intersect(
                array_map('sanitize_key', $pages),
                $assignable
            ));
        }

        return $output;
    }

    /**
     * @param int $user_id User ID.
     * @param string[] $page_keys Allowed page keys.
     * @return void
     */
    public static function save_user_page_access($user_id, $page_keys)
    {
        $user_id = absint($user_id);
        if ($user_id <= 0) {
            return;
        }

        if (self::is_super_admin($user_id)) {
            return;
        }

        $assignable = self::get_assignable_page_keys();
        $sanitized = array();
        if (is_array($page_keys)) {
            foreach ($page_keys as $page_key) {
                $page_key = sanitize_key((string) $page_key);
                if ($page_key !== '' && in_array($page_key, $assignable, true)) {
                    $sanitized[] = $page_key;
                }
            }
        }

        update_user_meta($user_id, self::USER_META_KEY, array_values(array_unique($sanitized)));
    }

    /**
     * @param string $page_key Permission key.
     * @param int $user_id User ID. Defaults to current user.
     * @return bool
     */
    public static function current_user_can_access($page_key, $user_id = 0)
    {
        $page_key = sanitize_key($page_key);
        if ($page_key === '' || !isset(self::get_pages()[$page_key])) {
            return false;
        }

        if ($user_id <= 0) {
            $user_id = get_current_user_id();
        }
        if ($user_id <= 0) {
            return false;
        }

        if (!empty(self::get_pages()[$page_key]['super_admin_only'])) {
            return self::is_super_admin($user_id);
        }

        if (self::is_super_admin($user_id)) {
            return true;
        }

        $allowed = self::get_allowed_page_keys_for_user($user_id);
        return in_array($page_key, $allowed, true);
    }

    /**
     * Block direct admin page access.
     *
     * @param string $page_key Permission key.
     * @return void
     */
    public static function require_page_access($page_key)
    {
        if (!self::current_user_can_access($page_key)) {
            wp_die(
                esc_html__('You do not have permission to access this page.', 'twork-rewards'),
                esc_html__('Access denied', 'twork-rewards'),
                array('response' => 403)
            );
        }
    }

    /**
     * Block admin POST/AJAX actions.
     *
     * @param string $page_key Permission key.
     * @return void
     */
    public static function require_action_access($page_key)
    {
        if (!self::current_user_can_access($page_key)) {
            wp_die(
                esc_html__('Insufficient permissions.', 'twork-rewards'),
                esc_html__('Access denied', 'twork-rewards'),
                array('response' => 403)
            );
        }
    }

    /**
     * Register hooks.
     *
     * @return void
     */
    public static function register_hooks()
    {
        add_action('admin_menu', array(__CLASS__, 'filter_admin_menu'), 999);
        add_action('admin_init', array(__CLASS__, 'guard_direct_page_access'), 1);
        add_action('admin_post_rewards_save_access_control', array(__CLASS__, 'handle_save_access_control'));
        add_action('wp_ajax_rewards_search_admin_users', array(__CLASS__, 'ajax_search_admin_users'));
    }

    /**
     * Hide unauthorized submenu entries.
     *
     * @return void
     */
    public static function filter_admin_menu()
    {
        global $submenu;

        $parent_slug = 'twork-rewards';
        if (empty($submenu[$parent_slug]) || !is_array($submenu[$parent_slug])) {
            return;
        }

        foreach ($submenu[$parent_slug] as $index => $item) {
            if (!is_array($item) || empty($item[2])) {
                continue;
            }
            $page_key = self::page_key_from_slug((string) $item[2]);
            if ($page_key === '') {
                continue;
            }
            if (!self::current_user_can_access($page_key)) {
                unset($submenu[$parent_slug][$index]);
            }
        }

        $submenu[$parent_slug] = array_values($submenu[$parent_slug]);

        if (empty($submenu[$parent_slug])) {
            remove_menu_page($parent_slug);
        }
    }

    /**
     * Early guard for direct ?page= access on Rewards screens.
     *
     * @return void
     */
    public static function guard_direct_page_access()
    {
        if (!is_admin() || !is_user_logged_in() || !isset($_GET['page'])) {
            return;
        }

        $menu_slug = sanitize_key(wp_unslash($_GET['page']));
        $page_key = self::page_key_from_slug($menu_slug);
        if ($page_key === '') {
            return;
        }

        if (!self::current_user_can_access($page_key)) {
            wp_die(
                esc_html__('You do not have permission to access this page.', 'twork-rewards'),
                esc_html__('Access denied', 'twork-rewards'),
                array('response' => 403)
            );
        }
    }

    /**
     * Valid Access Control tab slug.
     *
     * @param string $tab Raw tab.
     * @return string
     */
    private static function sanitize_tab($tab)
    {
        $tab = sanitize_key($tab);
        $allowed = array('users', 'roles', 'settings');
        return in_array($tab, $allowed, true) ? $tab : 'users';
    }

    /**
     * Build admin URL for Access Control screen.
     *
     * @param array<string, scalar> $args Query args.
     * @return string
     */
    private static function access_control_url($args = array())
    {
        $defaults = array(
            'page' => 'rewards-access-control',
            'tab' => 'users',
        );
        return add_query_arg(array_merge($defaults, $args), admin_url('admin.php'));
    }

    /**
     * How a user's effective access is derived.
     *
     * @param int $user_id User ID.
     * @return string override|role|legacy|none
     */
    public static function get_user_access_source($user_id)
    {
        $user_id = absint($user_id);
        if ($user_id <= 0) {
            return 'none';
        }

        if (self::is_super_admin($user_id)) {
            return 'administrator';
        }

        if (self::user_has_explicit_empty_grant($user_id)) {
            return 'override';
        }

        $raw = get_user_meta($user_id, self::USER_META_KEY, true);
        if (is_array($raw) && !empty($raw)) {
            return 'override';
        }

        $user = get_userdata($user_id);
        if ($user && !empty($user->roles)) {
            $role_permissions = self::get_role_permissions();
            foreach ((array) $user->roles as $role) {
                if (!empty($role_permissions[$role])) {
                    return 'role';
                }
            }
        }

        if (!self::is_strict_mode() && user_can($user_id, 'manage_woocommerce')) {
            return 'legacy';
        }

        return 'none';
    }

    /**
     * Role-default page keys for a user (no override / legacy).
     *
     * @param int $user_id User ID.
     * @return string[]
     */
    public static function get_role_default_pages_for_user($user_id)
    {
        $user_id = absint($user_id);
        if ($user_id <= 0 || self::is_super_admin($user_id)) {
            return array();
        }

        $role_permissions = self::get_role_permissions();
        $user = get_userdata($user_id);
        if (!$user || empty($user->roles)) {
            return array();
        }

        $merged = array();
        foreach ((array) $user->roles as $role) {
            if (!empty($role_permissions[$role]) && is_array($role_permissions[$role])) {
                $merged = array_merge($merged, $role_permissions[$role]);
            }
        }

        return array_values(array_unique(array_map('sanitize_key', $merged)));
    }

    /**
     * Remove per-user override meta.
     *
     * @param int $user_id User ID.
     * @return void
     */
    public static function clear_user_page_override($user_id)
    {
        $user_id = absint($user_id);
        if ($user_id <= 0 || self::is_super_admin($user_id)) {
            return;
        }
        delete_user_meta($user_id, self::USER_META_KEY);
    }

    /**
     * Roles for the default staff list (admin-capable, excludes storefront-only roles).
     *
     * @return string[]
     */
    public static function get_staff_role_slugs()
    {
        $wp_roles = wp_roles();
        if (!$wp_roles || empty($wp_roles->roles)) {
            return array();
        }

        $exclude = array('customer', 'subscriber');
        $staff = array();
        foreach (array_keys($wp_roles->roles) as $role_slug) {
            if (!in_array($role_slug, $exclude, true)) {
                $staff[] = $role_slug;
            }
        }

        return $staff;
    }

    /**
     * Role filter options for the Users overview list.
     *
     * @return array<string, string> slug => label
     */
    public static function get_user_list_role_filters()
    {
        $filters = array(
            'staff' => __('Staff & Administrators (excl. Customers)', 'twork-rewards'),
            'all' => __('All WordPress users (incl. Customers)', 'twork-rewards'),
        );

        $wp_roles = wp_roles();
        if ($wp_roles && !empty($wp_roles->roles)) {
            foreach ($wp_roles->roles as $role_slug => $role_data) {
                $filters[$role_slug] = translate_user_role($role_data['name']);
            }
        }

        return $filters;
    }

    /**
     * Sanitize role filter for user list queries.
     *
     * @param string $role_filter Raw filter.
     * @return string
     */
    public static function sanitize_user_list_role_filter($role_filter)
    {
        $role_filter = sanitize_key($role_filter);
        if ($role_filter === '') {
            return 'staff';
        }

        if (in_array($role_filter, array('staff', 'all'), true)) {
            return $role_filter;
        }

        $wp_roles = wp_roles();
        if ($wp_roles && isset($wp_roles->roles[$role_filter])) {
            return $role_filter;
        }

        return 'staff';
    }

    /**
     * Build WP_User_Query args for Access Control user lists.
     *
     * @param array<string, mixed> $args search, paged, per_page, role_filter.
     * @return array<string, mixed>
     */
    public static function build_user_list_query_args($args = array())
    {
        $search = isset($args['search']) ? sanitize_text_field($args['search']) : '';
        $paged = isset($args['paged']) ? max(1, absint($args['paged'])) : 1;
        $per_page = isset($args['per_page']) ? max(1, min(100, absint($args['per_page']))) : 20;
        $role_filter = self::sanitize_user_list_role_filter(
            isset($args['role_filter']) ? (string) $args['role_filter'] : 'staff'
        );

        $query_args = array(
            'number' => $per_page,
            'offset' => ($paged - 1) * $per_page,
            'orderby' => 'display_name',
            'order' => 'ASC',
            'count_total' => true,
        );

        if ($role_filter === 'all') {
            // No role restriction — includes administrators, customers, and all roles.
        } elseif ($role_filter === 'staff') {
            $staff_roles = self::get_staff_role_slugs();
            if (!empty($staff_roles)) {
                $query_args['role__in'] = $staff_roles;
            } else {
                $query_args['role__not_in'] = array('customer', 'subscriber');
            }
        } else {
            $query_args['role'] = $role_filter;
        }

        if ($search !== '') {
            $query_args['search'] = '*' . esc_attr($search) . '*';
            $query_args['search_columns'] = array('user_login', 'user_nicename', 'display_name', 'user_email');
        }

        return $query_args;
    }

    /**
     * Paginated overview rows for Users tab.
     *
     * @param array<string, mixed> $args Query args.
     * @return array{items: array<int, array<string, mixed>>, total: int}
     */
    public static function get_users_access_overview($args = array())
    {
        $per_page = 20;
        $assignable_count = count(self::get_assignable_page_keys());
        $query_args = self::build_user_list_query_args($args);

        $query = new WP_User_Query($query_args);
        $items = array();

        foreach ((array) $query->get_results() as $user) {
            if (!($user instanceof WP_User)) {
                continue;
            }

            $is_administrator = self::is_super_admin((int) $user->ID);
            $allowed = self::get_allowed_page_keys_for_user((int) $user->ID);
            $roles = array_map('translate_user_role', array_map(function ($role) {
                $wp_roles = wp_roles();
                return isset($wp_roles->roles[$role]['name']) ? $wp_roles->roles[$role]['name'] : $role;
            }, (array) $user->roles));

            $items[] = array(
                'id' => (int) $user->ID,
                'display_name' => $user->display_name,
                'user_login' => $user->user_login,
                'email' => $user->user_email,
                'roles_label' => implode(', ', $roles),
                'primary_role' => !empty($user->roles[0]) ? $user->roles[0] : '',
                'source' => self::get_user_access_source((int) $user->ID),
                'is_administrator' => $is_administrator,
                'page_count' => count($allowed),
                'assignable_count' => $assignable_count,
                'has_override' => self::user_has_explicit_empty_grant((int) $user->ID)
                    || is_array(get_user_meta((int) $user->ID, self::USER_META_KEY, true)),
            );
        }

        return array(
            'items' => $items,
            'total' => (int) $query->get_total(),
            'per_page' => $per_page,
        );
    }

    /**
     * Human label for access source badge.
     *
     * @param string $source Source key.
     * @return string
     */
    private static function access_source_label($source)
    {
        $map = array(
            'administrator' => __('Administrator', 'twork-rewards'),
            'override' => __('Override', 'twork-rewards'),
            'role' => __('Role', 'twork-rewards'),
            'legacy' => __('Legacy', 'twork-rewards'),
            'none' => __('None', 'twork-rewards'),
        );
        return isset($map[$source]) ? $map[$source] : $map['none'];
    }

    /**
     * Render Access Control admin page.
     *
     * @return void
     */
    public static function render_access_control_page()
    {
        self::require_page_access('access_control');

        $current_tab = self::sanitize_tab(isset($_GET['tab']) ? wp_unslash($_GET['tab']) : 'users');
        $selected_user_id = isset($_GET['user_id']) ? absint($_GET['user_id']) : 0;
        $selected_user = ($selected_user_id > 0) ? get_userdata($selected_user_id) : false;

        $role_permissions = self::get_role_permissions();
        $editable_roles = wp_roles()->roles;
        $assignable_keys = self::get_assignable_page_keys();
        $pages = self::get_pages();
        $strict_mode = self::is_strict_mode();

        if (isset($_GET['saved']) && (string) $_GET['saved'] === '1') {
            echo '<div class="notice notice-success is-dismissible"><p>' . esc_html__('Access settings saved.', 'twork-rewards') . '</p></div>';
        }
        if (isset($_GET['cleared']) && (string) $_GET['cleared'] === '1') {
            echo '<div class="notice notice-success is-dismissible"><p>' . esc_html__('User override cleared. Role defaults now apply.', 'twork-rewards') . '</p></div>';
        }

        $overview_search = isset($_GET['s']) ? sanitize_text_field(wp_unslash($_GET['s'])) : '';
        $overview_paged = isset($_GET['paged']) ? max(1, absint($_GET['paged'])) : 1;
        $role_filter = self::sanitize_user_list_role_filter(
            isset($_GET['role_filter']) ? wp_unslash($_GET['role_filter']) : 'staff'
        );
        $role_filter_options = self::get_user_list_role_filters();
        $overview = array('items' => array(), 'total' => 0, 'per_page' => 20);
        if ($current_tab === 'users') {
            $overview = self::get_users_access_overview(array(
                'search' => $overview_search,
                'paged' => $overview_paged,
                'role_filter' => $role_filter,
            ));
        }

        if ($selected_user_id > 0 && !$selected_user) {
            echo '<div class="notice notice-warning is-dismissible"><p>' . esc_html__('User not found or cannot be edited.', 'twork-rewards') . '</p></div>';
        }
        ?>
        <div class="wrap rewards-ac-wrap">
            <h1><?php esc_html_e('Rewards Access Control', 'twork-rewards'); ?></h1>
            <p><?php esc_html_e('Manage which WordPress users can open each Rewards admin page. Administrators always have full access.', 'twork-rewards'); ?></p>

            <nav class="rewards-ac-nav" aria-label="<?php esc_attr_e('Access control sections', 'twork-rewards'); ?>">
                <a href="<?php echo esc_url(self::access_control_url(array('tab' => 'users'))); ?>"
                   class="nav-tab <?php echo $current_tab === 'users' ? 'nav-tab-active' : ''; ?>">
                    <?php esc_html_e('Users', 'twork-rewards'); ?>
                </a>
                <a href="<?php echo esc_url(self::access_control_url(array('tab' => 'roles'))); ?>"
                   class="nav-tab <?php echo $current_tab === 'roles' ? 'nav-tab-active' : ''; ?>">
                    <?php esc_html_e('Role defaults', 'twork-rewards'); ?>
                </a>
                <a href="<?php echo esc_url(self::access_control_url(array('tab' => 'settings'))); ?>"
                   class="nav-tab <?php echo $current_tab === 'settings' ? 'nav-tab-active' : ''; ?>">
                    <?php esc_html_e('Settings', 'twork-rewards'); ?>
                </a>
            </nav>

            <?php if ($current_tab === 'users') : ?>
                <div class="rewards-ac-panel">
                    <div class="rewards-ac-toolbar">
                        <form method="get" action="<?php echo esc_url(admin_url('admin.php')); ?>">
                            <input type="hidden" name="page" value="rewards-access-control" />
                            <input type="hidden" name="tab" value="users" />
                            <?php if ($selected_user_id > 0) : ?>
                                <input type="hidden" name="user_id" value="<?php echo esc_attr((string) $selected_user_id); ?>" />
                            <?php endif; ?>
                            <label for="rewards-ac-role-filter" class="screen-reader-text"><?php esc_html_e('Filter by role', 'twork-rewards'); ?></label>
                            <select id="rewards-ac-role-filter" name="role_filter">
                                <?php foreach ($role_filter_options as $filter_key => $filter_label) : ?>
                                    <option value="<?php echo esc_attr($filter_key); ?>" <?php selected($role_filter, $filter_key); ?>>
                                        <?php echo esc_html($filter_label); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <label for="rewards-ac-list-search" class="screen-reader-text"><?php esc_html_e('Search users', 'twork-rewards'); ?></label>
                            <input type="search" id="rewards-ac-list-search" name="s" value="<?php echo esc_attr($overview_search); ?>" placeholder="<?php esc_attr_e('Search name or email…', 'twork-rewards'); ?>" />
                            <?php submit_button(__('Filter', 'twork-rewards'), 'secondary', 'submit', false); ?>
                        </form>
                        <div>
                            <label for="rewards-ac-user-search"><strong><?php esc_html_e('Quick pick user', 'twork-rewards'); ?></strong></label>
                            <select id="rewards-ac-user-search" style="min-width: 280px;">
                                <?php if ($selected_user) : ?>
                                    <option value="<?php echo esc_attr((string) $selected_user_id); ?>" selected>
                                        <?php echo esc_html($selected_user->display_name . ' (' . $selected_user->user_login . ')'); ?>
                                    </option>
                                <?php endif; ?>
                            </select>
                        </div>
                    </div>

                    <table class="widefat striped">
                        <thead>
                            <tr>
                                <th><?php esc_html_e('User', 'twork-rewards'); ?></th>
                                <th><?php esc_html_e('Email', 'twork-rewards'); ?></th>
                                <th><?php esc_html_e('Role', 'twork-rewards'); ?></th>
                                <th><?php esc_html_e('Source', 'twork-rewards'); ?></th>
                                <th><?php esc_html_e('Pages', 'twork-rewards'); ?></th>
                                <th><?php esc_html_e('Actions', 'twork-rewards'); ?></th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($overview['items'])) : ?>
                                <tr>
                                    <td colspan="6"><?php esc_html_e('No users found.', 'twork-rewards'); ?></td>
                                </tr>
                            <?php else : ?>
                                <?php foreach ($overview['items'] as $row) : ?>
                                    <tr>
                                        <td>
                                            <strong><?php echo esc_html($row['display_name']); ?></strong><br />
                                            <code><?php echo esc_html($row['user_login']); ?></code>
                                        </td>
                                        <td><?php echo esc_html($row['email']); ?></td>
                                        <td><?php echo esc_html($row['roles_label']); ?></td>
                                        <td>
                                            <span class="rewards-ac-badge rewards-ac-badge--<?php echo esc_attr($row['source']); ?>">
                                                <?php echo esc_html(self::access_source_label($row['source'])); ?>
                                            </span>
                                        </td>
                                        <td>
                                            <?php if (!empty($row['is_administrator'])) : ?>
                                                <?php esc_html_e('All', 'twork-rewards'); ?>
                                            <?php else : ?>
                                                <?php
                                                echo esc_html(sprintf(
                                                    /* translators: 1: allowed page count, 2: total assignable pages */
                                                    __('%1$d / %2$d', 'twork-rewards'),
                                                    (int) $row['page_count'],
                                                    (int) $row['assignable_count']
                                                ));
                                                ?>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <a class="button button-small" href="<?php echo esc_url(self::access_control_url(array(
                                                'tab' => 'users',
                                                'user_id' => $row['id'],
                                                's' => $overview_search,
                                                'paged' => $overview_paged,
                                                'role_filter' => $role_filter,
                                            ))); ?>">
                                                <?php echo !empty($row['is_administrator'])
                                                    ? esc_html__('View', 'twork-rewards')
                                                    : esc_html__('Edit', 'twork-rewards'); ?>
                                            </a>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            <?php endif; ?>
                        </tbody>
                    </table>

                    <?php if ($overview['total'] > (int) $overview['per_page']) : ?>
                        <div class="tablenav bottom">
                            <div class="tablenav-pages">
                                <?php
                                $pagination_base = add_query_arg(array(
                                    'page' => 'rewards-access-control',
                                    'tab' => 'users',
                                    's' => $overview_search,
                                    'role_filter' => $role_filter,
                                    'user_id' => $selected_user_id > 0 ? $selected_user_id : null,
                                    'paged' => '%#%',
                                ), admin_url('admin.php'));
                                echo wp_kses_post(paginate_links(array(
                                    'base' => $pagination_base,
                                    'format' => '',
                                    'prev_text' => __('&laquo;'),
                                    'next_text' => __('&raquo;'),
                                    'total' => (int) ceil($overview['total'] / (int) $overview['per_page']),
                                    'current' => $overview_paged,
                                )));
                                ?>
                            </div>
                        </div>
                    <?php endif; ?>
                </div>

                <?php if ($selected_user) : ?>
                    <?php
                    $is_selected_admin = self::is_super_admin($selected_user_id);
                    $raw = get_user_meta($selected_user_id, self::USER_META_KEY, true);
                    $user_allowed = is_array($raw) ? $raw : self::get_allowed_page_keys_for_user($selected_user_id);
                    $source = self::get_user_access_source($selected_user_id);
                    ?>
                    <div class="rewards-ac-panel rewards-ac-editor" id="rewards-ac-user-editor">
                        <div class="rewards-ac-editor__header">
                            <div>
                                <h2 style="margin:0 0 6px;">
                                    <?php echo esc_html($selected_user->display_name); ?>
                                    <span class="rewards-ac-badge rewards-ac-badge--<?php echo esc_attr($source); ?>">
                                        <?php echo esc_html(self::access_source_label($source)); ?>
                                    </span>
                                </h2>
                                <p class="rewards-ac-editor__meta">
                                    <?php echo esc_html($selected_user->user_email); ?>
                                    — <?php echo esc_html($selected_user->user_login); ?>
                                </p>
                            </div>
                            <?php if (!$is_selected_admin) : ?>
                                <div class="rewards-ac-editor__actions">
                                    <button type="button" class="button" id="rewards-ac-select-all-pages"><?php esc_html_e('Select all', 'twork-rewards'); ?></button>
                                    <button type="button" class="button" id="rewards-ac-clear-all-pages"><?php esc_html_e('Clear all', 'twork-rewards'); ?></button>
                                    <button type="button" class="button" id="rewards-ac-apply-role-default"><?php esc_html_e('Apply role default', 'twork-rewards'); ?></button>
                                </div>
                            <?php endif; ?>
                        </div>

                        <?php if ($is_selected_admin) : ?>
                            <p><em><?php esc_html_e('Administrators always have full access to every Rewards page and cannot be restricted.', 'twork-rewards'); ?></em></p>
                            <div class="rewards-ac-checkbox-grid">
                                <?php foreach ($assignable_keys as $page_key) : ?>
                                    <label>
                                        <input type="checkbox" checked disabled />
                                        <?php echo esc_html($pages[$page_key]['label']); ?>
                                    </label>
                                <?php endforeach; ?>
                            </div>
                        <?php else : ?>
                        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" id="rewards-ac-user-form">
                            <?php wp_nonce_field('rewards_save_access_control', 'rewards_access_nonce'); ?>
                            <input type="hidden" name="action" value="rewards_save_access_control" />
                            <input type="hidden" name="save_section" value="user" />
                            <input type="hidden" name="user_id" value="<?php echo esc_attr((string) $selected_user_id); ?>" />
                            <input type="hidden" name="redirect_tab" value="users" />

                            <div class="rewards-ac-checkbox-grid">
                                <?php foreach ($assignable_keys as $page_key) : ?>
                                    <label>
                                        <input type="checkbox"
                                               name="user_page_access[]"
                                               value="<?php echo esc_attr($page_key); ?>"
                                            <?php checked(in_array($page_key, $user_allowed, true)); ?> />
                                        <?php echo esc_html($pages[$page_key]['label']); ?>
                                    </label>
                                <?php endforeach; ?>
                            </div>

                            <p class="rewards-ac-hint"><?php esc_html_e('Changes are not saved until you click Save user access.', 'twork-rewards'); ?></p>
                            <?php submit_button(__('Save user access', 'twork-rewards')); ?>
                            <span class="rewards-ac-unsaved" aria-live="polite"><?php esc_html_e('Unsaved changes', 'twork-rewards'); ?></span>
                        </form>

                        <?php endif; ?>
                        <?php if (!$is_selected_admin && $source === 'override') : ?>
                            <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" id="rewards-ac-clear-override-form" style="margin-top:12px;">
                                <?php wp_nonce_field('rewards_save_access_control', 'rewards_access_nonce'); ?>
                                <input type="hidden" name="action" value="rewards_save_access_control" />
                                <input type="hidden" name="save_section" value="clear_user" />
                                <input type="hidden" name="user_id" value="<?php echo esc_attr((string) $selected_user_id); ?>" />
                                <input type="hidden" name="redirect_tab" value="users" />
                                <?php submit_button(__('Clear user override', 'twork-rewards'), 'delete', 'submit', false); ?>
                            </form>
                        <?php endif; ?>
                    </div>
                <?php endif; ?>

            <?php elseif ($current_tab === 'roles') : ?>
                <div class="rewards-ac-panel">
                    <p><?php esc_html_e('Default page access per role. Used when a user has no individual override saved.', 'twork-rewards'); ?></p>
                    <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                        <?php wp_nonce_field('rewards_save_access_control', 'rewards_access_nonce'); ?>
                        <input type="hidden" name="action" value="rewards_save_access_control" />
                        <input type="hidden" name="save_section" value="roles" />
                        <input type="hidden" name="redirect_tab" value="roles" />
                        <div class="rewards-ac-matrix-wrap">
                            <table class="widefat striped rewards-ac-matrix" id="rewards-ac-role-matrix">
                                <thead>
                                    <tr>
                                        <th><?php esc_html_e('Role', 'twork-rewards'); ?></th>
                                        <?php foreach ($assignable_keys as $page_key) : ?>
                                            <th>
                                                <?php echo esc_html($pages[$page_key]['label']); ?>
                                                <button type="button" class="button-link rewards-ac-col-toggle" data-page="<?php echo esc_attr($page_key); ?>">
                                                    <?php esc_html_e('All', 'twork-rewards'); ?>
                                                </button>
                                            </th>
                                        <?php endforeach; ?>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($editable_roles as $role_key => $role_data) : ?>
                                        <?php if ($role_key === 'administrator') : ?>
                                            <?php continue; ?>
                                        <?php endif; ?>
                                        <?php $role_allowed = isset($role_permissions[$role_key]) ? (array) $role_permissions[$role_key] : array(); ?>
                                        <tr>
                                            <td>
                                                <strong><?php echo esc_html(translate_user_role($role_data['name'])); ?></strong>
                                                <button type="button" class="button-link rewards-ac-row-toggle" data-role="<?php echo esc_attr($role_key); ?>">
                                                    <?php esc_html_e('Select row', 'twork-rewards'); ?>
                                                </button>
                                            </td>
                                            <?php foreach ($assignable_keys as $page_key) : ?>
                                                <td>
                                                    <input type="checkbox"
                                                           name="role_permissions[<?php echo esc_attr($role_key); ?>][]"
                                                           value="<?php echo esc_attr($page_key); ?>"
                                                           data-role="<?php echo esc_attr($role_key); ?>"
                                                           data-page="<?php echo esc_attr($page_key); ?>"
                                                           aria-label="<?php echo esc_attr(sprintf(
                                                               /* translators: 1: role name, 2: page label */
                                                               __('%1$s — %2$s', 'twork-rewards'),
                                                               translate_user_role($role_data['name']),
                                                               $pages[$page_key]['label']
                                                           )); ?>"
                                                        <?php checked(in_array($page_key, $role_allowed, true)); ?> />
                                                </td>
                                            <?php endforeach; ?>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                        <?php submit_button(__('Save role defaults', 'twork-rewards')); ?>
                    </form>
                </div>

            <?php else : ?>
                <div class="rewards-ac-panel">
                    <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                        <?php wp_nonce_field('rewards_save_access_control', 'rewards_access_nonce'); ?>
                        <input type="hidden" name="action" value="rewards_save_access_control" />
                        <input type="hidden" name="save_section" value="global" />
                        <input type="hidden" name="redirect_tab" value="settings" />
                        <label>
                            <input type="checkbox" name="rewards_admin_strict_mode" value="1" <?php checked($strict_mode); ?> />
                            <?php esc_html_e('Strict mode: only explicitly assigned users/roles may access Rewards pages (disable legacy Shop Manager full access).', 'twork-rewards'); ?>
                        </label>
                        <?php submit_button(__('Save settings', 'twork-rewards')); ?>
                    </form>
                    <ul class="rewards-ac-settings-list">
                        <li><?php esc_html_e('Use the Users tab to assign page access per WordPress user.', 'twork-rewards'); ?></li>
                        <li><?php esc_html_e('Role defaults apply when no user override is saved.', 'twork-rewards'); ?></li>
                        <li><?php esc_html_e('Administrators always have full access and cannot be restricted.', 'twork-rewards'); ?></li>
                    </ul>
                </div>
            <?php endif; ?>
        </div>
        <?php
        self::enqueue_access_control_assets($selected_user, $role_permissions);
    }

    /**
     * @param WP_User|false $selected_user Selected user object.
     * @param array<string, string[]> $role_permissions Role permissions map.
     * @return void
     */
    private static function enqueue_access_control_assets($selected_user, $role_permissions)
    {
        $plugin_file = defined('TWORK_REWARDS_PLUGIN_DIR')
            ? TWORK_REWARDS_PLUGIN_DIR . 'rewards-system.php'
            : dirname(__DIR__) . '/rewards-system.php';
        $css_path = dirname($plugin_file) . '/assets/css/admin-access-control.css';
        $js_path = dirname($plugin_file) . '/assets/js/admin-access-control.js';

        if (file_exists($css_path)) {
            wp_enqueue_style(
                'rewards-admin-access-control',
                plugins_url('assets/css/admin-access-control.css', $plugin_file),
                array(),
                (string) filemtime($css_path)
            );
        }

        if (wp_script_is('select2', 'registered') || wp_script_is('select2', 'enqueued')) {
            wp_enqueue_script('select2');
            wp_enqueue_style('select2');
        } else {
            wp_enqueue_script(
                'rewards-select2-cdn',
                'https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js',
                array('jquery'),
                '4.1.0-rc.0',
                true
            );
            wp_enqueue_style(
                'rewards-select2-cdn',
                'https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css',
                array(),
                '4.1.0-rc.0'
            );
        }

        if (file_exists($js_path)) {
            $script_deps = array('jquery');
            if (wp_script_is('select2', 'enqueued')) {
                $script_deps[] = 'select2';
            } elseif (wp_script_is('rewards-select2-cdn', 'enqueued')) {
                $script_deps[] = 'rewards-select2-cdn';
            }

            wp_enqueue_script(
                'rewards-admin-access-control',
                plugins_url('assets/js/admin-access-control.js', $plugin_file),
                $script_deps,
                (string) filemtime($js_path),
                true
            );

            $editor_role = ($selected_user instanceof WP_User && !empty($selected_user->roles[0]))
                ? $selected_user->roles[0]
                : '';
            $editor_role_pages = ($selected_user instanceof WP_User)
                ? self::get_role_default_pages_for_user((int) $selected_user->ID)
                : array();

            wp_localize_script('rewards-admin-access-control', 'rewardsAccessControl', array(
                'ajaxUrl' => admin_url('admin-ajax.php'),
                'searchNonce' => wp_create_nonce('rewards_search_admin_users'),
                'searchPlaceholder' => __('Search users…', 'twork-rewards'),
                'clearConfirm' => __('Clear this user override and revert to role defaults?', 'twork-rewards'),
                'rolePermissions' => $role_permissions,
                'editorRole' => $editor_role,
                'editorRolePages' => $editor_role_pages,
                'searchRoleFilter' => 'all',
            ));
        }
    }

    /**
     * Save access control form.
     *
     * @return void
     */
    public static function handle_save_access_control()
    {
        if (!self::is_super_admin()) {
            wp_die(esc_html__('Insufficient permissions.', 'twork-rewards'), '', array('response' => 403));
        }

        check_admin_referer('rewards_save_access_control', 'rewards_access_nonce');

        $section = isset($_POST['save_section']) ? sanitize_key(wp_unslash($_POST['save_section'])) : '';

        if ($section === 'global') {
            $strict = !empty($_POST['rewards_admin_strict_mode']);
            update_option(self::OPTION_STRICT_MODE, $strict ? 1 : 0, false);
        } elseif ($section === 'roles') {
            $input = isset($_POST['role_permissions']) && is_array($_POST['role_permissions'])
                ? wp_unslash($_POST['role_permissions'])
                : array();
            self::save_role_permissions($input);
            update_option(self::OPTION_STRICT_MODE, 1, false);
        } elseif ($section === 'user') {
            $user_id = isset($_POST['user_id']) ? absint($_POST['user_id']) : 0;
            if ($user_id > 0 && !self::is_super_admin($user_id)) {
                $pages = isset($_POST['user_page_access']) && is_array($_POST['user_page_access'])
                    ? wp_unslash($_POST['user_page_access'])
                    : array();
                self::save_user_page_access($user_id, $pages);
                update_option(self::OPTION_STRICT_MODE, 1, false);
            }
        } elseif ($section === 'clear_user') {
            $user_id = isset($_POST['user_id']) ? absint($_POST['user_id']) : 0;
            if ($user_id > 0 && !self::is_super_admin($user_id)) {
                self::clear_user_page_override($user_id);
            }
            $redirect_user = $user_id;
            $redirect_tab = 'users';
            $redirect_args = array(
                'page' => 'rewards-access-control',
                'tab' => $redirect_tab,
                'cleared' => '1',
            );
            if ($redirect_user > 0) {
                $redirect_args['user_id'] = $redirect_user;
            }
            wp_safe_redirect(add_query_arg($redirect_args, admin_url('admin.php')));
            exit;
        }

        $redirect_user = isset($_POST['user_id']) ? absint($_POST['user_id']) : 0;
        $redirect_tab = isset($_POST['redirect_tab']) ? self::sanitize_tab(wp_unslash($_POST['redirect_tab'])) : 'users';
        $redirect_args = array(
            'page' => 'rewards-access-control',
            'tab' => $redirect_tab,
            'saved' => '1',
        );
        if ($redirect_user > 0) {
            $redirect_args['user_id'] = $redirect_user;
        }

        wp_safe_redirect(add_query_arg($redirect_args, admin_url('admin.php')));
        exit;
    }

    /**
     * AJAX user search for Access Control page.
     *
     * @return void
     */
    public static function ajax_search_admin_users()
    {
        if (!self::is_super_admin()) {
            wp_send_json_error(array('message' => __('Insufficient permissions.', 'twork-rewards')), 403);
        }

        check_ajax_referer('rewards_search_admin_users', 'nonce');

        $term = isset($_GET['q']) ? sanitize_text_field(wp_unslash($_GET['q'])) : '';
        $paged = isset($_GET['page']) ? max(1, absint($_GET['page'])) : 1;
        $per_page = 20;
        $role_filter = isset($_GET['role_filter'])
            ? self::sanitize_user_list_role_filter(wp_unslash($_GET['role_filter']))
            : 'all';

        if (strlen($term) < 2) {
            wp_send_json(array('results' => array(), 'pagination' => array('more' => false)));
        }

        $query = new WP_User_Query(self::build_user_list_query_args(array(
            'search' => $term,
            'paged' => $paged,
            'per_page' => $per_page,
            'role_filter' => $role_filter,
        )));

        $results = array();
        foreach ((array) $query->get_results() as $user) {
            if (!($user instanceof WP_User)) {
                continue;
            }

            if (self::is_super_admin((int) $user->ID)) {
                $role_labels = array(__('Administrator', 'twork-rewards'));
            } else {
                $role_labels = array();
                foreach ((array) $user->roles as $role_slug) {
                    $wp_roles = wp_roles();
                    $role_labels[] = isset($wp_roles->roles[$role_slug]['name'])
                        ? translate_user_role($wp_roles->roles[$role_slug]['name'])
                        : $role_slug;
                }
            }

            $label = $user->display_name . ' (' . $user->user_login . ')';
            if (!empty($role_labels)) {
                $label .= ' — ' . implode(', ', $role_labels);
            }

            $results[] = array(
                'id' => (int) $user->ID,
                'text' => $label,
            );
        }

        $total = (int) $query->get_total();
        wp_send_json(array(
            'results' => $results,
            'pagination' => array('more' => ($paged * $per_page) < $total),
        ));
    }
}
