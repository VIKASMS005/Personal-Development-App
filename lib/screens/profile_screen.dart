import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../providers/app_providers.dart';
import '../services/data_export_service.dart';
import '../widgets/ds/ds.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _phoneCtrl;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final uid = auth.uid ?? 'local_user';
      context.read<ProfileProvider>().loadProfile(uid).then((_) {
        if (!mounted) return;
        _fillControllers(context.read<ProfileProvider>().profile);
      });
    });
  }

  void _fillControllers(UserProfile? profile) {
    if (profile != null) {
      _nameCtrl.text = profile.name;
      _bioCtrl.text = profile.bio;
      _phoneCtrl.text = profile.phoneNumber;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SheetScaffold(
        title: 'Profile photo',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconBadge(icon: Icons.photo_camera_outlined, size: 40),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconBadge(icon: Icons.photo_library_outlined, size: 40),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      try {
        final img = await picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 800,
          maxHeight: 800,
        );
        if (img != null && mounted) {
          await context.read<ProfileProvider>().updatePhoto(img.path);
          setState(() {});
          if (mounted) {
            AppSnack.show(context, 'Profile photo updated', tone: StatusTone.success);
          }
        }
      } catch (e) {
        debugPrint('[ProfileScreen] Image pick failed: $e');
        if (mounted) {
          AppSnack.show(
            context,
            'Couldn\'t open the camera or gallery. Check app permissions and try again.',
            tone: StatusTone.error,
            duration: const Duration(seconds: 3),
          );
        }
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      await context.read<ProfileProvider>().updateProfile(
            name: _nameCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
          );
      setState(() => _isEditing = false);
      if (mounted) {
        AppSnack.show(context, 'Profile saved', tone: StatusTone.success);
      }
    }
  }

  void _cancelEdit() {
    _fillControllers(context.read<ProfileProvider>().profile);
    setState(() => _isEditing = false);
  }

  /// Shows only the last 4 digits until the user chooses to edit.
  String _maskedPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return phone;
    return '•••• ${digits.substring(digits.length - 4)}';
  }

  Future<void> _export(AuthProvider auth) async {
    final uid = auth.uid ?? 'local_user';
    final path = await DataExportService.instance.exportToDownloads(uid);
    if (!mounted) return;
    if (path != null) {
      AppSnack.show(context, 'Backup saved to $path', tone: StatusTone.success, duration: const Duration(seconds: 4));
    } else {
      AppSnack.show(context, 'Export didn\'t finish. Please try again.', tone: StatusTone.error);
    }
  }

  Future<void> _import(AuthProvider auth) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Restore from backup?',
      message: 'The backup will be merged with your current data. Records with the same ID will be overwritten.\n\n'
          'Choose a grow_backup_*.json file to continue.',
      confirmLabel: 'Choose file',
    );
    if (!confirm || !mounted) return;
    final success = await DataExportService.instance.importFromFile(
      uid: auth.uid ?? 'local_user',
    );
    if (!mounted) return;
    if (success) {
      // Reload all providers
      final uid = auth.uid ?? 'local_user';
      context.read<TodoProvider>().loadTodos(uid);
      context.read<HabitProvider>().loadHabits(uid);
      context.read<JournalProvider>().loadJournals(uid);
      context.read<FinanceProvider>().loadTransactions(uid);
      context.read<ReminderProvider>().loadReminders(uid);
      context.read<AlarmProvider>().loadAlarms(uid);
      AppSnack.show(context, 'Data restored', tone: StatusTone.success);
    } else {
      AppSnack.show(context, 'Nothing was restored. The file was cancelled or couldn\'t be read.',
          tone: StatusTone.error, duration: const Duration(seconds: 3));
    }
  }

  Future<void> _reset(AuthProvider auth) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Reset all local data?',
      message: 'This permanently deletes your tasks, habits, focus logs, journal, finances, alarms and routines '
          'from this device.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (ok && mounted) {
      await auth.resetAllLocalData();
      if (mounted) {
        final uid = auth.uid ?? 'local_user';
        context.read<ProfileProvider>().clear();
        context.read<TodoProvider>().clear();
        context.read<HabitProvider>().clear();
        context.read<JournalProvider>().clear();
        context.read<FinanceProvider>().clear();
        context.read<CalendarProvider>().clear();
        context.read<TimetableProvider>().clear();
        context.read<ChatbotProvider>().clear();
        context.read<ReminderProvider>().clear();
        context.read<AlarmProvider>().clear();
        context.read<StepProvider>().clear();

        context.read<ProfileProvider>().loadProfile(uid);
        context.read<TodoProvider>().loadTodos(uid);
        context.read<HabitProvider>().loadHabits(uid);
        context.read<JournalProvider>().loadJournals(uid);
        context.read<FinanceProvider>().loadTransactions(uid);
        context.read<CalendarProvider>().loadEvents(uid);
        context.read<TimetableProvider>().loadSlots(uid);
        context.read<ChatbotProvider>().loadMessages(uid);
        context.read<ReminderProvider>().loadReminders(uid);
        context.read<AlarmProvider>().loadAlarms(uid);
        context.read<StepProvider>().loadStepData(uid);

        AppSnack.show(context, 'All local data has been reset');
      }
    }
  }

  // The rest of the app uses the original theme; this screen keeps the
  // redesigned look, so it supplies the new theme for its own subtree.
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: dark ? AppTheme.dark() : AppTheme.light(),
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final isDark = context.isDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_isEditing)
            TextButton(
              onPressed: () => setState(() => _isEditing = true),
              child: const Text('Edit'),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: PageListView(
        clearFab: false,
        children: [
          _ProfileHeader(profile: profile, onChangePhoto: _pickImage),
          const SectionGap(),

          // ── Personal information ─────────────────────────────────────────
          const SectionHeader(title: 'Personal information'),
          AnimatedSwitcher(
            duration: AppMotion.medium,
            child: _isEditing ? _buildEditForm() : _buildInfo(profile),
          ),
          const SectionGap(),

          // ── Preferences ──────────────────────────────────────────────────
          const SectionHeader(title: 'Preferences'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text('Choose how Grow looks on this device.', style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                AppSegmented<bool>(
                  segments: const {false: 'Light', true: 'Dark'},
                  icons: const {false: Icons.light_mode_outlined, true: Icons.dark_mode_outlined},
                  selected: isDark,
                  onChanged: (dark) => themeProvider.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
          ),
          const SectionGap(),

          // ── Data & account ───────────────────────────────────────────────
          const SectionHeader(
            title: 'Data & account',
            subtitle: 'Everything is stored privately on this device.',
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Export backup'),
                  subtitle: const Text('Save a .json file to Downloads'),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
                  onTap: () => _export(auth),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('Restore from backup'),
                  subtitle: const Text('Import a previously exported file'),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
                  onTap: () => _import(auth),
                ),
                const Divider(indent: 56),
                ListTile(
                  iconColor: context.colors.error,
                  textColor: context.colors.error,
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Reset all local data'),
                  subtitle: const Text('Permanently delete everything on this device'),
                  onTap: () => _reset(auth),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(UserProfile? profile) {
    final phone = profile?.phoneNumber ?? '';
    final bio = profile?.bio ?? '';
    return AppCard(
      key: const ValueKey('info'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _InfoRow(icon: Icons.badge_outlined, label: 'Name', value: profile?.name.isNotEmpty == true ? profile!.name : 'Not set'),
          const Divider(indent: 56),
          _InfoRow(icon: Icons.notes_rounded, label: 'Bio', value: bio.isNotEmpty ? bio : 'Not set'),
          const Divider(indent: 56),
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phone.isNotEmpty ? _maskedPhone(phone) : 'Not set',
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return AppCard(
      key: const ValueKey('edit'),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _bioCtrl,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Bio',
                hintText: 'e.g. Daily discipline, fitness, learning',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _cancelEdit, child: const Text('Cancel'))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: FilledButton(onPressed: _saveProfile, child: const Text('Save'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onChangePhoto;

  const _ProfileHeader({required this.profile, required this.onChangePhoto});

  @override
  Widget build(BuildContext context) {
    final photoPath = profile?.photoPath;
    final hasValidFile = photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync();
    final name = profile?.name.isNotEmpty == true ? profile!.name : 'Grow member';
    final initial = name.substring(0, 1).toUpperCase();
    final bio = profile?.bio ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                key: ValueKey(photoPath),
                radius: 44,
                backgroundColor: context.scheme.primaryContainer,
                backgroundImage: hasValidFile ? FileImage(File(photoPath)) : null,
                child: !hasValidFile
                    ? Text(initial, style: context.text.headlineMedium?.copyWith(color: context.scheme.onPrimaryContainer))
                    : null,
              ),
              Positioned(
                right: -8,
                bottom: -8,
                child: Material(
                  color: context.scheme.surface,
                  shape: CircleBorder(side: BorderSide(color: context.colors.border)),
                  child: IconButton(
                    tooltip: 'Change photo',
                    onPressed: onChangePhoto,
                    icon: Icon(Icons.photo_camera_outlined, size: AppSizes.iconMd, color: context.colors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(name, style: context.text.headlineSmall, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(bio, style: context.text.bodySmall, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: AppSpacing.sm),
          const StatusBadge(label: 'Stored on this device', icon: Icons.lock_outline_rounded, tone: StatusTone.primary),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: context.text.labelSmall),
      subtitle: Text(value, style: context.text.bodyLarge),
    );
  }
}
