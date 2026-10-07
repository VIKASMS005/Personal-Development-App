import 'package:flutter/material.dart';
import '../models/finance_transaction.dart';
import '../services/database_service.dart';

class FinanceProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<FinanceTransaction> _transactions = [];

  List<FinanceTransaction> get transactions => _transactions;

  double get totalBalance =>
      _transactions.fold(0.0, (sum, t) => sum + t.amount);
  double get totalIncome => _transactions
      .where((t) => t.amount > 0)
      .fold(0.0, (sum, t) => sum + t.amount);
  double get totalExpense => _transactions
      .where((t) => t.amount < 0)
      .fold(0.0, (sum, t) => sum + t.amount.abs());

  /// Money spent in calendar year [year].
  double expenseForYear(int year) => _transactions
      .where((t) => t.amount < 0 && t.date.year == year)
      .fold(0.0, (sum, t) => sum + t.amount.abs());

  void clear() {
    _transactions = [];
    notifyListeners();
  }

  Future<void> loadTransactions(String uid) async {
    _transactions = await _db.getTransactions(uid);
    notifyListeners();
  }

  Future<void> addTransaction(FinanceTransaction tx) async {
    _transactions.insert(0, tx);
    notifyListeners();
    await _db.upsertTransaction(tx);
  }

  Future<void> updateTransaction(FinanceTransaction tx) async {
    final idx = _transactions.indexWhere((t) => t.id == tx.id);
    if (idx != -1) {
      _transactions[idx] = tx.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _db.upsertTransaction(_transactions[idx]);
    }
  }

  Future<void> deleteTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
    await _db.softDeleteTransaction(id);
  }
}
