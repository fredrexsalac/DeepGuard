import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Custom DeepGuard branded app bar with cyber-security styling.
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
    return AppBar(
      leading: leading,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: DeepGuardColors.primaryGradient,
                ),
              ),
              child: const Center(
                child: Icon(Icons.visibility, size: 16, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: const TextStyle(
              color: DeepGuardColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
      actions: actions,
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: DeepGuardColors.primary),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// DeepGuard branded bottom navigation bar.
class DeepGuardBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const DeepGuardBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: DeepGuardColors.glassBorder,
            width: 0.5,
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: DeepGuardColors.surfaceDark,
        selectedItemColor: DeepGuardColors.primary,
        unselectedItemColor: DeepGuardColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_photo_alternate_outlined),
            activeIcon: Icon(Icons.add_photo_alternate),
            label: 'Analyze',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            activeIcon: Icon(Icons.info),
            label: 'About',
          ),
        ],
      ),
    );
  }
}