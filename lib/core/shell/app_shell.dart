import 'package:flutter/services.dart';
import '../../features/command_palette/presentation/command_palette_dialog.dart';
import '../utils/jwt_utils.dart';
import 'package:admin_dashboard/core/constants/app_colors.dart';
import 'package:admin_dashboard/core/router/app_router.dart';
import 'package:admin_dashboard/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/pin_lock/presentation/pin_lock_controller.dart';
import '../../features/pin_lock/presentation/pin_lock_overlay.dart';
import '../../features/pin_lock/presentation/set_pin_dialog.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final pinState = ref.watch(pinLockProvider);


    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          ref.read(pinLockProvider.notifier).resetInactivityTimer(),
      onPointerMove: (_) =>
          ref.read(pinLockProvider.notifier).resetInactivityTimer(),
      onPointerHover: (_) =>
          ref.read(pinLockProvider.notifier).resetInactivityTimer(),
      child: Stack(
        children: [
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                  CommandPaletteDialog.show(context),
              const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                  CommandPaletteDialog.show(context),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: Row(
                  children: [
                    if (isDesktop) const _SideNav(),
                    Expanded(child: child),
                  ],
                ),
                drawer: isDesktop ? null : const Drawer(child: _SideNav()),
                appBar: isDesktop
                    ? null
                    : AppBar(
                        backgroundColor: AppColors.darkGreen,
                        iconTheme: const IconThemeData(color: AppColors.gold),
                        title: Image.asset('assets/images/Untitled-1.png', height: 36),
                        centerTitle: true,
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.search, color: AppColors.gold),
                            tooltip: 'لوحة الأوامر السريعة (Ctrl+K)',
                            onPressed: () => CommandPaletteDialog.show(context),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          // قناع قفل الشاشة برمز PIN عند الخمول أو القفل اليدوي
          if (pinState.isLocked) const PinLockOverlay(),
        ],
      ),
    );
  }
}

class _SideNav extends ConsumerWidget {
  const _SideNav();

  static const _items = [
    _NavItem(
        icon: Icons.dashboard_outlined,
        label: 'لوحة التحكم',
        path: AppRouter.dashboard),
    _NavItem(
        icon: Icons.people_outline,
        label: 'المتدربون',
        path: AppRouter.trainees),
    _NavItem(
        icon: Icons.school_outlined,
        label: 'الكورسات',
        path: AppRouter.courses),
    _NavItem(
        icon: Icons.calendar_month_outlined,
        label: 'الجلسات',
        path: AppRouter.sessions),
    _NavItem(
        icon: Icons.payment_outlined,
        label: 'المدفوعات',
        path: AppRouter.payments),
    _NavItem(
        icon: Icons.money_off_outlined,
        label: 'المصاريف',
        path: AppRouter.expenses),
    _NavItem(
        icon: Icons.biotech_outlined,
        label: 'المخبر',
        path: AppRouter.dentalLab),
    _NavItem(
        icon: Icons.bar_chart_outlined,
        label: 'التقارير',
        path: AppRouter.reports),
    _NavItem(
        icon: Icons.assignment_outlined,
        label: 'الاستبيانات',
        path: AppRouter.surveys),
    _NavItem(
        icon: Icons.calendar_today_outlined,
        label: 'التقويم',
        path: AppRouter.calendar),
    _NavItem(
        icon: Icons.manage_accounts_outlined,
        label: 'المستخدمون',
        path: AppRouter.users),
    _NavItem(
        icon: Icons.history_outlined,
        label: 'سجل التدقيق',
        path: AppRouter.audit),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final pinState = ref.watch(pinLockProvider);
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final role = JwtUtils.extractRole(token);
    final isAdmin = role == 'admin';

    return Container(
      width: 220,
      color: AppColors.darkGreen,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Image.asset('assets/images/Untitled-1.png', height: 160),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => CommandPaletteDialog.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, size: 16, color: AppColors.gold),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'بحث سريع أو أمر...',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      'Ctrl K',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: Colors.white24),
          const SizedBox(height: 4),

          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _items.where((item) {
                if (item.path == AppRouter.dentalLab && !isAdmin) return false;
                return true;
              }).map((item) {
                final isActive = location == item.path ||
                    location.startsWith("${item.path}/");
                return _NavTile(item: item, isActive: isActive);
              }).toList(),
            ),
          ),

          const Divider(color: Colors.white24),

          // قفل الشاشة اليدوي
          ListTile(
            dense: true,
            leading: const Icon(Icons.lock_outline, color: AppColors.gold, size: 20),
            title: const Text(
              'قفل الشاشة الآن',
              style: TextStyle(
                color: AppColors.gold,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () {
              if (!pinState.hasConfiguredPin) {
                showDialog(
                  context: context,
                  builder: (_) => const SetPinDialog(),
                );
              } else {
                ref.read(pinLockProvider.notifier).lockManually();
              }
            },
          ),

          // إعدادات رمز PIN
          ListTile(
            dense: true,
            leading: const Icon(Icons.password, color: Colors.white60, size: 20),
            title: Text(
              pinState.hasConfiguredPin ? 'تغيير رمز PIN' : 'تعيين رمز PIN',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'Cairo',
                fontSize: 12,
              ),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const SetPinDialog(),
              );
            },
          ),

          // Logout
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout, color: AppColors.error, size: 20),
            title: const Text(
              'تسجيل الخروج',
              style: TextStyle(
                color: AppColors.error,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;

  const _NavTile({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.gold.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: AppColors.gold.withValues(alpha: 0.4))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isActive ? AppColors.gold : Colors.white60,
          size: 22,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isActive ? AppColors.gold : Colors.white70,
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        onTap: () {
          if (!isActive) context.go(item.path);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.label, required this.path});
}
