import 'dart:async';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../constants/ai_prompts.dart';
import '../models/chat_message.dart' as grow;

/// Exception thrown when the AI could not produce a response.
///
/// [isNetworkIssue] tells the caller WHY it failed:
///   - true  -> the device genuinely has no internet connection right now.
///   - false -> the device IS online, but something else went wrong
///              (bad/missing API key, unsupported model, quota, malformed
///              request, etc). This is the case that used to get
///              mislabeled as "no internet" — now it isn't.
class AiUnavailableException implements Exception {
  final String reason;
  final bool isNetworkIssue;

  const AiUnavailableException(this.reason, {this.isNetworkIssue = true});

  @override
  String toString() => 'AiUnavailableException: $reason';
}

/// Real Gemini AI Service.
class AiService {
  static final AiService instance = AiService._internal();
  AiService._internal();

  /// Candidate model ids, tried in order. If one isn't available for this
  /// API key/project (a common source of silent failures), we transparently
  /// fall back to the next one instead of failing the whole request.
  static const List<String> _modelCandidates = [
    'gemini-3.6-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
  ];

  /// Reads the API key from .env (bundled asset), defensively cleaned of
  /// stray quotes/whitespace which is a very common cause of "invalid key"
  /// failures when people copy-paste into .env files.
  static String get _apiKey {
    String key = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    key = key.trim();
    if (key.length >= 2 && key.startsWith('"') && key.endsWith('"')) {
      key = key.substring(1, key.length - 1).trim();
    }
    if (key.isNotEmpty && key != 'YOUR_GEMINI_API_KEY_HERE') return key;
    const defineKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    return defineKey.trim();
  }

  final Map<String, GenerativeModel> _models = {};
  bool get isConfigured => _apiKey.isNotEmpty;

  GenerativeModel _getModel(String modelId) {
    return _models.putIfAbsent(
      modelId,
      () => GenerativeModel(
        model: modelId,
        apiKey: _apiKey,
        systemInstruction: Content.system(AiPrompts.baseSystemPrompt),
        generationConfig: GenerationConfig(
          temperature: 0.8,
          maxOutputTokens: 2048,
          topP: 0.95,
        ),
      ),
    );
  }

  List<Content> _buildHistory(List<grow.ChatMessage> history) {
    final result = <Content>[];
    for (final msg in history) {
      if (msg.sender == 'user') {
        result.add(Content.text(msg.text));
      } else if (msg.sender == 'bot' && msg.text.isNotEmpty) {
        result.add(Content.model([TextPart(msg.text)]));
      }
    }
    return result;
  }

  /// Actually probes the internet instead of guessing from an exception's
  /// message text. This is what fixes the "connected to net but says it
  /// needs internet" bug — we now check the real cause of the failure.
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Stream a response token-by-token.
  ///
  /// Throws [AiUnavailableException] on failure, with `isNetworkIssue`
  /// correctly indicating whether it was really a connectivity problem.
  Future<String> streamResponse({
    required String userMessage,
    required List<grow.ChatMessage> history,
    String? contextBlock,
    required void Function(String token, String accumulated) onToken,
  }) async {
    if (!isConfigured) {
      throw const AiUnavailableException(
        'Gemini API key not configured. Add GEMINI_API_KEY to your .env file.',
        isNetworkIssue: false,
      );
    }

    final geminiHistory = _buildHistory(history);
    final messageText = contextBlock != null
        ? '$contextBlock\n\nUser question: $userMessage'
        : userMessage;

    Object? lastError;

    for (final modelId in _modelCandidates) {
      try {
        final model = _getModel(modelId);
        final chat = model.startChat(history: geminiHistory);
        final stream = chat.sendMessageStream(Content.text(messageText));

        final buffer = StringBuffer();
        await for (final chunk in stream) {
          final text = chunk.text ?? '';
          if (text.isNotEmpty) {
            buffer.write(text);
            onToken(text, buffer.toString());
          }
        }
        return buffer.toString();
      } on InvalidApiKey {
        throw const AiUnavailableException(
          'Invalid Gemini API key. Check your GEMINI_API_KEY value in .env.',
          isNetworkIssue: false,
        );
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();

        final looksLikeMissingModel = msg.contains('not found') ||
            msg.contains('404') ||
            msg.contains('is not supported') ||
            msg.contains('unsupported') ||
            msg.contains('no longer available') ||
            msg.contains('deprecated') ||
            msg.contains('has been removed');
        if (looksLikeMissingModel) {
          // Try the next candidate model instead of failing outright.
          continue;
        }

        // Something else went wrong — find out if it's REALLY the network.
        final connected = await _hasInternet();
        if (!connected) {
          throw const AiUnavailableException(
            'No internet connection.',
            isNetworkIssue: true,
          );
        }
        // We're online — this is a real API/config error, not a
        // connectivity issue, so don't blame the internet for it.
        throw AiUnavailableException(
          'AI request failed: $e',
          isNetworkIssue: false,
        );
      }
    }

    // Every candidate model id failed to be found for this API key.
    final connected = await _hasInternet();
    throw AiUnavailableException(
      connected
          ? 'No supported Gemini model was available for this API key. '
              'Last error: $lastError'
          : 'No internet connection.',
      isNetworkIssue: !connected,
    );
  }

  /// Check if AI is reachable with a lightweight call.
  Future<bool> checkAvailability() async {
    if (!isConfigured) return false;
    try {
      final model = _getModel(_modelCandidates.first);
      final response =
          await model.generateContent([Content.text('Hi')]).timeout(
        const Duration(seconds: 5),
      );
      return response.text != null;
    } catch (_) {
      return false;
    }
  }
}
