import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable form widget for configuring poll timer durations.
/// Use in poll creation/configuration UIs. Callbacks receive the typed values.
///
/// Example API payload when submitting:
/// ```dart
/// {
///   'poll_duration': 15,           // minutes
///   'result_display_duration': 1,  // minutes
/// }
/// ```
class PollTimerConfigForm extends StatefulWidget {
  final int initialPollDuration;
  final int initialResultDisplayDuration;
  final ValueChanged<Map<String, dynamic>>? onSubmit;
  final AutovalidateMode autovalidateMode;

  const PollTimerConfigForm({
    super.key,
    this.initialPollDuration = 15,
    this.initialResultDisplayDuration = 1,
    this.onSubmit,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  @override
  State<PollTimerConfigForm> createState() => _PollTimerConfigFormState();
}

class _PollTimerConfigFormState extends State<PollTimerConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _pollDurationController;
  late TextEditingController _resultDisplayController;

  @override
  void initState() {
    super.initState();
    _pollDurationController = TextEditingController(
      text: widget.initialPollDuration.toString(),
    );
    _resultDisplayController = TextEditingController(
      text: widget.initialResultDisplayDuration.toString(),
    );
  }

  @override
  void dispose() {
    _pollDurationController.dispose();
    _resultDisplayController.dispose();
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

  String? _validateResultDisplay(String? value) {
    final v = _parseInt(value ?? '');
    if (v == null || v < 0) {
      return 'Result display duration cannot be empty or negative. Enter minutes (e.g. 0, 1, 5).';
    }
    if (v > 60) {
      return 'Maximum 60 minutes.';
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() {
    final pollDuration = int.tryParse(_pollDurationController.text.trim()) ?? 15;
    final resultDisplay =
        int.tryParse(_resultDisplayController.text.trim()) ?? 1;
    return {
      'poll_duration': pollDuration,
      'result_display_duration': resultDisplay,
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
          TextFormField(
            controller: _resultDisplayController,
            decoration: const InputDecoration(
              labelText: 'Result Display Duration (minutes)',
              hintText: 'e.g. 0, 1, 5',
              border: OutlineInputBorder(),
              helperText:
                  'How long to show the winning result before next vote (0–60)',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: _validateResultDisplay,
            onFieldSubmitted: (_) => _handleSubmit(),
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
