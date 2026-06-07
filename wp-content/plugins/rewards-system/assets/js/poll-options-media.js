/**
 * Poll Options Admin - Dynamic repeater with WordPress Media Library integration.
 * Handles "Add Option", media upload/select, and maps mime type to media_type.
 *
 * @package TWork_Rewards
 */
(function($) {
    'use strict';

    /**
     * Map WordPress mime type to our simple media_type ('image', 'gif', 'video').
     * @param {string} mime - e.g. 'image/jpeg', 'image/gif', 'video/mp4'
     * @returns {string} 'image' | 'gif' | 'video'
     */
    function mimeToMediaType(mime) {
        if (!mime || typeof mime !== 'string') return 'image';
        var m = mime.toLowerCase();
        if (m.indexOf('gif') !== -1) return 'gif';
        if (m.indexOf('video/') === 0) return 'video';
        if (m.indexOf('image/') === 0) return 'image';
        return 'image';
    }

    /**
     * Render a small preview for the selected media.
     * @param {string} url - Media URL
     * @param {string} mediaType - 'image'|'gif'|'video'
     * @returns {string} HTML string
     */
    function getPreviewHtml(url, mediaType) {
        if (!url) return '';
        var safeUrl = String(url).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
        if (mediaType === 'video') {
            return '<div class="twork-poll-media-preview twork-poll-media-preview-video" title="' + safeUrl + '"><span class="dashicons dashicons-video-alt3"></span></div>';
        }
        return '<div class="twork-poll-media-preview"><img src="' + safeUrl + '" alt="" /></div>';
    }

    /**
     * Initialize poll options container (repeater + media buttons).
     */
    function initPollOptions() {
        var $container = $('#poll-options-container');
        if (!$container.length) return;

        // Add Option button
        $(document).off('click.tworkPollOptions', '#poll-add-option').on('click.tworkPollOptions', '#poll-add-option', function() {
            var template = document.getElementById('poll-option-template');
            if (!template || !template.content) return;
            var clone = template.content.cloneNode(true);
            var $newRow = $(clone).children().first();
            $newRow.removeClass('poll-option-template').show();
            $('#poll-options-container').append($newRow);
            initMediaButton($newRow.find('.twork-upload-media'));
        });

        // Remove Option button
        $(document).off('click.tworkPollOptions', '.poll-option-remove').on('click.tworkPollOptions', '.poll-option-remove', function() {
            var $row = $(this).closest('.poll-option-row');
            if ($row.siblings('.poll-option-row').length > 0) {
                $row.remove();
            }
        });

        // Init media buttons for existing rows
        $container.find('.twork-upload-media').each(function() {
            initMediaButton($(this));
        });
    }

    /**
     * Initialize media upload button for a specific option row.
     * Each button opens wp.media and populates its own row's fields.
     * @param {jQuery} $btn - The "Upload/Select Media" button
     */
    function initMediaButton($btn) {
        if (!$btn.length || $btn.data('twork-media-init')) return;

        $btn.data('twork-media-init', true);

        $btn.on('click', function(e) {
            e.preventDefault();
            var $row = $(this).closest('.poll-option-row');
            var $urlInput = $row.find('input.poll-option-media-url');
            var $typeInput = $row.find('input.poll-option-media-type');
            var $preview = $row.find('.twork-poll-media-preview-wrap');

            var frame = wp.media({
                library: { type: ['image', 'video'] },
                multiple: false,
                states: [
                    new wp.media.controller.Library({
                        library: wp.media.query(),
                        multiple: false,
                        title: 'Select or Upload Media',
                        filterable: 'all'
                    })
                ]
            });

            frame.on('select', function() {
                var attachment = frame.state().get('selection').first().toJSON();
                var url = attachment.url || '';
                var mime = attachment.mime || '';
                var mediaType = mimeToMediaType(mime);

                $urlInput.val(url);
                $typeInput.val(mediaType);
                $preview.html(getPreviewHtml(url, mediaType));
            });

            frame.open();
        });
    }

    /**
     * Toggle between quiz options (simple) and poll options (with media) when type changes.
     */
    function toggleOptionsUI() {
        var type = $('#type').val();
        var $quizRow = $('.quiz-options-row');
        var $pollRow = $('.poll-options-row');
        if ($quizRow.length && $pollRow.length) {
            if (type === 'poll') {
                $quizRow.hide();
                $pollRow.show();
            } else if (type === 'quiz') {
                $quizRow.show();
                $pollRow.hide();
            } else {
                $quizRow.hide();
                $pollRow.hide();
            }
        }
    }

    $(document).ready(function() {
        initPollOptions();

        $('#type').on('change', function() {
            toggleOptionsUI();
        });
        toggleOptionsUI();
    });

})(jQuery);
