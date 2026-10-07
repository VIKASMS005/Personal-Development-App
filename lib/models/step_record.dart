import 'package:uuid/uuid.dart';

class StepRecord {
  String id;
  String uid;
  String date; // YYYY-MM-DD
  int stepCount;
  int goal;
  double calories;
  double distanceKm;
  int activeMinutes;
  DateTime updatedAt;

  StepRecord({
    String? id,
    this.uid = '',
    required this.date,
    this.stepCount = 0,
    this.goal = 6000,
    double? calories,
    double? distanceKm,
    int? activeMinutes,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        calories = calories ?? _calculateCalories(stepCount),
        distanceKm = distanceKm ?? _calculateDistance(stepCount),
        activeMinutes = activeMinutes ?? _calculateActiveMinutes(stepCount),
        updatedAt = updatedAt ?? DateTime.now();

  static double _calculateCalories(int steps) => steps * 0.04; // avg 0.04 kcal/step
  static double _calculateDistance(int steps) => (steps * 0.762) / 1000.0; // avg 0.762m/step in km
  static int _calculateActiveMinutes(int steps) => (steps / 100.0).round(); // approx 100 steps/min

  double get progressPercentage => goal > 0 ? (stepCount / goal).clamp(0.0, 1.0) : 0.0;
  bool get isGoalReached => stepCount >= goal;

  StepRecord copyWith({
    String? id,
    String? uid,
    String? date,
    int? stepCount,
    int? goal,
    double? calories,
    double? distanceKm,
    int? activeMinutes,
    DateTime? updatedAt,
  }) {
    final count = stepCount ?? this.stepCount;
    return StepRecord(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      date: date ?? this.date,
      stepCount: count,
      goal: goal ?? this.goal,
      calories: calories ?? _calculateCalories(count),
      distanceKm: distanceKm ?? _calculateDistance(count),
      activeMinutes: activeMinutes ?? _calculateActiveMinutes(count),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'date': date,
        'step_count': stepCount,
        'goal': goal,
        'calories': calories,
        'distance_km': distanceKm,
        'active_minutes': activeMinutes,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StepRecord.fromMap(Map<String, dynamic> map) {
    return StepRecord(
      id: map['id']?.toString(),
      uid: map['uid']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      stepCount: (map['step_count'] as num?)?.toInt() ?? 0,
      goal: (map['goal'] as num?)?.toInt() ?? 6000,
      // Calories, distance and active minutes are estimates derived from the
      // step count. They are recomputed here rather than read back, because
      // older native writes used a different stride length (0.75 m), which
      // made the same day show different distances in different places.
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
