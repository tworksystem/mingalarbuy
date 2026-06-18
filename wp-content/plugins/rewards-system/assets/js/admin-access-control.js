(function ($) {
    'use strict';

    function markUnsaved($form) {
        $form.find('.rewards-ac-unsaved').addClass('is-visible');
    }

    function initUserSearch() {
        var $el = $('#rewards-ac-user-search');
        if (!$el.length || typeof $el.select2 !== 'function') {
            return;
        }

        var cfg = window.rewardsAccessControl || {};
        $el.select2({
            ajax: {
                url: cfg.ajaxUrl || ajaxurl,
                dataType: 'json',
                delay: 250,
                data: function (params) {
                    return {
                        action: 'rewards_search_admin_users',
                        nonce: cfg.searchNonce || '',
                        q: params.term || '',
                        page: params.page || 1,
                        role_filter: cfg.searchRoleFilter || 'all'
                    };
                },
                processResults: function (data) {
                    return data;
                }
            },
            minimumInputLength: 2,
            placeholder: cfg.searchPlaceholder || 'Search users…',
            allowClear: true,
            width: 'resolve'
        });

        $el.on('change', function () {
            var userId = $(this).val();
            if (!userId) {
                return;
            }
            var url = new URL(window.location.href);
            url.searchParams.set('tab', 'users');
            url.searchParams.set('user_id', userId);
            window.location.href = url.toString();
        });
    }

    function initUserEditor() {
        var $form = $('#rewards-ac-user-form');
        if (!$form.length) {
            return;
        }

        var cfg = window.rewardsAccessControl || {};
        var $boxes = $form.find('input[name="user_page_access[]"]');

        $form.on('change', 'input[type="checkbox"]', function () {
            markUnsaved($form);
        });

        $('#rewards-ac-select-all-pages').on('click', function (e) {
            e.preventDefault();
            $boxes.prop('checked', true);
            markUnsaved($form);
        });

        $('#rewards-ac-clear-all-pages').on('click', function (e) {
            e.preventDefault();
            $boxes.prop('checked', false);
            markUnsaved($form);
        });

        $('#rewards-ac-apply-role-default').on('click', function (e) {
            e.preventDefault();
            var rolePerms = Array.isArray(cfg.editorRolePages) ? cfg.editorRolePages : [];
            if (!rolePerms.length && cfg.rolePermissions && cfg.editorRole) {
                rolePerms = cfg.rolePermissions[cfg.editorRole] || [];
            }
            $boxes.prop('checked', false);
            rolePerms.forEach(function (pageKey) {
                $form.find('input[name="user_page_access[]"][value="' + pageKey + '"]').prop('checked', true);
            });
            markUnsaved($form);
        });

        $('#rewards-ac-clear-override-form').on('submit', function (e) {
            if (!window.confirm(cfg.clearConfirm || 'Clear this user override?')) {
                e.preventDefault();
            }
        });
    }

    function initRoleMatrix() {
        var $matrix = $('#rewards-ac-role-matrix');
        if (!$matrix.length) {
            return;
        }

        $matrix.on('click', '.rewards-ac-row-toggle', function (e) {
            e.preventDefault();
            var role = $(this).data('role');
            $matrix.find('input[data-role="' + role + '"]').prop('checked', true);
        });

        $matrix.on('click', '.rewards-ac-col-toggle', function (e) {
            e.preventDefault();
            var pageKey = $(this).data('page');
            $matrix.find('input[data-page="' + pageKey + '"]').prop('checked', true);
        });
    }

    $(function () {
        initUserSearch();
        initUserEditor();
        initRoleMatrix();
    });
}(jQuery));
