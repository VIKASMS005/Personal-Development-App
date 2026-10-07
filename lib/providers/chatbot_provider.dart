import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/timetable_slot.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/reminder.dart';
import '../services/database_service.dart';
import '../services/ai_chatbot_service.dart';
import '../engine/grow_engine.dart';
import 'timetable_provider.dart';
import 'todo_provider.dart';
import 'habit_provider.dart';
import 'reminder_provider.dart';

/// ChatbotProvider — manages AI conversation state.
///
/// Architecture:
///   ChatbotScreen
///    ↓
///   ChatbotProvider  ← you are here
///    ↓
///   AiChatbotService (router)
///    ├─ AiService (Gemini API — real streaming, multi-turn history)
///    └─ InsightEngine (offline fallback — deterministic, data-driven)
///    ↓
///   GrowEngine (context — engine, NOT raw DB)
class ChatbotProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final AiChatbotService _chatService = AiChatbotService.instance;

  List<ChatMessage> _messages = [];
  bool _isThinking = false;

  // Engine reference — injected before each sendMessage call
  GrowEngine? _engine;

  List<ChatMessage> get messages => _messages;
  bool get isThinking => _isThinking;

  void clear() {
    _messages = [];
    _isThinking = false;
    notifyListeners();
  }

  /// Update the engine reference. Called by the UI before sending a message.
  void updateEngine(GrowEngine? engine) {
    _engine = engine;
  }

  Future<void> loadMessages(String uid) async {
    _messages = await _db.getChatMessages(uid);
    if (_messages.isEmpty) {
      final welcome = ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '👋 Hi! I\'m **Grow AI**, your personal assistant.\n\n'
            'I can help with:\n'
            '• **Your progress** — habits, tasks, streaks, insights\n'
            '• **General questions** — science, programming, math, history, anything\n'
            '• **Planning** — create timetables, tasks, habits, reminders\n'
            '• **Learning** — explain any concept, help with code\n\n'
            'What would you like to talk about?',
      );
      _messages.add(welcome);
      await _db.insertChatMessage(welcome);
    }
    notifyListeners();
  }

  Future<void> sendMessage({
    required String uid,
    required String userText,
    GrowEngine? engine,
  }) async {
    if (userText.trim().isEmpty) return;

    // Use the injected engine or the one passed here
    final activeEngine = engine ?? _engine;

    // Add user message
    final userMsg = ChatMessage(
      uid: uid,
      sender: 'user',
      text: userText.trim(),
    );
    _messages.add(userMsg);
    await _db.insertChatMessage(userMsg);

    // Add streaming placeholder for the bot reply
    final botPlaceholder = ChatMessage(
      uid: uid,
      sender: 'bot',
      text: '',
    );
    _messages.add(botPlaceholder);
    _isThinking = true;
    notifyListeners();

    // Build history for multi-turn context:
    // All messages except the current user turn and the placeholder
    final history = _messages
        .where((m) => m.id != userMsg.id && m.id != botPlaceholder.id)
        .toList();

    // Stream the AI response
    String finalText = '';
    try {
      finalText = await _chatService.streamMessage(
        uid: uid,
        userMessage: userText,
        history: history,
        engine: activeEngine,
        onToken: (token, accumulated) {
          final idx = _messages.indexWhere((m) => m.id == botPlaceholder.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(text: accumulated);
            notifyListeners();
          }
        },
      );
    } catch (e) {
      finalText = '⚠️ Something went wrong. Please try again.';
    }

    // Finalize bot message — parse for action JSON blocks
    final parsedActionType = _extractActionType(finalText);
    final parsedActionData = parsedActionType != null
        ? _extractActionData(finalText, parsedActionType, uid)
        : null;

    final finalMsg = botPlaceholder.copyWith(
      text: finalText,
      actionType: parsedActionType,
      actionData: parsedActionData,
    );

    final finalIdx = _messages.indexWhere((m) => m.id == botPlaceholder.id);
    if (finalIdx != -1) {
      _messages[finalIdx] = finalMsg;
    }

    _isThinking = false;
    notifyListeners();

    await _db.insertChatMessage(finalMsg);
  }

  // ─── Action JSON Parsing ──────────────────────────────────────────────────

  /// Detect if the AI response contains an in-app action JSON block.
  String? _extractActionType(String text) {
    if (!text.contains('```json')) return null;
    try {
      final jsonStr = _extractJsonBlock(text);
      if (jsonStr == null) return null;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final action = data['action']?.toString();
      if (action == 'timetable') return 'timetable_generated';
      if (action == 'create_task') return 'task_generated';
      if (action == 'create_habit') return 'habit_generated';
      if (action == 'create_reminder') return 'reminder_generated';
    } catch (_) {}
    return null;
  }

  String? _extractActionData(String text, String actionType, String uid) {
    try {
      final jsonStr = _extractJsonBlock(text);
      if (jsonStr == null) return null;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (actionType == 'timetable_generated' && data['slots'] != null) {
        // Convert to timetable slot maps
        final slots = (data['slots'] as List).map((s) {
          return {
            'uid': uid,
            'day_of_week': s['dayOfWeek'] ?? 'Daily',
            'start_time': s['startTime'] ?? '08:00 AM',
            'end_time': s['endTime'] ?? '09:00 AM',
            'title': s['title'] ?? 'Activity',
            'category': s['category'] ?? 'Personal',
            'color_hex': _categoryColor(s['category']?.toString() ?? ''),
          };
        }).toList();
        return jsonEncode(slots);
      }

      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  String? _extractJsonBlock(String text) {
    final start = text.indexOf('```json');
    if (start == -1) return null;
    final end = text.indexOf('```', start + 7);
    if (end == -1) return null;
    return text.substring(start + 7, end).trim();
  }

  int _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'study':
        return 0xFF3B82F6;
      case 'work':
        return 0xFF6366F1;
      case 'workout':
      case 'health':
        return 0xFF10B981;
      case 'sleep':
        return 0xFF8B5CF6;
      case 'leisure':
        return 0xFFF59E0B;
      default:
        return 0xFF059669;
    }
  }

  // ─── Action Apply Methods ─────────────────────────────────────────────────

  Future<void> applyTimetableAction(
      ChatMessage msg, TimetableProvider timetableProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final List<dynamic> raw = jsonDecode(msg.actionData!);
      final slots = raw
          .map((m) => TimetableSlot.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      await timetableProvider.addMultipleSlots(slots);
      await _db.markChatActionApplied(msg.id);
      _updateMessageApplied(msg.id);
    } catch (e) {
      debugPrint('ChatbotProvider: Error applying timetable: $e');
    }
  }

  Future<void> applyTaskAction(
      ChatMessage msg, TodoProvider todoProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      final todo = Todo(
        uid: msg.uid,
        title: (data['title'] ?? 'New Task').toString(),
        createdAt: DateTime.now(),
        description: (data['description'] ?? '').toString(),
        category: (data['category'] ?? 'General').toString(),
        priority: (data['priority'] is int)
            ? data['priority'] as int
            : int.tryParse('${data['priority']}') ?? 2,
      );
      await todoProvider.addTodo(todo);
      await _db.markChatActionApplied(msg.id);
      _updateMessageApplied(msg.id);
    } catch (e) {
      debugPrint('ChatbotProvider: Error applying task: $e');
    }
  }

  Future<void> applyHabitAction(
      ChatMessage msg, HabitProvider habitProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      final freqStr = (data['frequency'] ?? 'daily').toString().toLowerCase();
      final habit = Habit(
        uid: msg.uid,
        title: (data['title'] ?? 'New Habit').toString(),
        frequency: freqStr.contains('week')
            ? HabitFrequency.weekly
            : HabitFrequency.daily,
      );
      await habitProvider.addHabit(habit);
      await _db.markChatActionApplied(msg.id);
      _updateMessageApplied(msg.id);
    } catch (e) {
      debugPrint('ChatbotProvider: Error applying habit: $e');
    }
  }

  Future<void> applyReminderAction(
      ChatMessage msg, ReminderProvider reminderProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      DateTime reminderTime = DateTime.now().add(const Duration(hours: 2));
      if (data['time'] != null) {
        final now = DateTime.now();
        final timeStr = data['time'].toString().toLowerCase();
        final match =
            RegExp(r'(\d{1,2}):?(\d{2})?\s*(am|pm)?').firstMatch(timeStr);
        if (match != null) {
          int hour = int.tryParse(match.group(1) ?? '17') ?? 17;
          int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
          final isPm = (match.group(3) ?? '').toLowerCase() == 'pm';
          if (isPm && hour < 12) hour += 12;
          if (!isPm && match.group(3) == 'am' && hour == 12) hour = 0;
          reminderTime = DateTime(now.year, now.month, now.day, hour, minute);
          if (reminderTime.isBefore(now)) {
            reminderTime = reminderTime.add(const Duration(days: 1));
          }
        }
      }
      final reminder = Reminder(
        uid: msg.uid,
        title: (data['title'] ?? 'New Reminder').toString(),
        description: (data['description'] ?? 'Created by Grow AI').toString(),
        category: (data['category'] ?? 'General').toString(),
        dateTime: reminderTime,
      );
      await reminderProvider.addReminder(reminder);
      await _db.markChatActionApplied(msg.id);
      _updateMessageApplied(msg.id);
    } catch (e) {
      debugPrint('ChatbotProvider: Error applying reminder: $e');
    }
  }

  void _updateMessageApplied(String id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(isApplied: true);
      notifyListeners();
    }
  }

  Future<void> clearHistory(String uid) async {
    _messages.clear();
    notifyListeners();
    await _db.clearChatMessages(uid);
    await loadMessages(uid);
  }
}
