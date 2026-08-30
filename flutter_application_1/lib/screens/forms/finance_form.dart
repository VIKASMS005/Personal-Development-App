import 'package:flutter/material.dart';
import '../../models/finance_transaction.dart';
import '../../utils/app_colors.dart';

class FinanceForm extends StatefulWidget {
  final FinanceTransaction? initial;
  const FinanceForm({super.key, this.initial});

  static Future<FinanceTransaction?> show(BuildContext context, {FinanceTransaction? initial}) {
    return showDialog<FinanceTransaction?>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: FinanceForm(initial: initial),
      ),
    );
  }

  @override
  State<FinanceForm> createState() => _FinanceFormState();
}

class _FinanceFormState extends State<FinanceForm> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _titleC;
  late TextEditingController _amountC;
  late TextEditingController _noteC;
  late String _category;
  late bool _isExpense;
  DateTime _date = DateTime.now();

  static const _categories = [
    'General',
    'Food & Dining',
    'Groceries',
    'Salary',
    'Shopping',
    'Bills & Utilities',
    'Investment',
    'Travel',
    'Health',
    'Education',
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _titleC = TextEditingController(text: t?.title ?? '');
    _amountC = TextEditingController(text: t != null ? t.amount.abs().toStringAsFixed(2) : '');
    _noteC = TextEditingController(text: t?.note ?? '');
    _category = t?.category ?? 'General';
    _isExpense = t != null ? t.amount < 0 : true;
    _date = t?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _amountC.dispose();
    _noteC.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final rawAmount = double.tryParse(_amountC.text.trim()) ?? 0.0;
    final finalAmount = _isExpense ? -rawAmount.abs() : rawAmount.abs();

    final tx = FinanceTransaction(
      id: widget.initial?.id,
      title: _titleC.text.trim(),
      amount: finalAmount,
      category: _category,
      date: _date,
      note: _noteC.text.trim(),
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, tx);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Edit Transaction' : 'New Transaction',
                  style: theme.textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Expense / Income Toggle
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.error),
                    label: const Center(child: Text('Expense')),
                    selected: _isExpense,
                    selectedColor: AppColors.error.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: _isExpense ? AppColors.error : null,
                      fontWeight: _isExpense ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _isExpense = true);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.success),
                    label: const Center(child: Text('Income')),
                    selected: !_isExpense,
                    selectedColor: AppColors.success.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: !_isExpense ? AppColors.success : null,
                      fontWeight: !_isExpense ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _isExpense = false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleC,
              decoration: const InputDecoration(
                labelText: 'Title / Description',
                hintText: 'e.g. Monthly Grocery, Client Payment',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amountC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                hintText: '0.00',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty || double.tryParse(v.trim()) == null)
                  ? 'Enter a valid amount'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'General'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text('Date: ${_date.toLocal().toString().split(' ')[0]}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: Text(isEdit ? 'Save Changes' : 'Record Transaction'),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
