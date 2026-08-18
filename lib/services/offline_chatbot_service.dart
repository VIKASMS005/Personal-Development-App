import 'dart:convert';
import '../models/timetable_slot.dart';
import '../models/chat_message.dart';

class OfflineChatbotService {
  static final OfflineChatbotService instance = OfflineChatbotService._internal();

  OfflineChatbotService._internal();

  /// Process an incoming message and stream tokens to the callback
  Future<ChatMessage> streamResponse({
    required String uid,
    required String userText,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
    void Function(String chunk, String accumulatedText)? onTokenChunk,
  }) async {
    final finalMsg = await processMessage(
      uid: uid,
      userText: userText,
      userName: userName,
      habitCount: habitCount,
      pendingTaskCount: pendingTaskCount,
    );

    if (onTokenChunk != null) {
      final fullText = finalMsg.text;
      final words = fullText.split(' ');
      final buffer = StringBuffer();
      for (int i = 0; i < words.length; i++) {
        final chunk = i == 0 ? words[i] : ' ${words[i]}';
        buffer.write(chunk);
        onTokenChunk(chunk, buffer.toString());
        await Future.delayed(const Duration(milliseconds: 18));
      }
    }

    return finalMsg;
  }

  /// Process an incoming message from the user
  Future<ChatMessage> processMessage({
    required String uid,
    required String userText,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
  }) async {
    final lower = userText.trim().toLowerCase();

    // 1. Check for Task creation intent
    if (lower.startsWith('add task') || lower.startsWith('create task') || lower.startsWith('new task') || lower.contains('remind me to')) {
      return _generateTaskResponse(uid, userText, lower, userName);
    }

    // 2. Check for Habit creation intent
    if (lower.startsWith('add habit') || lower.startsWith('create habit') || lower.startsWith('track habit') || lower.contains('new habit')) {
      return _generateHabitResponse(uid, userText, lower, userName);
    }

    // 3. Check for Reminder creation intent
    if (lower.startsWith('add reminder') || lower.startsWith('set reminder') || lower.startsWith('create reminder')) {
      return _generateReminderResponse(uid, userText, lower, userName);
    }

    // 4. Check for Timetable / Routine generation intent
    if (_isTimetableIntent(lower)) {
      return _generateTimetableResponse(uid, userText, lower, userName);
    }

    // 2. Check for Greetings / Introduction
    if (lower.startsWith('hi') || lower.startsWith('hello') || lower.startsWith('hey') || lower.contains('who are you')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: 'Hello $userName! 👋 I am **GrowBot**, your personal AI assistant.\n\nHere is what I can do for you:\n'
            '• **Create Timetables**: Say *"Create a daily study routine"* or *"Schedule 7 AM Workout, 9 AM Work, 1 PM Lunch, 6 PM Read, 10 PM Sleep"*\n'
            '• **Productivity Advice**: Ask me about the *Pomodoro technique*, *Eisenhower matrix*, or *building streaks*\n'
            '• **Daily Planning**: Ask me *"How is my day looking?"*\n\nHow can I help you grow today?',
      );
    }

    // 3. Check for Daily Status / Summary
    if (lower.contains('my day') || lower.contains('status') || lower.contains('summary') || lower.contains('how am i doing')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: 'Here is your current snapshot, **$userName**:\n\n'
            '🔥 **Active Habits**: $habitCount habits being tracked\n'
            '📋 **Pending Tasks**: $pendingTaskCount items in your matrix\n\n'
            '💡 *Tip: Tackle your high-priority quadrant 1 tasks first this morning to build unbeatable momentum!*',
      );
    }

    // 4. Productivity Techniques & FAQ
    if (lower.contains('pomodoro')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '🍅 **The Pomodoro Technique** is a powerful focus framework:\n\n'
            '1. Choose a single task from your Tasks screen.\n'
            '2. Set a timer for **25 minutes** in the Clock/Timer tab.\n'
            '3. Work with zero distractions until the alarm rings.\n'
            '4. Take a **5-minute restful break**.\n'
            '5. Repeat 4 cycles, then take a longer 20-minute recharge break.\n\n'
            'Would you like me to schedule a Pomodoro focus timetable for you?',
      );
    }

    if (lower.contains('eisenhower') || lower.contains('matrix') || lower.contains('priorit')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '⚖️ **The Eisenhower Matrix** prioritizes tasks by urgency & importance:\n\n'
            '• **Q1 (Urgent & Important)**: Crises, deadlines. *Do immediately!*\n'
            '• **Q2 (Important, Not Urgent)**: Exercise, studying, personal growth. *Schedule in your timetable!*\n'
            '• **Q3 (Urgent, Not Important)**: Interruptions, trivial requests. *Minimize/delegate!*\n'
            '• **Q4 (Neither)**: Distractions & mindless scrolling. *Eliminate!*\n\n'
            'Focus 80% of your energy on **Q2** to achieve lasting progress.',
      );
    }

    if (lower.contains('habit') || lower.contains('streak') || lower.contains('consistency')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '⚡ **Rule of 2 Days for Unbreakable Habits**:\n\n'
            '1. **Never miss twice**: Missing one day happens, but never allow 2 missed days in a row.\n'
            '2. **Make it tiny**: If reading 30 mins feels hard, commit to just 2 pages.\n'
            '3. **Habit Stacking**: Attach the new habit to an existing one (e.g. *After morning coffee, I will journal for 5 mins*).\n\n'
            'Keep your streak flame burning in the Habits tab! 🔥',
      );
    }

    if (lower.contains('finance') || lower.contains('budget') || lower.contains('money') || lower.contains('saving')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '💰 **50/30/20 Budgeting Principle**:\n\n'
            '• **50% Needs**: Rent, groceries, bills\n'
            '• **30% Wants**: Hobbies, dining out, entertainment\n'
            '• **20% Savings/Investments**: Emergency fund & future security\n\n'
            'Remember to log each expense in your Finance tracker right after spending!',
      );
    }

    if (lower.contains('motivation') || lower.contains('inspire') || lower.contains('quote') || lower.contains('tired')) {
      final quotes = [
        '"We are what we repeatedly do. Excellence, then, is not an act, but a habit." — Will Durant',
        '"Small daily improvements over time lead to stunning results." — Robin Sharma',
        '"Discipline is choosing between what you want now and what you want most." — Abraham Lincoln',
        '"Focus on being productive instead of busy." — Tim Ferriss',
        '"You do not rise to the level of your goals. You fall to the level of your systems." — James Clear',
      ];
      final quote = quotes[(DateTime.now().microsecond % quotes.length)];
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '🌟 **Daily Inspiration for $userName**:\n\n$quote\n\nTake a deep breath and conquer your next goal!',
      );
    }

    // 5. Coding & Software Development Knowledge
    if (lower.contains('flutter') || lower.contains('dart') || lower.contains('python') ||
        lower.contains('code') || lower.contains('programming') || lower.contains('javascript') ||
        lower.contains('debug') || lower.contains('api') || lower.contains('database') || lower.contains('git')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '💻 **Software Engineering Knowledge Guide**:\n\n'
            '• **State Management**: Keep UI decoupled from business logic using reactive patterns (like Provider/Bloc/Riverpod).\n'
            '• **Clean Architecture**: Separate into UI Layer, Domain/Business Logic, and Data Source Layer (Local DB + Cloud Sync).\n'
            '• **Debugging Tip**: Break the problem down with print/logging at the boundary of data transformations.\n'
            '• **Git Best Practice**: Commit small, logical units of work with clear imperative messages (`feat: ...`, `fix: ...`).\n\n'
            'Let me know what language, error, or architecture concept you would like to explore deeper!',
      );
    }

    // 6. Science, Physics, Chemistry, Biology
    if (lower.contains('science') || lower.contains('physics') || lower.contains('chemistry') ||
        lower.contains('biology') || lower.contains('gravity') || lower.contains('atom') ||
        lower.contains('cell') || lower.contains('energy') || lower.contains('quantum')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '🔬 **Scientific Principles Overview**:\n\n'
            '• **First Principles Thinking**: Break any complex system down to its most fundamental truths and reason up from there.\n'
            '• **Conservation of Energy**: Energy cannot be created or destroyed, only transformed from one form to another (E = mc²).\n'
            '• **Biological Adaptation**: Systems adapt to the stressors placed upon them (SAID principle: Specific Adaptations to Imposed Demands).\n\n'
            'Feel free to ask a specific scientific theorem or calculation!',
      );
    }

    // 7. Writing, Resume & Communication
    if (lower.contains('essay') || lower.contains('resume') || lower.contains('writing') ||
        lower.contains('email') || lower.contains('letter') || lower.contains('grammar') || lower.contains('interview')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '✍️ **Effective Writing & Communication Framework**:\n\n'
            '1. **Hook**: Grab immediate attention in the first 2 sentences.\n'
            '2. **BLUF (Bottom Line Up Front)**: State your main thesis or request clearly before expanding on details.\n'
            '3. **Action-Oriented Verbs**: For resumes, use strong verbs with quantified outcomes (*"Spearheaded...", "Increased efficiency by 35%"*).\n'
            '4. **Ruthless Editing**: Remove every unnecessary word. Brevity commands respect.\n\n'
            'Need help drafting or structuring a specific document?',
      );
    }

    // 8. Sleep, Health & Fitness
    if (lower.contains('sleep') || lower.contains('workout') || lower.contains('diet') ||
        lower.contains('protein') || lower.contains('gym') || lower.contains('health') || lower.contains('exercise')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '💪 **Peak Health & Sleep Protocol**:\n\n'
            '• **Sleep (7-9 hrs)**: Keep your bedroom cool, pitch black, and avoid blue screens 60 mins before bed for optimal REM cycles.\n'
            '• **Daily Movement**: Target at least 8,000-10,000 steps plus 3-4 days of progressive resistance training.\n'
            '• **Hydration**: Drink 2.5–3.5 liters of water daily, starting with 500ml right upon waking.\n'
            '• **Nutrition**: Prioritize whole foods with 1.6–2.2g of protein per kg of body weight for active days.',
      );
    }

    // 9. Stoicism & Mental Clarity
    if (lower.contains('stoic') || lower.contains('anxiety') || lower.contains('stress') ||
        lower.contains('philosophy') || lower.contains('mindset') || lower.contains('calm') || lower.contains('fear')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '🏛️ **Stoic Wisdom & Mental Clarity**:\n\n'
            '• **Dichotomy of Control**: *"Some things are in our control and others not. Things in our control are opinion, pursuit, desire, aversion, and whatever are our own actions."* — Epictetus\n'
            '• **Amor Fati**: Embrace every obstacle not as an impediment, but as fuel to develop resilience.\n'
            '• **Action**: Take one slow, deep breath in for 4 seconds, hold for 4, exhale for 6. Focus solely on your next immediate step.',
      );
    }

    // 10. Procrastination & Deep Work
    if (lower.contains('procrastinat') || lower.contains('focus') || lower.contains('distract') ||
        lower.contains('lazy') || lower.contains('study')) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: '🧠 **Protocol to Eliminate Procrastination**:\n\n'
            '1. **The 2-Minute Rule**: If a task takes under 2 minutes, do it now. If it\'s big, commit to starting for just 2 minutes.\n'
            '2. **Reduce Friction**: Remove phone and background tabs from your physical field of view.\n'
            '3. **Eat the Frog**: Complete your hardest, most impactful task before noon.\n'
            '4. **Set a Single Objective**: Pick 1 primary goal for today and conquer it before touching secondary tasks.',
      );
    }

    // Default Fallback
    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: 'I\'m here with you, **$userName**! I can answer questions across science, coding, writing, philosophy, and health, or manage your schedule.\n\n'
          'Here are a few things you can try:\n'
          '👉 *"Create a daily student study timetable"*\n'
          '👉 *"Add a task: Complete Physics Chapter 4"*\n'
          '👉 *"How do I beat procrastination?"*\n'
          '👉 *"Explain state management in Flutter"*',
    );
  }

  bool _isTimetableIntent(String lower) {
    return lower.contains('timetable') ||
        lower.contains('routine') ||
        lower.contains('schedule') ||
        lower.contains('plan my day') ||
        lower.contains('daily plan') ||
        lower.contains('weekly plan') ||
        (lower.contains('am') && lower.contains('pm'));
  }

  ChatMessage _generateTimetableResponse(
    String uid,
    String rawText,
    String lower,
    String userName,
  ) {
    List<TimetableSlot> slots = [];
    String day = 'Daily';

    if (lower.contains('monday')) day = 'Monday';
    if (lower.contains('tuesday')) day = 'Tuesday';
    if (lower.contains('wednesday')) day = 'Wednesday';
    if (lower.contains('thursday')) day = 'Thursday';
    if (lower.contains('friday')) day = 'Friday';
    if (lower.contains('saturday')) day = 'Saturday';
    if (lower.contains('sunday')) day = 'Sunday';

    // Check if user provided explicit time slots in the text
    // E.g. "6 AM Run, 8 AM Study, 1 PM Lunch, 6 PM Gym, 10 PM Sleep"
    final parsedCustom = _parseCustomSlots(rawText, uid, day);
    if (parsedCustom.isNotEmpty) {
      slots = parsedCustom;
    } else if (lower.contains('student') || lower.contains('study') || lower.contains('exam')) {
      slots = _studentPreset(uid, day);
    } else if (lower.contains('work') || lower.contains('wfh') || lower.contains('office') || lower.contains('job')) {
      slots = _workPreset(uid, day);
    } else if (lower.contains('fitness') || lower.contains('workout') || lower.contains('gym') || lower.contains('health')) {
      slots = _fitnessPreset(uid, day);
    } else {
      // General balanced productivity preset
      slots = _balancedPreset(uid, day);
    }

    final slotsJson = jsonEncode(slots.map((s) => s.toMap()).toList());

    final buffer = StringBuffer();
    buffer.writeln('📅 **$userName, I have crafted your $day Timetable:**\n');
    for (final s in slots) {
      buffer.writeln('• **${s.startTime} - ${s.endTime}**: ${s.title} *(${s.category})*');
    }
    buffer.writeln('\nTap **"Apply to Timetable"** below to save these slots to your schedule with automatic reminders!');

    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: buffer.toString(),
      actionType: 'timetable_generated',
      actionData: slotsJson,
    );
  }

  List<TimetableSlot> _parseCustomSlots(String text, String uid, String day) {
    final List<TimetableSlot> list = [];
    // Regular expression to match formats like "7:00 AM Task", "7 AM Task", "07:00 - 08:00 Task", "7am gym, 9am study"
    final regex = RegExp(r'(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:-|to)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm))?\s*[:\-\s]+([^,;\n]+)', caseSensitive: false);
    final matches = regex.allMatches(text);

    for (final m in matches) {
      final start = m.group(1)?.trim() ?? '08:00';
      final end = m.group(2)?.trim() ?? _calculateNextHour(start);
      final rawTitle = m.group(3)?.trim() ?? 'Activity';

      if (rawTitle.isNotEmpty && !rawTitle.toLowerCase().contains('timetable') && !rawTitle.toLowerCase().contains('schedule')) {
        final category = _guessCategory(rawTitle);
        list.add(TimetableSlot(
          uid: uid,
          dayOfWeek: day,
          startTime: _normalizeTime(start),
          endTime: _normalizeTime(end),
          title: rawTitle,
          category: category,
          colorHex: _categoryColor(category),
        ));
      }
    }
    return list;
  }

  String _calculateNextHour(String start) {
    return '1 Hour';
  }

  String _normalizeTime(String raw) {
    return raw.toUpperCase();
  }

  String _guessCategory(String title) {
    final t = title.toLowerCase();
    if (t.contains('study') || t.contains('read') || t.contains('learn') || t.contains('class') || t.contains('homework')) return 'Study';
    if (t.contains('work') || t.contains('code') || t.contains('meeting') || t.contains('project') || t.contains('email')) return 'Work';
    if (t.contains('gym') || t.contains('workout') || t.contains('run') || t.contains('yoga') || t.contains('walk') || t.contains('exercise')) return 'Workout';
    if (t.contains('meditat') || t.contains('health') || t.contains('breakfast') || t.contains('lunch') || t.contains('dinner') || t.contains('meal')) return 'Health';
    if (t.contains('sleep') || t.contains('nap') || t.contains('rest')) return 'Sleep';
    if (t.contains('game') || t.contains('movie') || t.contains('music') || t.contains('leisure')) return 'Leisure';
    return 'Personal';
  }

  int _categoryColor(String category) {
    switch (category) {
      case 'Study':
        return 0xFF3B82F6; // Blue
      case 'Work':
        return 0xFF6366F1; // Indigo
      case 'Workout':
        return 0xFFEF4444; // Red
      case 'Health':
        return 0xFF10B981; // Emerald
      case 'Sleep':
        return 0xFF8B5CF6; // Purple
      case 'Leisure':
        return 0xFFF59E0B; // Amber
      default:
        return 0xFF059669; // Emerald Primary
    }
  }

  List<TimetableSlot> _studentPreset(String uid, String day) => [
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '06:30 AM', endTime: '07:30 AM', title: 'Morning Exercise & Meditation', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '08:00 AM', endTime: '09:00 AM', title: 'Healthy Breakfast & Prep', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '09:00 AM', endTime: '12:00 PM', title: 'Deep Study Block 1 (Core Subjects)', category: 'Study', colorHex: 0xFF3B82F6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '12:30 PM', endTime: '01:30 PM', title: 'Lunch & Relax', category: 'Health', colorHex: 0xFFF59E0B),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '02:00 PM', endTime: '04:30 PM', title: 'Deep Study Block 2 (Practice & Revision)', category: 'Study', colorHex: 0xFF3B82F6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '05:00 PM', endTime: '06:00 PM', title: 'Outdoor Sports / Walk', category: 'Workout', colorHex: 0xFFEF4444),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '07:00 PM', endTime: '08:30 PM', title: 'Homework & Review', category: 'Study', colorHex: 0xFF6366F1),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '09:00 PM', endTime: '09:30 PM', title: 'Daily Journal & Wind Down', category: 'Personal', colorHex: 0xFF8B5CF6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '10:30 PM', endTime: '06:30 AM', title: 'Restorative Sleep', category: 'Sleep', colorHex: 0xFF8B5CF6),
      ];

  List<TimetableSlot> _workPreset(String uid, String day) => [
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '06:30 AM', endTime: '07:15 AM', title: 'Morning Routine & Hydration', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '07:30 AM', endTime: '08:30 AM', title: 'Personal Growth / Reading', category: 'Personal', colorHex: 0xFF8B5CF6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '09:00 AM', endTime: '12:00 PM', title: 'Deep Work (High Impact Tasks)', category: 'Work', colorHex: 0xFF6366F1),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '12:00 PM', endTime: '01:00 PM', title: 'Nutritious Lunch & Walk', category: 'Health', colorHex: 0xFFF59E0B),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '01:30 PM', endTime: '04:30 PM', title: 'Collaborative Work & Execution', category: 'Work', colorHex: 0xFF6366F1),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '05:30 PM', endTime: '06:30 PM', title: 'Gym Workout & Cardio', category: 'Workout', colorHex: 0xFFEF4444),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '08:00 PM', endTime: '09:00 PM', title: 'Family & Leisure Time', category: 'Leisure', colorHex: 0xFFF59E0B),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '10:30 PM', endTime: '06:30 AM', title: 'Sleep', category: 'Sleep', colorHex: 0xFF8B5CF6),
      ];

  List<TimetableSlot> _fitnessPreset(String uid, String day) => [
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '06:00 AM', endTime: '06:30 AM', title: 'Hydration & Mobility Warmup', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '06:30 AM', endTime: '08:00 AM', title: 'Strength Training / Running', category: 'Workout', colorHex: 0xFFEF4444),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '08:30 AM', endTime: '09:30 AM', title: 'High-Protein Breakfast & Shower', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '10:00 AM', endTime: '01:00 PM', title: 'Work / Study Block', category: 'Work', colorHex: 0xFF6366F1),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '01:00 PM', endTime: '02:00 PM', title: 'Recovery Meal & Hydration', category: 'Health', colorHex: 0xFFF59E0B),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '05:30 PM', endTime: '06:15 PM', title: 'Evening Walk & Stretching', category: 'Workout', colorHex: 0xFFEF4444),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '10:00 PM', endTime: '06:00 AM', title: 'Muscle Recovery Sleep (8h)', category: 'Sleep', colorHex: 0xFF8B5CF6),
      ];

  List<TimetableSlot> _balancedPreset(String uid, String day) => [
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '07:00 AM', endTime: '08:00 AM', title: 'Morning Routine & Healthy Breakfast', category: 'Health', colorHex: 0xFF10B981),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '08:30 AM', endTime: '12:00 PM', title: 'Deep Work Session', category: 'Work', colorHex: 0xFF6366F1),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '12:00 PM', endTime: '01:00 PM', title: 'Lunch & Break', category: 'Health', colorHex: 0xFFF59E0B),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '01:30 PM', endTime: '04:30 PM', title: 'Productivity & Projects', category: 'Work', colorHex: 0xFF3B82F6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '05:00 PM', endTime: '06:00 PM', title: 'Exercise / Habit Time', category: 'Workout', colorHex: 0xFFEF4444),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '08:00 PM', endTime: '09:00 PM', title: 'Reading & Journaling', category: 'Personal', colorHex: 0xFF8B5CF6),
        TimetableSlot(uid: uid, dayOfWeek: day, startTime: '10:30 PM', endTime: '07:00 AM', title: 'Sleep & Recharge', category: 'Sleep', colorHex: 0xFF8B5CF6),
      ];

  ChatMessage _generateTaskResponse(String uid, String rawText, String lower, String userName) {
    String title = rawText;
    final prefixes = ['add task', 'create task', 'new task', 'remind me to'];
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        title = rawText.substring(p.length).trim();
        if (title.startsWith(':') || title.startsWith('-')) {
          title = title.substring(1).trim();
        }
        break;
      }
    }
    if (title.isEmpty) title = 'Important Task';

    String category = 'General';
    int priority = 2;
    if (lower.contains('study') || lower.contains('exam') || lower.contains('physics') || lower.contains('math') || lower.contains('chemistry') || lower.contains('homework')) {
      category = 'Study';
      priority = 1;
    } else if (lower.contains('work') || lower.contains('meeting') || lower.contains('project') || lower.contains('client')) {
      category = 'Work';
      priority = 1;
    } else if (lower.contains('gym') || lower.contains('workout') || lower.contains('run') || lower.contains('exercise')) {
      category = 'Fitness';
    } else if (lower.contains('code') || lower.contains('bug') || lower.contains('dev') || lower.contains('app')) {
      category = 'Coding';
    } else if (lower.contains('urgent') || lower.contains('asap')) {
      category = 'Urgent';
      priority = 1;
    }

    final taskData = {
      'action': 'create_task',
      'title': title,
      'category': category,
      'priority': priority,
      'description': 'Created by GrowBot',
    };

    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: '📋 **$userName, I have prepared your new task:**\n\n'
          '• **Title**: $title\n'
          '• **Category**: $category\n'
          '• **Priority**: Q$priority ${priority == 1 ? "(Urgent & Important)" : "(Important)"}\n\n'
          'Tap **"Add Task"** below to add it directly to your Eisenhower Matrix!',
      actionType: 'task_generated',
      actionData: jsonEncode(taskData),
    );
  }

  ChatMessage _generateHabitResponse(String uid, String rawText, String lower, String userName) {
    String title = rawText;
    final prefixes = ['add habit', 'create habit', 'track habit', 'new habit'];
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        title = rawText.substring(p.length).trim();
        if (title.startsWith(':') || title.startsWith('-')) {
          title = title.substring(1).trim();
        }
        break;
      }
    }
    if (title.isEmpty) title = 'Daily Healthy Habit';

    String category = 'Health';
    if (lower.contains('read') || lower.contains('book')) category = 'Reading';
    if (lower.contains('study') || lower.contains('learn')) category = 'Study';
    if (lower.contains('meditat') || lower.contains('mindful') || lower.contains('journal')) category = 'Mindfulness';
    if (lower.contains('gym') || lower.contains('workout') || lower.contains('run') || lower.contains('water')) category = 'Health';

    final habitData = {
      'action': 'create_habit',
      'title': title,
      'category': category,
      'targetDays': 21,
      'frequency': 'Daily',
    };

    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: '🔥 **$userName, I have formulated your habit goal:**\n\n'
          '• **Habit**: $title\n'
          '• **Target**: 21 Days Streak (Habit formation milestone)\n'
          '• **Category**: $category\n\n'
          'Tap **"Add Habit"** below to start building your streak in the Habits tab!',
      actionType: 'habit_generated',
      actionData: jsonEncode(habitData),
    );
  }

  ChatMessage _generateReminderResponse(String uid, String rawText, String lower, String userName) {
    String title = rawText;
    final prefixes = ['add reminder', 'set reminder', 'create reminder'];
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        title = rawText.substring(p.length).trim();
        if (title.startsWith(':') || title.startsWith('-')) {
          title = title.substring(1).trim();
        }
        break;
      }
    }
    if (title.isEmpty) title = 'Upcoming Reminder';

    String category = 'General';
    if (lower.contains('study') || lower.contains('exam')) category = 'Study';
    if (lower.contains('work') || lower.contains('meeting')) category = 'Work';
    if (lower.contains('health') || lower.contains('doctor') || lower.contains('medicine')) category = 'Health';

    final reminderData = {
      'action': 'create_reminder',
      'title': title,
      'category': category,
      'time': '05:00 PM',
    };

    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: '🔔 **$userName, I have scheduled your reminder:**\n\n'
          '• **Title**: $title\n'
          '• **Category**: $category\n'
          '• **Target Time**: Today • 05:00 PM\n\n'
          'Tap **"Set Reminder"** below to schedule this notification!',
      actionType: 'reminder_generated',
      actionData: jsonEncode(reminderData),
    );
  }
}
