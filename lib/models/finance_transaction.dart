import 'package:uuid/uuid.dart';

class FinanceTransaction {
  String id;
  String uid;
  String title;
  double amount;
  String category;
  DateTime date;
  String note;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  FinanceTransaction({
    String? id,
    this.uid = '',
    required this.title,
    required this.amount,
    this.category = 'General',
    DateTime? date,
    this.note = '',
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  FinanceTransaction copyWith({
    String? id,
    String? uid,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? note,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return FinanceTransaction(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'note': note,
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'note': note,
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory FinanceTransaction.fromMap(Map<String, dynamic> m) =>
      FinanceTransaction(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        amount: (m['amount'] is num)
            ? (m['amount'] as num).toDouble()
            : double.tryParse('${m['amount']}') ?? 0.0,
        category: (m['category'] ?? 'General') as String,
        date: m['date'] != null
            ? DateTime.tryParse(m['date'].toString()) ?? DateTime.now()
            : DateTime.now(),
        note: (m['note'] ?? '') as String,
        updatedAt: m['updatedAt'] != null
            ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
        isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
      );

  factory FinanceTransaction.fromSqlite(Map<String, dynamic> m) =>
      FinanceTransaction(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        amount: (m['amount'] is num)
            ? (m['amount'] as num).toDouble()
            : double.tryParse('${m['amount']}') ?? 0.0,
        category: (m['category'] ?? 'General') as String,
        date: m['date'] != null
            ? DateTime.tryParse(m['date'].toString()) ?? DateTime.now()
            : DateTime.now(),
        note: (m['note'] ?? '') as String,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: m['is_synced'] == 1,
        isDeleted: m['is_deleted'] == 1,
      );
}

