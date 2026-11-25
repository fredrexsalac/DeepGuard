import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DeepGuard accessible, theme-aware top app bar.
class DeepGuardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showLogo;

  const DeepGuardAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return AppBar(
      leading: leading,
      title: Semantics(
        header: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLogo) ...[
              ExcludeSemantics(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.brandNavy,
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.shield_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: actions,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      iconTheme: IconThemeData(color: palette.primaryText),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: palette.border),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
