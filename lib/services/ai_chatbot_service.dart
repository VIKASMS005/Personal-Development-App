import '../models/chat_message.dart';
import '../engine/grow_engine.dart';
import '../ai/ai_service.dart';
import '../ai/ai_context_builder.dart';
import '../constants/ai_prompts.dart';

/// AiChatbotService — routes each message to the correct response source.
///
/// Decision flow:
///   1. If API key not configured -> show setup message
///   2. If AI available (network + valid key) -> Gemini API with context
///   3. If AI unavailable (offline / error) -> InsightEngine offline response
///
/// The AI never touches the database. All user data is provided via GrowEngine.
class AiChatbotService {
  static final AiChatbotService instance = AiChatbotService._internal();
  AiChatbotService._internal();

  final AiService _aiService = AiService.instance;

  /// Stream a response. Calls [onToken] for each token as it arrives.
  /// Returns the complete final message text.
  ///
  /// Throws nothing — handles all errors internally and returns a graceful
  /// offline/error message instead.
  Future<String> streamMessage({
    required String uid,
    required String userMessage,
    required List<ChatMessage> history,
    required GrowEngine? engine,
    required void Function(String token, String accumulated) onToken,
  }) async {
    final clean = userMessage.trim();
    if (clean.isEmpty) return '';

    // ── 1. API key not configured ──────────────────────────────────────────
    if (!_aiService.isConfigured) {
      const reply = AiPrompts.apiKeyMissingMessage;
      _streamFakeTokens(reply, onToken);
      return reply;
    }

    // ── 2. Try real AI ────────────────────────────────────────────────────
    try {
      // Build context only if the message seems personally relevant
      final contextBlock = engine != null
          ? AiContextBuilder.buildIfRelevant(message: clean, engine: engine)
          : null;

      return await _aiService.streamResponse(
        userMessage: clean,
        history: history,
        contextBlock: contextBlock,
        onToken: onToken,
      );
    } on AiUnavailableException catch (e) {
      // ── 3. AI unavailable — but WHY matters. Only claim "offline" when
      //       we actually confirmed there's no internet. Otherwise surface
      //       the real error so it doesn't get misdiagnosed as connectivity.
      return _offlineResponse(
        clean,
        engine,
        onToken,
        reason: e.reason,
        isNetworkIssue: e.isNetworkIssue,
      );
    } catch (e) {
      return _offlineResponse(
        clean,
        engine,
        onToken,
        reason: e.toString(),
        isNetworkIssue: false,
      );
    }
  }

  // ─── Offline / Error Fallback ────────────────────────────────────────────

  String _offlineResponse(
    String message,
    GrowEngine? engine,
    void Function(String, String) onToken, {
    required String reason,
    required bool isNetworkIssue,
  }) {
    String reply;

    final headerLine = isNetworkIssue
        ? "📴 *You're offline — here's what I know from your local data:*\n"
        : "⚠️ *Grow AI hit an issue reaching the assistant (not a connectivity "
            "problem) — here's what I know from your local data instead:*\n"
            "_Details: ${reason}_\n";

    if (engine != null && engine.messageNeedsPersonalContext(message)) {
      // Provide a real data-driven offline response
      final summary = engine.summaryLine;
      final insights = engine.currentInsights;

      final buffer = StringBuffer();
      buffer.writeln(headerLine);
      buffer.writeln(summary);

      if (insights.isNotEmpty) {
        buffer.writeln('\n**Today\'s Insights:**');
        for (final insight in insights.take(3)) {
          buffer.writeln('${insight.icon} ${insight.text}');
        }
      }
      buffer.writeln(isNetworkIssue
          ? '\n*Full AI responses are available when you have an internet connection.*'
          : '\n*Full AI responses will resume once this is resolved — tap the retry '
              'or check your API key/model configuration if this keeps happening.*');
      reply = buffer.toString();
    } else {
      // General question — can't answer via the AI right now.
      final summary =
          engine?.summaryLine ?? 'Your Grow data is available offline.';
      reply = isNetworkIssue
          ? AiPrompts.offlineFallback(summary)
          : '$headerLine\n$summary\n\n'
              'All your habits, tasks, journal, and timetable features '
              'continue to work fully offline.';
    }

    _streamFakeTokens(reply, onToken);
    return reply;
  }

  /// Simulate token streaming for offline/error messages so the UI
  /// still shows the familiar streaming animation.
  void _streamFakeTokens(
    String text,
    void Function(String, String) onToken,
  ) {
    final buffer = StringBuffer();
    final words = text.split(' ');
    for (int i = 0; i < words.length; i++) {
      final chunk = i == 0 ? words[i] : ' ${words[i]}';
      buffer.write(chunk);
      onToken(chunk, buffer.toString());
    }
  }
}
