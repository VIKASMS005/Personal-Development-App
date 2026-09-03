import 'package:uuid/uuid.dart';

class ChatMessage {
  final String id;
  final String uid;
  final String sender; // 'user' or 'bot'
  final String text;
  final DateTime timestamp;
  final String? actionType; // 'timetable_generated', 'action_prompt', null
  final String? actionData; // JSON or serialized data for action buttons
  final bool isApplied;

  ChatMessage({
    String? id,
    this.uid = '',
    required this.sender,
    required this.text,
    DateTime? timestamp,
    this.actionType,
    this.actionData,
    this.isApplied = false,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  bool get isUser => sender == 'user';

  ChatMessage copyWith({
    String? id,
    String? uid,
    String? sender,
    String? text,
    DateTime? timestamp,
    String? actionType,
    String? actionData,
    bool? isApplied,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      actionType: actionType ?? this.actionType,
      actionData: actionData ?? this.actionData,
      isApplied: isApplied ?? this.isApplied,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'sender': sender,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'actionType': actionType,
        'actionData': actionData,
        'isApplied': isApplied,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'sender': sender,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'action_type': actionType,
        'action_data': actionData,
        'is_applied': isApplied ? 1 : 0,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        sender: m['sender'] ?? 'user',
        text: m['text'] ?? '',
        timestamp: m['timestamp'] != null
            ? DateTime.tryParse(m['timestamp']) ?? DateTime.now()
            : DateTime.now(),
        actionType: m['actionType'],
        actionData: m['actionData'],
        isApplied: m['isApplied'] == true || m['isApplied'] == 1,
      );

  factory ChatMessage.fromSqlite(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        sender: (m['sender'] ?? 'user') as String,
        text: (m['text'] ?? '') as String,
        timestamp: m['timestamp'] != null
            ? DateTime.tryParse(m['timestamp']) ?? DateTime.now()
            : DateTime.now(),
        actionType: m['action_type'] as String?,
        actionData: m['action_data'] as String?,
        isApplied: m['is_applied'] == 1,
      );
}
