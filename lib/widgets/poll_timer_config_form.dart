import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable form widget for configuring poll timer durations.
/// Use in poll creation/configuration UIs. Callbacks receive the typed values.
///
/// Example API payload when submitting:
/// ```dart
/// {
///   'poll_duration': 15,                      // minutes
///   'result_display_duration_seconds': 90,   // total seconds (e.g. 1 min 30 sec)
/// }
/// ```
class PollTimerConfigForm extends StatefulWidget {
  final int initialPollDuration;
  /// Total seconds for the result phase (canonical; matches WordPress `result_display_duration_seconds`).
  final int initialResultDisplayDurationSeconds;
  final ValueChanged<Map<String, dynamic>>? onSubmit;
  final AutovalidateMode autovalidateMode;

  const PollTimerConfigForm({
    super.key,
    this.initialPollDuration = 15,
    this.initialResultDisplayDurationSeconds = 60,
    this.onSubmit,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  @override
  State<PollTimerConfigForm> createState() => _PollTimerConfigFormState();
}

class _PollTimerConfigFormState extends State<PollTimerConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _pollDurationController;
  late TextEditingController _resultMinutesController;
  late TextEditingController _resultSecondsController;

  @override
  void initState() {
    super.initState();
    _pollDurationController = TextEditingController(
      text: widget.initialPollDuration.toString(),
    );
    final capped = widget.initialResultDisplayDurationSeconds.clamp(0, 60 * 60 + 59);
    final rm = capped ~/ 60;
    final rs = capped % 60;
    _resultMinutesController = TextEditingController(text: rm.toString());
    _resultSecondsController = TextEditingController(text: rs.toString());
  }

  @override
  void dispose() {
    _pollDurationController.dispose();
    _resultMinutesController.dispose();
    _resultSecondsController.dispose();
    super.dispose();
  }

  int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  String? _validatePollDuration(String? value) {
    final v = _parseInt(value ?? '');
    if (v == null || v <= 0) {
      return 'Poll duration cannot be empty or 0. Enter minutes (e.g. 3, 15, 45).';
    }
    if (v > 1440) {
      return 'Maximum 1440 minutes (24 hours).';
    }
    return null;
  }

  String? _validateResultMinutes(String? value) {
    final v = _parseInt(value ?? '');
    if (v == null || v < 0) {
      return 'Minutes cannot be empty or negative (0–60).';
    }
    if (v > 60) {
      return 'Maximum 60 minutes.';
    }
    return null;
  }

  String? _validateResultSeconds(String? value) {
    final v = _parseInt(value ?? '');
    if (v == null || v < 0) {
      return 'Seconds cannot be empty or negative (0–59).';
    }
    if (v > 59) {
      return 'Seconds must be 0–59.';
    }
    return null;
  }

  /// Combines minutes and seconds into one integer for the API / DB (seconds = minutes×60 + seconds).
  static int combineResultDisplaySeconds(int minutes, int seconds) {
    return (minutes.clamp(0, 60) * 60) + seconds.clamp(0, 59);
  }

  Map<String, dynamic> _buildPayload() {
    final pollDuration = int.tryParse(_pollDurationController.text.trim()) ?? 15;
    final rm = int.tryParse(_resultMinutesController.text.trim()) ?? 0;
    final rs = int.tryParse(_resultSecondsController.text.trim()) ?? 0;
    final totalSeconds = combineResultDisplaySeconds(rm, rs);
    return {
      'poll_duration': pollDuration,
      'result_display_duration_seconds': totalSeconds,
    };
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit?.call(_buildPayload());
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: widget.autovalidateMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _pollDurationController,
            decoration: const InputDecoration(
              labelText: 'Poll Duration (minutes)',
              hintText: 'e.g. 3, 15, 45',
              border: OutlineInputBorder(),
              helperText: 'How long users can vote before poll closes (1–1440)',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: _validatePollDuration,
            onFieldSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _resultMinutesController,
                  decoration: const InputDecoration(
                    labelText: 'Result display — minutes',
                    hintText: '0–60',
                    border: OutlineInputBorder(),
                    helperText: '0–60',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _validateResultMinutes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _resultSecondsController,
                  decoration: const InputDecoration(
                    labelText: 'Result display — seconds',
                    hintText: '0–59',
                    border: OutlineInputBorder(),
                    helperText: '0–59',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _validateResultSeconds,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'How long to show the winning result before the next vote. Stored as total seconds on the server.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          if (widget.onSubmit != null) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _handleSubmit,
              child: const Text('Save Timer Settings'),
            ),
          ],
        ],
      ),
    );
  }
}
