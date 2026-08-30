import 'package:flutter/material.dart';
import '../models/journal_entry.dart';
import '../services/database_service.dart';

class JournalProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<JournalEntry> _entries = [];

  List<JournalEntry> get entries => _entries;

  void clear() {
    _entries = [];
    notifyListeners();
  }

  Future<void> loadJournals(String uid) async {
    _entries = await _db.getJournals(uid);
    notifyListeners();
  }

  Future<void> addJournal(JournalEntry entry) async {
    _entries.insert(0, entry);
    notifyListeners();
    await _db.upsertJournal(entry);
  }

  Future<void> updateJournal(JournalEntry entry) async {
    final idx = _entries.indexWhere((j) => j.id == entry.id);
    if (idx != -1) {
      _entries[idx] = entry.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _db.upsertJournal(_entries[idx]);
    }
  }

  Future<void> deleteJournal(String id) async {
    _entries.removeWhere((j) => j.id == id);
    notifyListeners();
    await _db.softDeleteJournal(id);
  }
}
