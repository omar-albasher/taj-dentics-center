import 'package:admin_dashboard/core/constants/app_colors.dart';
import 'package:admin_dashboard/core/router/app_router.dart';
import 'package:admin_dashboard/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
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
            ),
    );
  }
}

class _SideNav extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      width: 220,
      color: AppColors.darkGreen,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Image.asset('assets/images/Untitled-1.png', height: 230),
          ),

          const Divider(color: Colors.white24),
          const SizedBox(height: 8),

          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _items.map((item) {
                final isActive = location == item.path || location.startsWith("${item.path}/");
                return _NavTile(item: item, isActive: isActive);
              }).toList(),
            ),
          ),

          const Divider(color: Colors.white24),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.gold),
            title: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo'),
            ),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
          const SizedBox(height: 16),
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
        color: isActive ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
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
        onTap: () { if (!isActive) context.go(item.path); },
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

