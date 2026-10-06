import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Modal bottom sheet with the standard handle, title row and keyboard-aware
/// scrolling. All forms and pickers open through this.
class AppSheet {
  AppSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    Widget? footer,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SheetScaffold(title: title, footer: footer, child: builder(ctx)),
    );
  }
}

/// Layout used inside a bottom sheet (or a full-screen form dialog):
/// handle, title + close, scrollable body, optional pinned footer.
class SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? footer;

  const SheetScaffold({super.key, required this.title, required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ContentWidthSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: colors.border, borderRadius: AppRadius.pillAll),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, AppSpacing.xxs),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: context.text.titleLarge)),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  footer == null ? AppSpacing.lg : AppSpacing.md,
                ),
                child: child,
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.divider))),
                child: SafeArea(top: false, child: footer!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps sheets readable on tablets.
class ContentWidthSheet extends StatelessWidget {
  final Widget child;
  const ContentWidthSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: child),
    );
  }
}
