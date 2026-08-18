import 'dart:async';
import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import '../constants/ai_prompts.dart';
import '../models/chat_message.dart';
import 'offline_chatbot_service.dart';

class AiChatbotService {
  static final AiChatbotService instance = AiChatbotService._internal();

  AiChatbotService._internal();

  static const _supportedModelNames = [
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ];

  /// Builds a GenerativeModel with the centralized System Prompt & dynamic Grow context
  GenerativeModel _createModel({
    required String modelName,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
    List<String> habitTitles = const [],
    List<String> taskTitles = const [],
  }) {
    final systemPrompt = AiPrompts.buildSystemPrompt(
      userName: userName,
      habitCount: habitCount,
      pendingTaskCount: pendingTaskCount,
      habitTitles: habitTitles,
      taskTitles: taskTitles,
    );

    return FirebaseAI.googleAI().generativeModel(
      model: modelName,
      systemInstruction: Content.system(systemPrompt),
    );
  }

  /// Sanitizes history to strictly conform to Gemini multi-turn conversation requirements.
  /// Rules:
  /// 1. History must start with a 'user' turn.
  /// 2. Turns must alternate strictly: user -> model -> user -> model.
  /// 3. History must end on a 'model' turn so the next message is a 'user' turn.
  List<Content> _buildSanitizedHistory(List<ChatMessage> history) {
    if (history.isEmpty) return const [];

    final cleanContents = <Content>[];

    // Take the most recent 16 messages for rich multi-turn context
    final candidateHistory = history.length > 16
        ? history.sublist(history.length - 16)
        : history;

    // Filter out messages with empty text
    final validMessages = candidateHistory
        .where((m) => m.text.trim().isNotEmpty)
        .toList();

    if (validMessages.isEmpty) return const [];

    // Find the first user message to guarantee history starts with a user turn
    int firstUserIdx = validMessages.indexWhere((m) => m.sender == 'user');
    if (firstUserIdx == -1) return const [];

    String expectedSender = 'user';

    for (int i = firstUserIdx; i < validMessages.length; i++) {
      final msg = validMessages[i];
      final text = msg.text.trim();

      if (msg.sender == expectedSender) {
        if (msg.sender == 'user') {
          cleanContents.add(Content.text(text));
          expectedSender = 'bot';
        } else {
          cleanContents.add(Content.model([TextPart(text)]));
          expectedSender = 'user';
        }
      } else if (msg.sender == 'user' && expectedSender == 'user') {
        // If two user turns in a row, replace previous or append
        cleanContents.add(Content.text(text));
        expectedSender = 'bot';
      }
    }

    // History for startChat must end with a model turn
    if (cleanContents.isNotEmpty && expectedSender == 'bot') {
      cleanContents.removeLast();
    }

    return cleanContents;
  }

  /// Stream AI response token-by-token with natural multi-turn conversation context
  Future<ChatMessage> streamMessage({
    required String uid,
    required String userText,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
    List<String> habitTitles = const [],
    List<String> taskTitles = const [],
    List<ChatMessage> history = const [],
    required void Function(String chunk, String accumulatedText) onTokenChunk,
  }) async {
    final cleanPrompt = userText.trim();
    if (cleanPrompt.isEmpty) {
      return ChatMessage(
        uid: uid,
        sender: 'bot',
        text: 'How can I assist you today?',
      );
    }

    // 1. Try Available Cloud Models
    for (final modelName in _supportedModelNames) {
      try {
        final model = _createModel(
          modelName: modelName,
          userName: userName,
          habitCount: habitCount,
          pendingTaskCount: pendingTaskCount,
          habitTitles: habitTitles,
          taskTitles: taskTitles,
        );

        final sanitizedHistory = _buildSanitizedHistory(history);
        final accumulated = StringBuffer();
        Stream<GenerateContentResponse>? stream;

        try {
          final chat = model.startChat(history: sanitizedHistory);
          stream = chat.sendMessageStream(Content.text(cleanPrompt));
        } catch (chatInitErr) {
          debugPrint('startChat fallback to generateContentStream: $chatInitErr');
          // If startChat history structure fails, fallback to direct content stream
          stream = model.generateContentStream([
            ...sanitizedHistory,
            Content.text(cleanPrompt),
          ]);
        }

        await for (final response in stream.timeout(const Duration(seconds: 20))) {
          final chunk = response.text;
          if (chunk != null && chunk.isNotEmpty) {
            accumulated.write(chunk);
            onTokenChunk(chunk, accumulated.toString());
          }
        }

        final fullReply = accumulated.toString().trim();
        if (fullReply.isNotEmpty) {
          return _buildFinalMessage(uid, fullReply);
        }
      } catch (e) {
        debugPrint('Model $modelName stream error: $e. Trying next model...');
      }
    }

    // 2. Offline / Local Fallback
    return OfflineChatbotService.instance.streamResponse(
      uid: uid,
      userText: cleanPrompt,
      userName: userName,
      habitCount: habitCount,
      pendingTaskCount: pendingTaskCount,
      onTokenChunk: onTokenChunk,
    );
  }

  /// One-shot message processor
  Future<ChatMessage> processMessage({
    required String uid,
    required String userText,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
    List<String> habitTitles = const [],
    List<String> taskTitles = const [],
    List<ChatMessage> history = const [],
  }) async {
    return streamMessage(
      uid: uid,
      userText: userText,
      userName: userName,
      habitCount: habitCount,
      pendingTaskCount: pendingTaskCount,
      habitTitles: habitTitles,
      taskTitles: taskTitles,
      history: history,
      onTokenChunk: (_, __) {},
    );
  }

  ChatMessage _buildFinalMessage(String uid, String fullReply) {
    final actionMap = _extractAction(fullReply);
    String? actionType;
    String? actionData;

    if (actionMap != null) {
      final act = actionMap['action'];
      if (act == 'timetable' || actionMap.containsKey('slots')) {
        actionType = 'timetable_generated';
        actionData = jsonEncode(actionMap['slots'] ?? []);
      } else if (act == 'create_task') {
        actionType = 'task_generated';
        actionData = jsonEncode(actionMap);
      } else if (act == 'create_habit') {
        actionType = 'habit_generated';
        actionData = jsonEncode(actionMap);
      } else if (act == 'create_reminder') {
        actionType = 'reminder_generated';
        actionData = jsonEncode(actionMap);
      }
    }

    return ChatMessage(
      uid: uid,
      sender: 'bot',
      text: fullReply,
      actionType: actionType,
      actionData: actionData,
    );
  }

  Map<String, dynamic>? _extractAction(String text) {
    try {
      final jsonBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', multiLine: true);
      final matches = jsonBlockRegex.allMatches(text);
      for (final match in matches) {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map) {
            if (decoded.containsKey('action')) {
              return Map<String, dynamic>.from(decoded);
            }
            if (decoded.containsKey('timetable') && decoded['timetable'] is List) {
              return {'action': 'timetable', 'slots': decoded['timetable']};
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
