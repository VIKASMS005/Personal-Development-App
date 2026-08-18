import 'dart:convert';
import 'package:flutter/material.dart';

class AlarmModel {
  String id;
  String uid;
  int hour;
  int minute;
  String label;
  List<int> daysOfWeek; // 1 = Monday ... 7 = Sunday
  bool isEnabled;
  DateTime createdAt;

  AlarmModel({
    required this.id,
    required this.uid,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.daysOfWeek = const [],
    this.isEnabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String get formattedTime {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  String get daysSummary {
    if (daysOfWeek.isEmpty) return 'Once';
    if (daysOfWeek.length == 7) return 'Everyday';
    if (daysOfWeek.length == 5 &&
        daysOfWeek.contains(1) &&
        daysOfWeek.contains(2) &&
        daysOfWeek.contains(3) &&
        daysOfWeek.contains(4) &&
        daysOfWeek.contains(5)) {
      return 'Weekdays';
    }
    if (daysOfWeek.length == 2 &&
        daysOfWeek.contains(6) &&
        daysOfWeek.contains(7)) {
      return 'Weekends';
    }
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = List<int>.from(daysOfWeek)..sort();
    return sorted.map((d) => dayNames[d - 1]).join(', ');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'hour': hour,
      'minute': minute,
      'label': label,
      'days_of_week': jsonEncode(daysOfWeek),
      'is_enabled': isEnabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    List<int> days = [];
    if (map['days_of_week'] != null) {
      try {
        final decoded = map['days_of_week'] is List
            ? map['days_of_week']
            : jsonDecode(map['days_of_week'].toString());
        if (decoded is List) {
          days = decoded.map((e) => (e is num) ? e.toInt() : int.tryParse('$e') ?? 1).toList();
        }
      } catch (_) {}
    }

    return AlarmModel(
      id: (map['id'] ?? '').toString(),
      uid: (map['uid'] as String?) ?? '',
      hour: (map['hour'] is num)
          ? (map['hour'] as num).toInt()
          : int.tryParse('${map['hour']}') ?? 7,
      minute: (map['minute'] is num)
          ? (map['minute'] as num).toInt()
          : int.tryParse('${map['minute']}') ?? 0,
      label: (map['label'] as String?) ?? 'Alarm',
      daysOfWeek: days,
      isEnabled: (map['is_enabled'] == 1 || map['is_enabled'] == true || map['is_enabled'] == 'true'),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  AlarmModel copyWith({
    String? id,
    String? uid,
    int? hour,
    int? minute,
    String? label,
    List<int>? daysOfWeek,
    bool? isEnabled,
    DateTime? createdAt,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
