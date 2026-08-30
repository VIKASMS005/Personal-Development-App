import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../providers/app_providers.dart';
import '../utils/app_colors.dart';
import '../services/data_export_service.dart';

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
        final profile = context.read<ProfileProvider>().profile;
        if (profile != null) {
          _nameCtrl.text = profile.name;
          _bioCtrl.text = profile.bio;
          _phoneCtrl.text = profile.phoneNumber;
        }
      });
    });
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
      backgroundColor: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Change Profile Photo',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.secondary),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✨ Profile photo updated!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not access camera/gallery: $e'),
              backgroundColor: AppColors.error,
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profileProvider = context.watch<ProfileProvider>();
    final profile = profileProvider.profile;
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_isEditing ? Icons.check_rounded : Icons.edit_rounded, size: 16),
              label: Text(_isEditing ? 'Save' : 'Edit', style: const TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () {
                if (_isEditing) {
                  _saveProfile();
                } else {
                  setState(() => _isEditing = true);
                }
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero Header Card
                  _buildHeroHeader(profile, theme, isDark)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: -0.05, end: 0),
                  const SizedBox(height: 18),

                  // 2. Personal Information Section Card
                  _buildSectionCard(
                    theme: theme,
                    title: 'Personal Information',
                    icon: Icons.person_outline_rounded,
                    iconColor: AppColors.primary,
                    child: Column(
                      children: [
                        // Name Field
                        _buildInputField(
                          controller: _nameCtrl,
                          label: 'Full Name',
                          hint: 'Enter your name',
                          icon: Icons.badge_outlined,
                          iconColor: AppColors.primary,
                          enabled: _isEditing,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                        ),
                        const SizedBox(height: 14),

                        // Bio Field
                        _buildInputField(
                          controller: _bioCtrl,
                          label: 'Focus Goals & Bio',
                          hint: 'e.g. Daily discipline, physical fitness, continuous learning',
                          icon: Icons.psychology_outlined,
                          iconColor: AppColors.accent,
                          maxLines: 2,
                          enabled: _isEditing,
                        ),
                        const SizedBox(height: 14),

                        // Phone Field
                        _buildInputField(
                          controller: _phoneCtrl,
                          label: 'Phone Number',
                          hint: '+1 555-0199',
                          icon: Icons.phone_outlined,
                          iconColor: AppColors.timetable,
                          keyboardType: TextInputType.phone,
                          enabled: _isEditing,
                        ),

                        if (_isEditing) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 20),
                              label: const Text('Save Profile Changes',
                                  style: TextStyle(fontWeight: FontWeight.w800)),
                              onPressed: _saveProfile,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 16),

                  // 3. Preferences Section
                  _buildSectionCard(
                    theme: theme,
                    title: 'App Preferences',
                    icon: Icons.tune_rounded,
                    iconColor: AppColors.secondary,
                    child: Column(
                      children: [
                        // Appearance Theme Switch
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            isDark ? 'Theme: Dark Mode' : 'Theme: Light Mode',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          subtitle: Text(
                            isDark
                                ? 'Switch to clean Light theme'
                                : 'Switch to eye-friendly Dark theme',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.secondary.withValues(alpha: 0.15)
                                  : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                              color: isDark ? AppColors.secondary : AppColors.accent,
                              size: 20,
                            ),
                          ),
                          value: isDark,
                          activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                          onChanged: (_) => themeProvider.toggleTheme(context),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 24),

                  // 4. Data Backup Card
                  _buildSectionCard(
                    theme: theme,
                    title: 'Data Backup',
                    icon: Icons.backup_rounded,
                    iconColor: AppColors.timetable,
                    child: Column(
                      children: [
                        // Export
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.timetable,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.upload_rounded, size: 20),
                            label: const Text('Export My Data', style: TextStyle(fontWeight: FontWeight.w800)),
                            onPressed: () async {
                              final uid = auth.uid ?? 'local_user';
                              final path = await DataExportService.instance.exportToDownloads(uid);
                              if (!context.mounted) return;
                              if (path != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Backup saved!\n$path'),
                                    backgroundColor: AppColors.success,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('❌ Export failed. Please try again.'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Import
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.timetable,
                              side: const BorderSide(color: AppColors.timetable, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: const Text('Import & Restore Data', style: TextStyle(fontWeight: FontWeight.w800)),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Restore from Backup?'),
                                  content: const Text(
                                    'This will merge the backup data with your current data. Existing records with the same ID will be overwritten.\n\nPick your grow_backup_*.json file to continue.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text(
                                        'Pick File & Restore',
                                        style: TextStyle(color: AppColors.timetable, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true || !context.mounted) return;
                              final success = await DataExportService.instance.importFromFile();
                              if (!context.mounted) return;
                              if (success) {
                                // Reload all providers
                                final uid = auth.uid ?? 'local_user';
                                context.read<TodoProvider>().loadTodos(uid);
                                context.read<HabitProvider>().loadHabits(uid);
                                context.read<JournalProvider>().loadJournals(uid);
                                context.read<FinanceProvider>().loadTransactions(uid);
                                context.read<ReminderProvider>().loadReminders(uid);
                                context.read<AlarmProvider>().loadAlarms(uid);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Data restored successfully!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('❌ Import failed or cancelled.'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Export saves a .json file to your Downloads folder. You can import it any time to restore all data.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 350.ms),
                  const SizedBox(height: 16),

                  // 5. Reset All Local Data
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text(
                        'Reset All Local Data',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Reset All Local Data?'),
                            content: const Text(
                              '⚠️ This will permanently clear all your local tasks, habits, focus logs, journals, finances, alarms, and routines from this device.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Clear Everything',
                                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await auth.resetAllLocalData();
                          if (context.mounted) {
                            final uid = auth.uid ?? 'local_user';
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

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🗑️ All local data has been reset.'),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ).animate().fadeIn(delay: 450.ms),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== WIDGET BUILDERS ====================

  Widget _buildHeroHeader(UserProfile? profile, ThemeData theme, bool isDark) {
    final photoPath = profile?.photoPath;
    final hasValidFile =
        photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync();
    final initial = (profile?.name.isNotEmpty == true
            ? profile!.name.substring(0, 1)
            : 'G')
        .toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  AppColors.primary.withValues(alpha: 0.2),
                  theme.colorScheme.surface,
                ]
              : [
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.primary.withValues(alpha: 0.03),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.15),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: CircleAvatar(
                  key: ValueKey(photoPath),
                  radius: 38,
                  backgroundColor: theme.colorScheme.surface,
                  backgroundImage: hasValidFile ? FileImage(File(photoPath)) : null,
                  child: !hasValidFile
                      ? Text(
                          initial,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.name.isNotEmpty == true ? profile!.name : 'Grow Member',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '100% Offline & Private',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, size: 14, color: AppColors.primary),
                      SizedBox(width: 5),
                      Text(
                        'Local Storage Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildInputField({
    TextEditingController? controller,
    String? initialValue,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    bool enabled = true,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: enabled ? iconColor : Colors.grey, size: 20),
        ),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
