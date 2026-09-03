class AppUsageRecord {
  final String packageName;
  final String appName;
  final Duration usage;
  final DateTime startDate;
  final DateTime endDate;
  final String category;
  final String? iconBase64;

  AppUsageRecord({
    required this.packageName,
    required this.appName,
    required this.usage,
    required this.startDate,
    required this.endDate,
    String? category,
    this.iconBase64,
  }) : category = category ?? _categorize(packageName, appName);

  int get durationInSeconds => usage.inSeconds;
  int get durationInMinutes => usage.inMinutes;

  AppUsageRecord copyWith({
    String? packageName,
    String? appName,
    Duration? usage,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? iconBase64,
  }) {
    return AppUsageRecord(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      usage: usage ?? this.usage,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      category: category ?? this.category,
      iconBase64: iconBase64 ?? this.iconBase64,
    );
  }

  static String _categorize(String pkg, String name) {
    final lower = (pkg + name).toLowerCase();
    if (lower.contains('youtube') ||
        lower.contains('netflix') ||
        lower.contains('spotify') ||
        lower.contains('music') ||
        lower.contains('video') ||
        lower.contains('prime') ||
        lower.contains('disney')) {
      return 'Entertainment';
    }
    if (lower.contains('instagram') ||
        lower.contains('whatsapp') ||
        lower.contains('telegram') ||
        lower.contains('facebook') ||
        lower.contains('twitter') ||
        lower.contains('tiktok') ||
        lower.contains('snapchat') ||
        lower.contains('reddit') ||
        lower.contains('discord') ||
        lower.contains('social')) {
      return 'Social';
    }
    if (lower.contains('game') ||
        lower.contains('pubg') ||
        lower.contains('candy') ||
        lower.contains('roblox') ||
        lower.contains('clash')) {
      return 'Gaming';
    }
    if (lower.contains('grow') ||
        lower.contains('code') ||
        lower.contains('study') ||
        lower.contains('notion') ||
        lower.contains('calendar') ||
        lower.contains('todo') ||
        lower.contains('docs') ||
        lower.contains('sheets') ||
        lower.contains('drive') ||
        lower.contains('mail') ||
        lower.contains('gmail') ||
        lower.contains('slack') ||
        lower.contains('teams') ||
        lower.contains('zoom') ||
        lower.contains('github')) {
      return 'Productivity';
    }
    if (lower.contains('chrome') ||
        lower.contains('browser') ||
        lower.contains('safari') ||
        lower.contains('firefox') ||
        lower.contains('edge') ||
        lower.contains('opera')) {
      return 'Browsing';
    }
    return 'Utilities';
  }
}

class DailyScreenTimeSummary {
  final String date;
  final Duration totalDuration;
  final List<AppUsageRecord> appUsages;
  final Map<String, Duration> categoryBreakdown;

  DailyScreenTimeSummary({
    required this.date,
    required this.totalDuration,
    required this.appUsages,
    required this.categoryBreakdown,
  });
}
