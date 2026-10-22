import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/jwt_utils.dart';
import '../../backup/presentation/export_data_dialog.dart';
import '../../dental_lab/presentation/widgets/create_client_dialog.dart';
import '../../dental_lab/presentation/widgets/create_invoice_dialog.dart';
import '../../dental_lab/presentation/widgets/create_lab_expense_dialog.dart';
import '../../trainees/presentation/add_trainee_dialog.dart';
import '../domain/command_item.dart';

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => const CommandPaletteDialog(),
    );
  }

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  int _selectedIndex = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<CommandItem> _buildCommands(BuildContext context, bool isAdmin) {
    final commands = <CommandItem>[
      // -----------------------------------------------------------------------
      // ⚡ الإجراءات السريعة (Quick Actions)
      // -----------------------------------------------------------------------
      CommandItem(
        id: 'action_add_trainee',
        title: 'إضافة متدرب جديد',
        subtitle: 'تسجيل متدرب وتوليد أو كتابة كود المتدرب',
        keywords: ['متدرب', 'طالب', 'تسجيل', 'trainee', 'student', 'add'],
        icon: Icons.person_add_alt_1,
        category: CommandCategory.action,
        onSelect: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => AddTraineeDialog(onAdded: () {}),
          );
        },
      ),
      CommandItem(
        id: 'action_record_payment',
        title: 'تسجيل دفعة لمتدرب',
        subtitle: 'الانتقال لشاشة المدفوعات لتسجيل قسط جديد',
        keywords: ['دفعة', 'سداد', 'قبض', 'مالية', 'payment', 'pay'],
        icon: Icons.payment,
        category: CommandCategory.action,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.payments);
        },
      ),
      CommandItem(
        id: 'action_add_expense',
        title: 'تسجيل مصروف للمركز',
        subtitle: 'الانتقال لشاشة المصاريف لتسجيل نفقة جديدة',
        keywords: ['مصروف', 'نفقات', 'شراء', 'expense'],
        icon: Icons.money_off,
        category: CommandCategory.action,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.expenses);
        },
      ),
      CommandItem(
        id: 'action_new_lab_invoice',
        title: 'إصدار فاتورة مخبر جديدة',
        subtitle: 'فاتورة تعويضات وأعمال سنية لعيادة/طبيب',
        keywords: ['مخبر', 'فاتورة', 'تعويضات', 'زيركون', 'lab', 'invoice'],
        icon: Icons.biotech,
        category: CommandCategory.action,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => const CreateInvoiceDialog(),
          );
        },
      ),
      CommandItem(
        id: 'action_add_lab_client',
        title: 'إضافة عيادة أو طبيب للمخبر',
        subtitle: 'تسجيل عميل جديد في سجل المخبر',
        keywords: ['طبيب', 'عيادة', 'عميل', 'مخبر', 'client', 'doctor'],
        icon: Icons.medical_services,
        category: CommandCategory.action,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => const CreateClientDialog(),
          );
        },
      ),
      CommandItem(
        id: 'action_record_lab_expense',
        title: 'تسجيل مصروف خاص بالمخبر',
        subtitle: 'مواد مخبرية، خامات زيركون، صيانة معدات',
        keywords: ['مصروف مخبر', 'خامات', 'زيركون', 'lab expense'],
        icon: Icons.receipt_long,
        category: CommandCategory.action,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => const CreateLabExpenseDialog(),
          );
        },
      ),
      CommandItem(
        id: 'action_export_backup',
        title: 'تصدير نسخة احتياطية كاملة (JSON)',
        subtitle: 'تنزيل لقطة شاملة لكل بيانات النظام والمخبر',
        keywords: ['نسخة احتياطية', 'تصدير', 'باك اب', 'backup', 'export'],
        icon: Icons.download_for_offline,
        category: CommandCategory.action,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => const ExportDataDialog(),
          );
        },
      ),

      // -----------------------------------------------------------------------
      // 📍 التنقل السريع (Navigation)
      // -----------------------------------------------------------------------
      CommandItem(
        id: 'nav_dashboard',
        title: 'لوحة التحكم الرئيسية',
        subtitle: 'نظرة عامة على المؤشرات والمستحقات والتنبيهات',
        keywords: ['داشبورد', 'رئيسية', 'home', 'dashboard'],
        icon: Icons.dashboard_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.dashboard);
        },
      ),
      CommandItem(
        id: 'nav_trainees',
        title: 'سجل المتدربين',
        subtitle: 'عرض وبحث وتصفية المتدربين وملفاتهم الشخصية',
        keywords: ['متدربين', 'طلاب', 'أكواد', 'trainees', 'students'],
        icon: Icons.people_outline,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.trainees);
        },
      ),
      CommandItem(
        id: 'nav_courses',
        title: 'الدورات والكورسات',
        subtitle: 'إدارة الدورات التدريبية والمجموعات والمناهج',
        keywords: ['كورسات', 'دورات', 'مجموعات', 'courses', 'cohorts'],
        icon: Icons.school_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.courses);
        },
      ),
      CommandItem(
        id: 'nav_sessions',
        title: 'الجلسات والتحضير',
        subtitle: 'إدارة مواعيد الجلسات وتوليد رموز QR للحضور',
        keywords: ['جلسات', 'حضور', 'باركود', 'qr', 'sessions'],
        icon: Icons.calendar_month_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.sessions);
        },
      ),
      CommandItem(
        id: 'nav_payments',
        title: 'المدفوعات والمستحقات المالية',
        subtitle: 'سجل المقبوضات وتذكيرات الواتساب وأقساط المتدربين',
        keywords: ['دفعات', 'مقبوضات', 'أقساط', 'مالية', 'payments'],
        icon: Icons.payment_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.payments);
        },
      ),
      CommandItem(
        id: 'nav_expenses',
        title: 'المصاريف التشغيلية للمركز',
        subtitle: 'سجل النفقات والمصروفات والرواتب',
        keywords: ['مصاريف', 'نفقات', 'رواتب', 'expenses'],
        icon: Icons.money_off_outlined,
        category: CommandCategory.navigation,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.expenses);
        },
      ),
      CommandItem(
        id: 'nav_dental_lab',
        title: 'المخبر والتعويضات السنية',
        subtitle: 'فواتير الأطباء والعيادات ومصاريف وأرباح المخبر المستقلة',
        keywords: ['مخبر', 'أطباء', 'عيادات', 'تعويضات', 'زيركون', 'dental lab'],
        icon: Icons.biotech_outlined,
        category: CommandCategory.navigation,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.dentalLab);
        },
      ),
      CommandItem(
        id: 'nav_reports',
        title: 'التقارير والإحصائيات',
        subtitle: 'تقارير مالية، حضور وغياب، وأداء المجموعات',
        keywords: ['تقارير', 'إحصائيات', 'أرباح', 'reports', 'analytics'],
        icon: Icons.bar_chart_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.reports);
        },
      ),
      CommandItem(
        id: 'nav_surveys',
        title: 'الاستبيانات وتقييمات الجلسات',
        subtitle: 'نماذج الاستبيانات والنتائج وآراء المتدربين',
        keywords: ['استبيان', 'تقييم', 'surveys', 'feedback'],
        icon: Icons.assignment_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.surveys);
        },
      ),
      CommandItem(
        id: 'nav_calendar',
        title: 'التقويم الزمني والمواعيد',
        subtitle: 'عرض الجلسات والجدول الزمني على التقويم',
        keywords: ['تقويم', 'جدول', 'مواعيد', 'calendar', 'schedule'],
        icon: Icons.calendar_today_outlined,
        category: CommandCategory.navigation,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.calendar);
        },
      ),
      CommandItem(
        id: 'nav_users',
        title: 'المستخدمون والصلاحيات',
        subtitle: 'إدارة حسابات موظفي الاستقبال والمدراء',
        keywords: ['مستخدمين', 'موظفين', 'أدمن', 'users', 'roles'],
        icon: Icons.manage_accounts_outlined,
        category: CommandCategory.navigation,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.users);
        },
      ),
      CommandItem(
        id: 'nav_audit',
        title: 'سجل التدقيق والأمان',
        subtitle: 'تتبع كافة التعديلات والحركات الإدارية والمالية',
        keywords: ['تدقيق', 'سجل', 'أمان', 'audit', 'logs'],
        icon: Icons.history_outlined,
        category: CommandCategory.navigation,
        adminOnly: true,
        onSelect: () {
          Navigator.of(context).pop();
          context.go(AppRouter.audit);
        },
      ),
    ];

    return commands.where((cmd) {
      if (cmd.adminOnly && !isAdmin) return false;
      return true;
    }).toList();
  }

  void _handleKeyEvent(KeyEvent event, List<CommandItem> filtered) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (filtered.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % filtered.length;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (filtered.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + filtered.length) % filtered.length;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty && _selectedIndex < filtered.length) {
        filtered[_selectedIndex].onSelect();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final role = JwtUtils.extractRole(token);
    final isAdmin = role == 'admin';

    final allCommands = _buildCommands(context, isAdmin);
    final filtered = allCommands.where((cmd) => cmd.matches(_query)).toList();

    if (_selectedIndex >= filtered.length) {
      _selectedIndex = filtered.isEmpty ? 0 : filtered.length - 1;
    }

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (e) => _handleKeyEvent(e, filtered),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.only(top: 80, left: 16, right: 16),
        child: Container(
          width: 620,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.gold, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'اكتب أمراً، اسم شاشة، أو إجراءً سريعاً...',
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) {
                          setState(() {
                            _query = val;
                            _selectedIndex = 0;
                          });
                        },
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                            _selectedIndex = 0;
                          });
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: const Text(
                        'ESC للإغلاق',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),

              // Results List
              Flexible(
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, color: Colors.white38, size: 36),
                            SizedBox(height: 8),
                            Text(
                              'لا توجد أوامر أو شاشات مطابقة للبحث',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, idx) {
                          final cmd = filtered[idx];
                          final isSelected = idx == _selectedIndex;

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => cmd.onSelect(),
                            onHover: (hovering) {
                              if (hovering) setState(() => _selectedIndex = idx);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.gold.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected
                                    ? Border.all(color: AppColors.gold.withValues(alpha: 0.5))
                                    : Border.all(color: Colors.transparent),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: cmd.category == CommandCategory.action
                                          ? AppColors.gold.withValues(alpha: 0.15)
                                          : AppColors.darkGreen.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      cmd.icon,
                                      size: 18,
                                      color: cmd.category == CommandCategory.action
                                          ? AppColors.gold
                                          : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cmd.title,
                                          style: TextStyle(
                                            color: isSelected ? AppColors.gold : Colors.white,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          cmd.subtitle,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (cmd.category == CommandCategory.action)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.gold.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'إجراء',
                                        style: TextStyle(
                                          color: AppColors.gold,
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.subdirectory_arrow_left,
                                        color: AppColors.gold, size: 16),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Footer with navigation hints
              const Divider(color: AppColors.divider, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Wrap(
                      spacing: 12,
                      children: [
                        Text('↑↓ للتنقل', style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 11)),
                        Text('↵ للاختيار', style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 11)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.keyboard_command_key, color: AppColors.gold, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'لوحة الأوامر السريعة',
                          style: TextStyle(
                            color: AppColors.gold.withValues(alpha: 0.8),
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
