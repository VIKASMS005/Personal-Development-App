import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/app_providers.dart';
import '../utils/app_colors.dart';

class TaskTimerDialog extends StatefulWidget {
  final Todo task;
  const TaskTimerDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, Todo task) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskTimerDialog(task: task),
    );
  }

  @override
  State<TaskTimerDialog> createState() => _TaskTimerDialogState();
}

class _TaskTimerDialogState extends State<TaskTimerDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _markCompleteOnSave = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _markCompleteOnSave = widget.task.completed;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _ticker?.cancel();
      _animController.stop();
      setState(() => _isRunning = false);
    } else {
      _animController.repeat(reverse: true);
      setState(() => _isRunning = true);
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _elapsedSeconds++);
      });
    }
  }

  void _addManualMinutes(int minutes) {
    setState(() {
      _elapsedSeconds += minutes * 60;
    });
  }

  void _resetTimer() {
    _ticker?.cancel();
    _animController.stop();
    setState(() {
      _isRunning = false;
      _elapsedSeconds = 0;
    });
  }

  void _saveSession() async {
    _ticker?.cancel();
    if (_elapsedSeconds > 0) {
      final todoProv = context.read<TodoProvider>();
      await todoProv.logTaskTime(widget.task.id, _elapsedSeconds);
      if (_markCompleteOnSave && !widget.task.completed) {
        await todoProv.toggleCompleted(widget.task);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⏱️ Saved ${_formatSeconds(_elapsedSeconds)} focus time on "${widget.task.title}"!',
            ),
            backgroundColor: AppColors.tasks,
          ),
        );
      }
    } else {
      Navigator.pop(context);
    }
  }

  String _formatSeconds(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatTotalTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPrevious = widget.task.timeSpentSeconds;
    final liveTotal = totalPrevious + _elapsedSeconds;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Category Badge & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tasks.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: AppColors.tasks),
                      const SizedBox(width: 6),
                      Text(
                        widget.task.category.isNotEmpty ? widget.task.category : 'Task Tracker',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tasks,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Task Title
            Text(
              widget.task.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Total Logged Time
            Text(
              'Total Logged: ${_formatTotalTime(liveTotal)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // Live Timer Animated Circle Display
            GestureDetector(
              onTap: _toggleTimer,
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRunning
                          ? AppColors.tasks.withValues(alpha: 0.08)
                          : theme.colorScheme.surface,
                      border: Border.all(
                        color: _isRunning
                            ? AppColors.tasks
                            : theme.dividerColor.withValues(alpha: 0.4),
                        width: _isRunning ? 4 : 2,
                      ),
                      boxShadow: _isRunning
                          ? [
                              BoxShadow(
                                color: AppColors.tasks.withValues(
                                    alpha: 0.2 + (_animController.value * 0.15)),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppColors.tasks,
                          size: 36,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatSeconds(_elapsedSeconds),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRunning ? 'Tracking...' : 'Tap to Start',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _isRunning
                                ? AppColors.tasks
                                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Quick manual add chips
            Text(
              'Quick Add Time',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _quickChip('+15m', 15),
                _quickChip('+30m', 30),
                _quickChip('+45m', 45),
                _quickChip('+1h', 60),
                _quickChip('+2h', 120),
              ],
            ),
            const SizedBox(height: 16),

            // Mark completed checkbox
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Mark task as completed',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              value: _markCompleteOnSave,
              activeColor: AppColors.tasks,
              onChanged: (val) => setState(() => _markCompleteOnSave = val ?? false),
            ),
            const SizedBox(height: 12),

            // Action Buttons (Save & Reset)
            Row(
              children: [
                if (_elapsedSeconds > 0)
                  IconButton.outlined(
                    tooltip: 'Reset',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _resetTimer,
                  ),
                if (_elapsedSeconds > 0) const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.tasks,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _elapsedSeconds > 0
                            ? 'Save ${_formatSeconds(_elapsedSeconds)}'
                            : 'Done',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      onPressed: _saveSession,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(String label, int minutes) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onPressed: () => _addManualMinutes(minutes),
      backgroundColor: AppColors.tasks.withValues(alpha: 0.08),
    );
  }
}
