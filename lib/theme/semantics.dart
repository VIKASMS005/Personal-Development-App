import 'package:flutter/material.dart';
import 'app_colors_ext.dart';

/// How a task/goal priority is presented. Each level has a label and an icon,
/// so priority is never communicated by color alone.
class PriorityStyle {
  final int level;
  final String label;
  final String shortLabel;
  final IconData icon;
  final StatusTone tone;

  const PriorityStyle._(this.level, this.label, this.shortLabel, this.icon, this.tone);

  static const urgentImportant =
      PriorityStyle._(1, 'Urgent', 'Urgent', Icons.keyboard_double_arrow_up_rounded, StatusTone.error);
  static const important =
      PriorityStyle._(2, 'Important', 'Important', Icons.keyboard_arrow_up_rounded, StatusTone.warning);
  static const urgent = PriorityStyle._(3, 'Medium Priority', 'Medium', Icons.remove_rounded, StatusTone.info);
  static const low =
      PriorityStyle._(4, 'Low Priority', 'Low', Icons.keyboard_arrow_down_rounded, StatusTone.neutral);

  static const all = [urgentImportant, important, urgent, low];

  static PriorityStyle of(int priority) {
    switch (priority) {
      case 1:
        return urgentImportant;
      case 2:
        return important;
      case 3:
        return urgent;
      default:
        return low;
    }
  }
}

/// Icon for a task / reminder category. Shared by forms, lists and reports.
IconData categoryIcon(String category) {
  switch (category) {
    case 'Study':
      return Icons.menu_book_rounded;
    case 'Work':
      return Icons.work_outline_rounded;
    case 'Coding':
      return Icons.code_rounded;
    case 'Fitness':
    case 'Workout':
    case 'Health':
      return Icons.fitness_center_rounded;
    case 'Reading':
      return Icons.auto_stories_outlined;
    case 'Personal':
      return Icons.person_outline_rounded;
    case 'Urgent':
      return Icons.priority_high_rounded;
    case 'Other':
      return Icons.category_outlined;
    default:
      return Icons.checklist_rounded;
  }
}

/// Journal moods: stored key → label and icon. Icons keep moods readable
/// without relying on emoji fonts or color.
const journalMoods = ['happy', 'calm', 'energetic', 'neutral', 'stressed', 'sad'];

String moodLabel(String mood) => switch (mood) {
      'happy' => 'Happy',
      'calm' => 'Calm',
      'energetic' => 'Energetic',
      'neutral' => 'Neutral',
      'stressed' => 'Stressed',
      'sad' => 'Sad',
      _ => mood.isEmpty ? 'Note' : '${mood[0].toUpperCase()}${mood.substring(1)}',
    };

IconData moodIcon(String mood) => switch (mood) {
      'happy' => Icons.sentiment_very_satisfied_outlined,
      'calm' => Icons.self_improvement_rounded,
      'energetic' => Icons.bolt_rounded,
      'neutral' => Icons.sentiment_neutral_outlined,
      'stressed' => Icons.sentiment_dissatisfied_outlined,
      'sad' => Icons.sentiment_very_dissatisfied_outlined,
      _ => Icons.edit_note_rounded,
    };
