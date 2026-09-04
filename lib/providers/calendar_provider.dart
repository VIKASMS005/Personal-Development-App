import 'package:flutter/material.dart';
import '../models/calendar_event.dart';
import '../services/database_service.dart';

class CalendarProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => _events;

  void clear() {
    _events = [];
    notifyListeners();
  }

  Future<void> loadEvents(String uid) async {
    _events = await _db.getCalendarEvents(uid);
    notifyListeners();
  }

  List<CalendarEvent> getEventsForDay(DateTime day) {
    return _events.where((e) {
      final eLocal = e.dateTime.toLocal();
      return eLocal.year == day.year &&
          eLocal.month == day.month &&
          eLocal.day == day.day;
    }).toList();
  }

  Future<void> addEvent(CalendarEvent event) async {
    _events.add(event);
    notifyListeners();
    await _db.upsertCalendarEvent(event);
  }

  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    notifyListeners();
    await _db.softDeleteCalendarEvent(id);
  }
}
