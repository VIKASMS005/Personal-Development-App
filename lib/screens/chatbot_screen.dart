import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import '../models/chat_message.dart';
import '../widgets/ds/ds.dart';

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

    if (auth.uid != null) {
      final habits = context.read<HabitProvider>().habits;
      final todos = context.read<TodoProvider>().todos;
      final journals = context.read<JournalProvider>().entries;
      final finance = context.read<FinanceProvider>();
      final timetable = context.read<TimetableProvider>().slots;
      final reminders = context.read<ReminderProvider>().reminders;
      final profile = context.read<ProfileProvider>().profile;
      final stepProv = context.read<StepProvider>();
      final screenProv = context.read<ScreenTimeProvider>();

      context.read<EngineProvider>().rebuild(
            habits: habits,
            todos: todos,
            journals: journals,
            transactions: finance.transactions,
            timetableSlots: timetable,
            reminders: reminders,
            userName: profile?.name ?? '',
            todaySteps: stepProv.todaySteps,
            stepGoal: stepProv.stepGoal,
            todayCalories: stepProv.todayCalories,
            todayDistanceKm: stepProv.todayDistanceKm,
            todayActiveMinutes: stepProv.todayActiveMinutes,
            todayScreenTime: screenProv.todayFormattedTotal,
            totalFinanceBalance: finance.totalBalance,
          );

      final engine = context.read<EngineProvider>().engine;

      context.read<ChatbotProvider>().sendMessage(
        uid: auth.uid!,
        userText: text,
        engine: engine,
      );
      _msgCtrl.clear();
      _scrollToBottom();
    }
  }

  /// Quick prompts are sent exactly as before; only the leading emoji is
  /// hidden in the chip label.
  String _promptLabel(String p) {
    final i = p.indexOf(' ');
    return i > 0 && i <= 3 ? p.substring(i + 1) : p;
  }

  /// Renders **bold** markers from the coach's replies as bold text.
  List<TextSpan> _richSpans(String text) {
    final parts = text.split('**');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: parts[i],
            style: i.isOdd && i < parts.length - 1 ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
    ];
  }

  void _snack(String message) {
    AppSnack.show(context, message, tone: StatusTone.success, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final chatbot = context.watch<ChatbotProvider>();
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final todos = context.watch<TodoProvider>();
    final habits = context.watch<HabitProvider>();
    final reminders = context.watch<ReminderProvider>();
    final colors = context.colors;

    if (chatbot.isThinking) {
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Row(
          children: [
            const IconBadge(icon: Icons.auto_awesome_outlined, size: 36),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Coach', style: context.text.titleMedium),
                  Text('Uses your data on this device', style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear conversation',
            onPressed: () async {
              final ok = await ConfirmDialog.show(
                context,
                title: 'Clear conversation?',
                message: 'This removes your chat history with the AI Coach.',
                confirmLabel: 'Clear',
                destructive: true,
              );
              if (ok && auth.uid != null) {
                await chatbot.clearHistory(auth.uid!);
              }
            },
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: ContentWidth(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen, vertical: AppSpacing.xxs),
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final prompt = _quickPrompts[i];
                  return ActionChip(
                    label: Text(_promptLabel(prompt)),
                    onPressed: () => _send(prompt),
                  );
                },
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Expanded(
              child: chatbot.messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Ask your coach',
                      subtitle: 'Plan a routine, add a task or habit, or ask a question.',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.md),
                      itemCount: chatbot.messages.length,
                      itemBuilder: (context, index) {
                        final msg = chatbot.messages[index];
                        final isLastBot = !msg.isUser && index == chatbot.messages.length - 1 && chatbot.isThinking;
                        return _buildMessageBubble(context, msg, isLastBot, timetable, todos, habits, reminders, chatbot);
                      },
                    ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.scheme.surface,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgCtrl,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Message your coach'),
                          onSubmitted: _send,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton.filled(
                        tooltip: 'Send',
                        style: IconButton.styleFrom(minimumSize: const Size(AppSizes.minTouchTarget + 4, AppSizes.minTouchTarget + 4)),
                        icon: const Icon(Icons.arrow_upward_rounded),
                        onPressed: () => _send(_msgCtrl.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage msg,
    bool isStreaming,
    TimetableProvider timetable,
    TodoProvider todos,
    HabitProvider habits,
    ReminderProvider reminders,
    ChatbotProvider chatbot,
  ) {
    final isUser = msg.sender == 'user';
    final colors = context.colors;
    final scheme = context.scheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const IconBadge(icon: Icons.auto_awesome_outlined, size: 28),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm - 2),
                    decoration: BoxDecoration(
                      color: isUser ? scheme.primary : scheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(AppRadius.lg),
                        topRight: const Radius.circular(AppRadius.lg),
                        bottomLeft: Radius.circular(isUser ? AppRadius.lg : AppRadius.xs),
                        bottomRight: Radius.circular(isUser ? AppRadius.xs : AppRadius.lg),
                      ),
                      border: isUser ? null : Border.all(color: colors.border),
                    ),
                    child: msg.text.isEmpty && isStreaming
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: colors.textSecondary),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text('Thinking…', style: context.text.bodyMedium?.copyWith(color: colors.textSecondary)),
                            ],
                          )
                        : SelectableText.rich(
                            TextSpan(
                              children: _richSpans(msg.text + (isStreaming ? ' ▍' : '')),
                            ),
                            style: context.text.bodyMedium?.copyWith(
                              color: isUser ? scheme.onPrimary : colors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                  ),
                  if (!isUser && msg.text.isNotEmpty && !isStreaming)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        textStyle: context.text.labelSmall,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: msg.text));
                        AppSnack.show(context, 'Copied to clipboard', duration: const Duration(seconds: 1));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy'),
                    ),
                  if (msg.actionType == 'timetable_generated' && !isStreaming)
                    _buildActionCard(
                      icon: Icons.calendar_view_day_outlined,
                      title: 'Routine ready',
                      subtitle: 'Add these blocks to your timetable.',
                      isApplied: msg.isApplied,
                      appliedText: 'Added to timetable',
                      actionButtonText: 'Add to timetable',
                      onAction: () async {
                        await chatbot.applyTimetableAction(msg, timetable);
                        if (mounted) _snack('Routine added to your timetable');
                      },
                    ),
                  if (msg.actionType == 'task_generated' && !isStreaming)
                    _buildActionCard(
                      icon: Icons.task_alt_rounded,
                      title: 'Task suggested',
                      subtitle: 'Add it to your task list.',
                      isApplied: msg.isApplied,
                      appliedText: 'Added to tasks',
                      actionButtonText: 'Add to tasks',
                      onAction: () async {
                        await chatbot.applyTaskAction(msg, todos);
                        if (mounted) _snack('Task added');
                      },
                    ),
                  if (msg.actionType == 'habit_generated' && !isStreaming)
                    _buildActionCard(
                      icon: Icons.local_fire_department_outlined,
                      title: 'Habit suggested',
                      subtitle: 'Track it daily and build a streak.',
                      isApplied: msg.isApplied,
                      appliedText: 'Habit added',
                      actionButtonText: 'Start tracking',
                      onAction: () async {
                        await chatbot.applyHabitAction(msg, habits);
                        if (mounted) _snack('Habit added');
                      },
                    ),
                  if (msg.actionType == 'reminder_generated' && !isStreaming)
                    _buildActionCard(
                      icon: Icons.notifications_none_rounded,
                      title: 'Reminder ready',
                      subtitle: 'A notification will be scheduled.',
                      isApplied: msg.isApplied,
                      appliedText: 'Reminder set',
                      actionButtonText: 'Set reminder',
                      onAction: () async {
                        await chatbot.applyReminderAction(msg, reminders);
                        if (mounted) _snack('Reminder scheduled');
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isApplied,
    required String appliedText,
    required String actionButtonText,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: AppCard(
        emphasized: !isApplied,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: isApplied ? Icons.check_rounded : icon, tone: isApplied ? StatusTone.success : StatusTone.primary, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall),
                      Text(subtitle, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: isApplied
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_rounded, size: AppSizes.iconMd),
                      label: Text(appliedText),
                    )
                  : FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.add_rounded, size: AppSizes.iconMd),
                      label: Text(actionButtonText),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
