import 'package:flutter/material.dart';
import '../models/timetable_slot.dart';
import '../services/database_service.dart';

class TimetableProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<TimetableSlot> _slots = [];
  String _selectedDay = 'All';

  List<TimetableSlot> get slots => _slots;
  String get selectedDay => _selectedDay;

  void clear() {
    _slots = [];
    notifyListeners();
  }

  static int parseTimeToMinutes(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPM = clean.contains('PM');
      final isAM = clean.contains('AM');
      final numPart = clean.replaceAll(RegExp(r'[^\d:]'), '').trim();
      final parts = numPart.split(':');
      if (parts.length >= 2) {
        int hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;
        return hour * 60 + minute;
      }
    } catch (_) {}
    return 0;
  }

  void _sortSlots() {
    _slots.sort((a, b) => parseTimeToMinutes(a.startTime)
        .compareTo(parseTimeToMinutes(b.startTime)));
  }

  void setSelectedDay(String day) {
    _selectedDay = day;
    notifyListeners();
  }

  Future<void> loadSlots(String uid) async {
    _slots = await _db.getTimetableSlots(uid);
    _sortSlots();
    notifyListeners();
  }

  List<TimetableSlot> getFilteredSlots(String day) {
    List<TimetableSlot> list;
    if (day == 'All' || day == 'Daily') {
      list = List.from(_slots);
    } else {
      list = _slots
          .where((s) => s.dayOfWeek == day || s.dayOfWeek == 'Daily')
          .toList();
    }
    list.sort((a, b) => parseTimeToMinutes(a.startTime)
        .compareTo(parseTimeToMinutes(b.startTime)));
    return list;
  }

  Future<void> addSlot(TimetableSlot slot) async {
    _slots.add(slot);
    _sortSlots();
    notifyListeners();
    await _db.upsertTimetableSlot(slot);
  }

  Future<void> addMultipleSlots(List<TimetableSlot> newSlots) async {
    _slots.addAll(newSlots);
    _sortSlots();
    notifyListeners();
    await _db.batchInsertTimetableSlots(newSlots);
  }

  Future<void> updateSlot(TimetableSlot slot) async {
    final idx = _slots.indexWhere((s) => s.id == slot.id);
    if (idx != -1) {
      _slots[idx] = slot.copyWith(updatedAt: DateTime.now());
      _sortSlots();
      notifyListeners();
      await _db.upsertTimetableSlot(_slots[idx]);
    }
  }

  Future<void> toggleCompleted(TimetableSlot slot) async {
    final updated = slot.copyWith(
      isCompleted: !slot.isCompleted,
      updatedAt: DateTime.now(),
    );
    final idx = _slots.indexWhere((s) => s.id == slot.id);
    if (idx != -1) {
      _slots[idx] = updated;
      notifyListeners();
      await _db.upsertTimetableSlot(updated);
    }
  }

  Future<void> deleteSlot(String id) async {
    _slots.removeWhere((s) => s.id == id);
    notifyListeners();
    await _db.softDeleteTimetableSlot(id);
  }
}
