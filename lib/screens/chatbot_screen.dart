import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_providers.dart';
import '../models/chat_message.dart';
import '../utils/app_colors.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> with TickerProviderStateMixin {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  static const _quickPrompts = [
    '✨ Ask me anything',
    '📅 Create daily study routine',
    '🧠 Explain quantum physics simply',
    '🌟 Deep motivation & clarity',
    '💼 Generate work schedule',
    '⚡ Tips to maintain streaks',
    '🍅 How does Pomodoro work?',
    '✍️ Help structure an essay',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        context.read<ChatbotProvider>().loadMessages(auth.uid!);
      }
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    final auth = context.read<AuthProvider>();
    final profile = context.read<ProfileProvider>();
    final habits = context.read<HabitProvider>();
    final todos = context.read<TodoProvider>();

    if (auth.uid != null) {
      context.read<ChatbotProvider>().sendMessage(
        uid: auth.uid!,
        userText: text,
        userName: profile.displayName,
        habitCount: habits.activeCount,
        pendingTaskCount: todos.pendingCount,
        habitTitles: habits.habits.map((h) => h.title).toList(),
        taskTitles: todos.pendingTodos.map((t) => t.title).toList(),
      );
      _msgCtrl.clear();
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatbot = context.watch<ChatbotProvider>();
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final todos = context.watch<TodoProvider>();
    final habits = context.watch<HabitProvider>();
    final reminders = context.watch<ReminderProvider>();

    if (chatbot.isThinking) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.chatbotGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GrowBot AI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Always active • Ready to assist',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear Conversation',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Reset Chat?'),
                  content: const Text('This will clear the current conversation history with GrowBot.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
              if (ok == true && auth.uid != null) {
                await chatbot.clearHistory(auth.uid!);
              }
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // 1. Quick Prompts
              Container(
                height: 44,
                margin: const EdgeInsets.only(top: 4, bottom: 6),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _quickPrompts.length,
                  itemBuilder: (context, i) {
                    final prompt = _quickPrompts[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _send(prompt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            prompt,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 2. Chat Message List
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: chatbot.messages.length,
                  itemBuilder: (context, index) {
                    final msg = chatbot.messages[index];
                    final isLastBot = !msg.isUser && index == chatbot.messages.length - 1 && chatbot.isThinking;
                    return _buildMessageBubble(
                      context,
                      msg,
                      theme,
                      isDark,
                      isLastBot,
                      timetable,
                      todos,
                      habits,
                      reminders,
                      chatbot,
                    );
                  },
                ),
              ),

              // 3. Floating Input Bar
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _msgCtrl,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(fontSize: 14.5),
                            decoration: InputDecoration(
                              hintText: 'Ask anything, plan routines, or add tasks...',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onSubmitted: _send,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppColors.chatbotGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                          onPressed: () => _send(_msgCtrl.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage msg,
    ThemeData theme,
    bool isDark,
    bool isStreaming,
    TimetableProvider timetable,
    TodoProvider todos,
    HabitProvider habits,
    ReminderProvider reminders,
    ChatbotProvider chatbot,
  ) {
    final isUser = msg.sender == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: AppColors.chatbotGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.primary
                        : (isDark ? AppColors.darkCard : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    border: isUser
                        ? null
                        : Border.all(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            width: 1,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: msg.text.isEmpty && isStreaming
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                                  begin: const Offset(0.7, 0.7),
                                  end: const Offset(1.3, 1.3),
                                  duration: 600.ms,
                                ),
                            const SizedBox(width: 6),
                            Text(
                              'Generating...',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              msg.text,
                              style: TextStyle(
                                color: isUser
                                    ? Colors.white
                                    : (isDark ? AppColors.darkText : AppColors.lightText),
                                height: 1.5,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            if (isStreaming)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 8,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 400.ms),
                              ),
                          ],
                        ),
                ),

                // Quick copy button for bot messages
                if (!isUser && msg.text.isNotEmpty && !isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: msg.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied response to clipboard'), duration: Duration(seconds: 1)),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 1. Timetable action button
                if (msg.actionType == 'timetable_generated' && !isStreaming) ...[
                  const SizedBox(height: 10),
                  _buildActionCard(
                    context: context,
                    icon: Icons.calendar_month_rounded,
                    color: AppColors.timetable,
                    title: 'Custom Routine Created',
                    subtitle: 'Ready to integrate into your timetable schedule',
                    isApplied: msg.isApplied,
                    appliedText: 'Routine Applied to Timetable ✓',
                    actionButtonText: 'Apply to Timetable',
                    onAction: () async {
                      await chatbot.applyTimetableAction(msg, timetable);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Timetable routine added successfully!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ],

                // 2. Task action button
                if (msg.actionType == 'task_generated' && !isStreaming) ...[
                  const SizedBox(height: 10),
                  _buildActionCard(
                    context: context,
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.tasks,
                    title: 'New Task Prepared',
                    subtitle: 'Ready to add to your Eisenhower Matrix',
                    isApplied: msg.isApplied,
                    appliedText: 'Task Added to Matrix ✓',
                    actionButtonText: 'Add to Tasks',
                    onAction: () async {
                      await chatbot.applyTaskAction(msg, todos);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Task added to your matrix!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ],

                // 3. Habit action button
                if (msg.actionType == 'habit_generated' && !isStreaming) ...[
                  const SizedBox(height: 10),
                  _buildActionCard(
                    context: context,
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.habits,
                    title: 'Habit Goal Configured',
                    subtitle: 'Start tracking daily consistency & streak',
                    isApplied: msg.isApplied,
                    appliedText: 'Habit Tracking Active ✓',
                    actionButtonText: 'Start Tracking Habit',
                    onAction: () async {
                      await chatbot.applyHabitAction(msg, habits);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Habit added to your tracking list! 🔥'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ],

                // 4. Reminder action button
                if (msg.actionType == 'reminder_generated' && !isStreaming) ...[
                  const SizedBox(height: 10),
                  _buildActionCard(
                    context: context,
                    icon: Icons.notifications_active_rounded,
                    color: AppColors.alarm,
                    title: 'Reminder Ready',
                    subtitle: 'Alert & notification will be scheduled',
                    isApplied: msg.isApplied,
                    appliedText: 'Reminder Scheduled ✓',
                    actionButtonText: 'Set Reminder',
                    onAction: () async {
                      await chatbot.applyReminderAction(msg, reminders);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reminder alert scheduled successfully! 🔔'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isApplied,
    required String appliedText,
    required String actionButtonText,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isApplied ? AppColors.success : color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(isApplied ? Icons.check_circle_rounded : Icons.add_rounded, size: 18),
              label: Text(
                isApplied ? appliedText : actionButtonText,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: isApplied ? null : onAction,
            ),
          ),
        ],
      ),
    );
  }
}
