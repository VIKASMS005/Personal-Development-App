import 'package:flutter/material.dart';
import '../../models/finance_transaction.dart';
import 'package:intl/intl.dart';
import '../../widgets/ds/ds.dart';

class FinanceForm extends StatefulWidget {
  final FinanceTransaction? initial;
  final DateTime? defaultDate;
  const FinanceForm({super.key, this.initial, this.defaultDate});

  static Future<FinanceTransaction?> show(BuildContext context, {FinanceTransaction? initial, DateTime? defaultDate}) =>
      showModalBottomSheet<FinanceTransaction?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FinanceForm(initial: initial, defaultDate: defaultDate),
      );

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
    _date = t?.date ?? widget.defaultDate ?? DateTime.now();
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
      uid: widget.initial?.uid ?? 'local_user',
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
    final categories = _categories.contains(_category) ? _categories : [..._categories, _category];

    return SheetScaffold(
      title: isEdit ? 'Edit entry' : 'New entry',
      footer: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : (_isExpense ? 'Add expense' : 'Add income')),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSegmented<bool>(
              segments: const {true: 'Expense', false: 'Income'},
              icons: const {true: Icons.north_east_rounded, false: Icons.south_west_rounded},
              selected: _isExpense,
              onChanged: (v) => setState(() => _isExpense = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amountC,
              autofocus: !isEdit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              style: context.text.titleLarge,
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                prefixText: '₹ ',
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null) return 'Enter an amount, e.g. 250';
                if (n == 0) return 'Amount can\'t be zero';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _titleC,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: _isExpense ? 'e.g. Groceries' : 'e.g. Salary',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please add a short description' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            PickerField(
              label: 'Date',
              value: DateFormat('EEE, MMM d, yyyy').format(_date),
              icon: Icons.calendar_today_outlined,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Category'),
            ChoiceWrap<String>(
              options: categories,
              selected: _category,
              labelOf: (c) => c,
              onSelected: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _noteC,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}
