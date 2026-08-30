import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/screen_time_record.dart';

/// ScreenTimeService — fetches real foreground-only application usage stats on Android.
///
/// Uses the native UsageEvents API (MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND event pairs)
/// via MethodChannel instead of the Flutter app_usage package.
///
/// Why this is correct:
///   • app_usage package uses queryUsageStats() → includes background processes, sync,
///     notifications — NOT actual user screen time.
///   • UsageEvents with event pairs → exact foreground user time only.
///   • Screen-off safe: when screen locks, Android fires MOVE_TO_BACKGROUND for all apps.
///   • Open sessions capped at query endMs so screen-off time is never accumulated.
class ScreenTimeService {
  static final ScreenTimeService instance = ScreenTimeService._internal();
  ScreenTimeService._internal();

  static const _channel = MethodChannel('com.grow.app/settings');

  // Memory cache of package → {appName, iconBase64}
  final Map<String, Map<String, String>> _appMetadataCache = {};

  // Range query cache for completed past windows (key = startMs_endMs)
  final Map<String, List<AppUsageRecord>> _rangeUsageCache = {};

  /// Query foreground-only per-app usage for the given time range.
  /// Returns only apps the user ACTUALLY had in foreground (min 1 second).
  Future<List<AppUsageRecord>> getUsageForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!Platform.isAndroid) return [];
    if (startDate.isAfter(endDate)) return [];

    final startMs = startDate.millisecondsSinceEpoch;
    final endMs = endDate.millisecondsSinceEpoch;
    final cacheKey = '${startMs}_$endMs';
    final now = DateTime.now();

    // Cache completed past windows (not current/live windows)
    final isHistorical = endDate.isBefore(now.subtract(const Duration(minutes: 5)));
    if (isHistorical && _rangeUsageCache.containsKey(cacheKey)) {
      return _rangeUsageCache[cacheKey]!;
    }

    try {
      // Call native Kotlin UsageEvents computation
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getUsageEvents',
        {'startMs': startMs, 'endMs': endMs},
      );

      if (raw == null || raw.isEmpty) {
        if (isHistorical) _rangeUsageCache[cacheKey] = [];
        return [];
      }

      // raw = List<Map<String, Any>> [{packageName, durationMs}, ...]
      final entries = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['durationMs'] as num? ?? 0) >= 1000)
          .toList();

      if (entries.isEmpty) {
        if (isHistorical) _rangeUsageCache[cacheKey] = [];
        return [];
      }

      // Resolve app names + icons for uncached packages
      final packagesToFetch = entries
          .map((e) => e['packageName'] as String)
          .where((pkg) => !_appMetadataCache.containsKey(pkg))
          .toList();

      if (packagesToFetch.isNotEmpty) {
        try {
          final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'getBatchAppInfo',
            {'packages': packagesToFetch},
          );
          if (res != null) {
            for (final entry in res.entries) {
              final pkg = entry.key.toString();
              final data = Map<String, String>.from(entry.value as Map);
              _appMetadataCache[pkg] = data;
            }
          }
        } catch (e) {
          debugPrint('[ScreenTime] Error fetching batch app info: $e');
        }
      }

      final result = entries.map((e) {
        final pkg = e['packageName'] as String;
        final durationMs = (e['durationMs'] as num).toInt();
        final cached = _appMetadataCache[pkg];
        final realName = cached?['appName'] ?? _formatFallbackName(pkg);
        final iconBase64 = cached?['iconBase64'];

        return AppUsageRecord(
          packageName: pkg,
          appName: realName,
          usage: Duration(milliseconds: durationMs),
          startDate: startDate,
          endDate: endDate,
          iconBase64: iconBase64,
        );
      }).toList();

      // Sort by descending usage duration
      result.sort((a, b) => b.usage.compareTo(a.usage));

      if (isHistorical) _rangeUsageCache[cacheKey] = result;
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'NO_PERMISSION') {
        debugPrint('[ScreenTime] Usage access not granted');
      } else {
        debugPrint('[ScreenTime] Platform error: ${e.message}');
      }
      return [];
    } catch (e) {
      debugPrint('[ScreenTime] Query error: $e');
      return [];
    }
  }

  /// Today's usage from midnight to now.
  Future<DailyScreenTimeSummary> getTodayUsage() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return getSummaryForRange(
      startDate: startOfToday,
      endDate: now,
      dateLabel: now.toIso8601String().split('T')[0],
    );
  }

  /// Aggregate summary for any time range.
  Future<DailyScreenTimeSummary> getSummaryForRange({
    required DateTime startDate,
    required DateTime endDate,
    required String dateLabel,
  }) async {
    final apps = await getUsageForRange(startDate: startDate, endDate: endDate);

    Duration sumTotal = Duration.zero;
    final Map<String, Duration> categoryBreakdown = {};

    for (final app in apps) {
      sumTotal += app.usage;
      categoryBreakdown[app.category] =
          (categoryBreakdown[app.category] ?? Duration.zero) + app.usage;
    }

    // No wall-clock clamping needed — UsageEvents is inherently accurate.
    // We keep a safety guard just in case of data corruption.
    final wallClock = endDate.difference(startDate);
    final safeTotal = (wallClock > Duration.zero && sumTotal > wallClock)
        ? wallClock
        : sumTotal;

    return DailyScreenTimeSummary(
      date: dateLabel,
      totalDuration: safeTotal,
      appUsages: apps,
      categoryBreakdown: categoryBreakdown,
    );
  }

  /// Check if usage access permission is granted.
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('hasUsagePermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static String _formatFallbackName(String packageName) {
    // Known popular package mappings for instant reliable fallback
    const knownOverrides = {
      'com.mxtech.videoplayer.ad': 'MX Player',
      'com.mxtech.videoplayer.pro': 'MX Player Pro',
      'com.whatsapp': 'WhatsApp',
      'com.instagram.android': 'Instagram',
      'com.google.android.youtube': 'YouTube',
      'com.google.android.apps.docs': 'Google Drive',
      'com.google.android.gm': 'Gmail',
      'com.google.android.apps.photos': 'Google Photos',
      'com.spotify.music': 'Spotify',
      'com.netflix.mediaclient': 'Netflix',
      'com.twitter.android': 'X (Twitter)',
      'org.telegram.messenger': 'Telegram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.amazon.mShop.android.shopping': 'Amazon',
      'in.amazon.mShop.android.shopping': 'Amazon',
      'com.flipkart.android': 'Flipkart',
      'com.google.android.apps.maps': 'Google Maps',
      'com.google.android.calculator': 'Calculator',
      'com.google.android.calendar': 'Google Calendar',
    };
    if (knownOverrides.containsKey(packageName)) {
      return knownOverrides[packageName]!;
    }

    final parts = packageName.split('.');
    if (parts.length >= 2) {
      // Find the most meaningful segment (ignoring generic suffixes like 'ad', 'pro', 'lite', 'free', 'app', 'android')
      const ignoredSuffixes = {'ad', 'ads', 'pro', 'lite', 'free', 'app', 'android', 'client', 'mobile', 'release'};
      String candidate = '';
      for (int i = parts.length - 1; i >= 0; i--) {
        final segment = parts[i].toLowerCase();
        if (!ignoredSuffixes.contains(segment) && segment.length >= 3) {
          candidate = parts[i];
          break;
        }
      }
      if (candidate.isEmpty) {
        candidate = parts.length > 2 ? parts[parts.length - 2] : parts.last;
      }
      if (candidate.length > 1) {
        final spaced = candidate
            .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
            .replaceAll('_', ' ');
        return spaced.trim()[0].toUpperCase() + spaced.trim().substring(1);
      }
    }
    return packageName;
  }

  void clearCache() {
    _rangeUsageCache.clear();
    // Keep app metadata cache — icons don't change
  }

  void clearAllCache() {
    _rangeUsageCache.clear();
    _appMetadataCache.clear();
  }
}