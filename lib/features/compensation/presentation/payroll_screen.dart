import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/widgets/keep_alive_wrapper.dart';
import '../../accounts/data/accounts_repository.dart';
import '../data/compensation_repository.dart';
import '../domain/compensation_models.dart';
import 'widgets/add_advance_dialog.dart';
import 'widgets/add_bonus_dialog.dart';
import 'widgets/add_staff_compensation_dialog.dart';
import 'widgets/add_staff_referral_dialog.dart';
import 'widgets/pay_payroll_dialog.dart';

class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = firstOfMonth(DateTime.now());
  bool _isGeneratingPayroll = false;
  bool _isApprovingPayroll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final staffCompAsync = ref.watch(staffCompensationProvider);
    final advancesAsync = ref.watch(advancesProvider);
    final bonusesAsync = ref.watch(bonusesProvider);
    final referralsAsync = ref.watch(referralsProvider);
    final payrollAsync = ref.watch(payrollProvider(_selectedMonth));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 16),

              // Tabs
              TabBar(
                controller: _tabController,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.gold,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.badge_outlined, size: 20),
                    text: 'رواتب وعمولات الكادر',
                  ),
                  Tab(
                    icon: Icon(Icons.money_off, size: 20),
                    text: 'السلف والمكافآت',
                  ),
                  Tab(
                    icon: Icon(Icons.person_add_alt_1_outlined, size: 20),
                    text: 'إحالات الطلاب (2.5%)',
                  ),
                  Tab(
                    icon: Icon(Icons.account_balance, size: 20),
                    text: 'مسير الرواتب الشهري',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Staff Compensation
                    KeepAliveWrapper(
                      child: staffCompAsync.when(
                        data: (staff) => _buildStaffCompensationTab(staff),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.gold),
                        ),
                        error: (e, _) => _buildErrorCard(
                          'تعذر تحميل رواتب الكادر: $e',
                          () => ref.invalidate(staffCompensationProvider),
                        ),
                      ),
                    ),

                    // Tab 2: Advances and Bonuses
                    KeepAliveWrapper(
                      child: _buildAdvancesAndBonusesTab(
                          advancesAsync, bonusesAsync),
                    ),

                    // Tab 3: Staff Referrals
                    KeepAliveWrapper(
                      child: referralsAsync.when(
                        data: (referrals) => _buildReferralsTab(referrals),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.gold),
                        ),
                        error: (e, _) => _buildErrorCard(
                          'تعذر تحميل إحالات الطلاب: $e',
                          () => ref.invalidate(referralsProvider),
                        ),
                      ),
                    ),

                    // Tab 4: Monthly Payroll Run
                    KeepAliveWrapper(
                      child: Column(
                        children: [
                          _buildPayrollMonthHeader(),
                          const SizedBox(height: 14),
                          Expanded(
                            child: payrollAsync.when(
                              data: (lines) => _buildPayrollRunTab(lines),
                              loading: () => const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.gold),
                              ),
                              error: (e, _) => _buildErrorCard(
                                'تعذر تحميل مسير الرواتب: $e',
                                () => ref
                                    .invalidate(payrollProvider(_selectedMonth)),
                              ),
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
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'رواتب ومستحقات الكادر',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'إدارة الرواتب الشهرية، عمولات الإحالة 2.5%، السلف والمكافآت، واعتماد وصرف مسير الرواتب',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: 'تحديث البيانات',
          icon: const Icon(Icons.refresh, color: AppColors.gold),
          onPressed: () {
            ref.invalidate(staffCompensationProvider);
            ref.invalidate(advancesProvider);
            ref.invalidate(bonusesProvider);
            ref.invalidate(referralsProvider);
            ref.invalidate(payrollProvider(_selectedMonth));
          },
        ),
      ],
    );
  }

  // ------------------------------------------------ Tab 1: Staff Compensation
  Widget _buildStaffCompensationTab(List<StaffCompensationRow> staff) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'إجمالي الكادر المحدد له رواتب: ${staff.length} موظف',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => AddStaffCompensationDialog.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'تحديد راتب موظف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: staff.isEmpty
              ? const Center(
                  child: Text(
                    'لم يتم تحديد رواتب للكادر بعد',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: staff.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = staff[index];
                    return _buildStaffRowCard(row);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStaffRowCard(StaffCompensationRow row) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkGreen.withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.badge, color: AppColors.gold, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      row.fullName,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        row.roleAr,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'عمولة الإحالة: ${row.commissionRatePercent.toStringAsFixed(1)}% • سارية من: ${AppFormatters.dateOnly.format(row.effectiveFrom)} إلى: ${row.effectiveTo == null ? "مستمرة" : AppFormatters.dateOnly.format(row.effectiveTo!)}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (row.notes != null && row.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'ملاحظات: ${row.notes}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${AppFormatters.amount.format(row.monthlySalary)} ${row.currency}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                tooltip: 'حذف الراتب المحدد',
                onPressed: () => _confirmDeleteStaffComp(row),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteStaffComp(StaffCompensationRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد حذف بيانات الراتب',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل تريد بالتأكيد حذف بيانات راتب الموظف "${row.fullName}"؟',
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(compensationRepositoryProvider)
            .deleteStaffCompensation(row.id);
        ref.invalidate(staffCompensationProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.friendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  // --------------------------------------------- Tab 2: Advances & Bonuses
  Widget _buildAdvancesAndBonusesTab(
    AsyncValue<List<StaffAdvance>> advancesAsync,
    AsyncValue<List<StaffBonus>> bonusesAsync,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => AddAdvanceDialog.show(context),
              icon: const Icon(Icons.money_off, size: 18),
              label: const Text(
                'صرف سلفة لموظف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => AddBonusDialog.show(context,
                  initialMonth: _selectedMonth),
              icon: const Icon(Icons.card_giftcard, size: 18),
              label: const Text(
                'منح مكافأة',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Advances List
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.money_off,
                              size: 18, color: AppColors.warning),
                          SizedBox(width: 8),
                          Text(
                            'سجل السلف المالية',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: advancesAsync.when(
                          data: (advances) => _buildAdvancesList(advances),
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.gold),
                          ),
                          error: (e, _) => Text(
                            'خطأ: $e',
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Bonuses List
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.card_giftcard,
                              size: 18, color: AppColors.gold),
                          SizedBox(width: 8),
                          Text(
                            'سجل المكافآت التقديرية',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: bonusesAsync.when(
                          data: (bonuses) => _buildBonusesList(bonuses),
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.gold),
                          ),
                          error: (e, _) => Text(
                            'خطأ: $e',
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancesList(List<StaffAdvance> advances) {
    if (advances.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد سلف مسجلة',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: advances.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final adv = advances[index];
        Color statusColor;
        String statusText;

        if (adv.isCancelled) {
          statusColor = AppColors.error;
          statusText = 'ملغاة';
        } else if (adv.isDeducted) {
          statusColor = AppColors.success;
          statusText = 'مخصومة من المسير';
        } else {
          statusColor = AppColors.warning;
          statusText = 'مفتوحة (قيد الخصم)';
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    adv.userName,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${AppFormatters.amount.format(adv.amount)} ${adv.currency}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'التاريخ: ${AppFormatters.dateOnly.format(adv.advancedAt)} • الحساب: ${adv.accountNameAr.isEmpty ? "خزينة" : adv.accountNameAr}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (adv.reason != null && adv.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'السبب: ${adv.reason}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (adv.isOpen) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _confirmCancelAdvance(adv),
                    icon: const Icon(Icons.cancel_outlined,
                        size: 14, color: AppColors.error),
                    label: const Text(
                      'إلغاء السلفة واسترداد الخزينة',
                      style: TextStyle(
                          color: AppColors.error,
                          fontFamily: 'Cairo',
                          fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmCancelAdvance(StaffAdvance adv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد إلغاء السلفة',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل تريد بالتأكيد إلغاء سلفة "${adv.userName}" بمبلغ ${AppFormatters.amount.format(adv.amount)} ${adv.currency}؟\nسيتم حذف حركة المصروف وإعادة المبلغ إلى رصيد الخزينة فوراً.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:
                  const Text('إلغاء السلفة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(compensationRepositoryProvider)
            .cancelAdvance(adv.id);
        ref.invalidate(advancesProvider);
        ref.invalidate(payrollProvider(_selectedMonth));
        ref.invalidate(accountBalancesProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.friendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildBonusesList(List<StaffBonus> bonuses) {
    if (bonuses.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد مكافآت مسجلة',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: bonuses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final b = bonuses[index];
        final isDeducted = b.isDeducted;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    b.userName,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${AppFormatters.amount.format(b.amount)} ${b.currency}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'شهر المكافأة: ${AppFormatters.monthYearAr.format(b.bonusMonth)}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDeducted
                          ? AppColors.success.withAlpha(20)
                          : AppColors.warning.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isDeducted ? 'أُدرجت بالمسير' : 'قيد الصرف',
                      style: TextStyle(
                        color:
                            isDeducted ? AppColors.success : AppColors.warning,
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'السبب: ${b.reason}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!isDeducted) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _confirmDeleteBonus(b),
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: AppColors.error),
                    label: const Text(
                      'حذف المكافأة',
                      style: TextStyle(
                          color: AppColors.error,
                          fontFamily: 'Cairo',
                          fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteBonus(StaffBonus b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد حذف المكافأة',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل تريد بالتأكيد حذف مكافأة "${b.userName}" لشهر ${AppFormatters.monthYearAr.format(b.bonusMonth)}؟',
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(compensationRepositoryProvider).deleteBonus(b.id);
        ref.invalidate(bonusesProvider);
        ref.invalidate(payrollProvider(_selectedMonth));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.friendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------- Tab 3: Referrals
  Widget _buildReferralsTab(List<StaffReferral> referrals) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'إجمالي إحالات الطلاب المسجلة: ${referrals.length} إحالة',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => AddStaffReferralDialog.show(context),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text(
                'تسجيل إحالة طالب',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: referrals.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد إحالات مسجلة للطلاب',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: referrals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = referrals[index];
                    return _buildReferralCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReferralCard(StaffReferral item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.school, color: AppColors.gold, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'المتدرب: ${item.traineeName}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.traineeCode,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'الموظف المحال إليه: ${item.staffName} • نسبة العمولة: ${item.commissionRatePercent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'تاريخ الإحالة: ${item.createdAt != null ? AppFormatters.dateOnly.format(item.createdAt!) : ""}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.error, size: 20),
            tooltip: 'إلغاء الإحالة',
            onPressed: () => _confirmDeleteReferral(item),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteReferral(StaffReferral item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد حذف الإحالة',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل تريد بالتأكيد إلغاء إحالة المتدرب "${item.traineeName}" للموظف "${item.staffName}"؟',
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(compensationRepositoryProvider)
            .deleteReferral(item.id);
        ref.invalidate(referralsProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.friendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  // ------------------------------------------------ Tab 4: Monthly Payroll Run
  Widget _buildPayrollMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.gold),
                tooltip: 'الشهر القادم',
                onPressed: _nextMonth,
              ),
              const SizedBox(width: 8),
              Text(
                AppFormatters.monthYearAr.format(_selectedMonth),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    size: 16, color: AppColors.gold),
                tooltip: 'الشهر السابق',
                onPressed: _prevMonth,
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _isGeneratingPayroll ? null : _generatePayrollRun,
            icon: _isGeneratingPayroll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.autorenew, size: 18),
            label: const Text(
              'توليد مسير الشهر',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePayrollRun() async {
    setState(() => _isGeneratingPayroll = true);
    try {
      await ref
          .read(compensationRepositoryProvider)
          .generatePayroll(_selectedMonth);
      ref.invalidate(payrollProvider(_selectedMonth));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم توليد مسير الرواتب بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPayroll = false);
    }
  }

  Widget _buildPayrollRunTab(List<PayrollLine> lines) {
    if (lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_late_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'لم يتم توليد مسير رواتب لشهر ${AppFormatters.monthYearAr.format(_selectedMonth)} بعد',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اضغط على زر "توليد مسير الشهر" بالأعلى لاحتساب رواتب الكادر والعمولات والسلف',
              style: TextStyle(
                color: Colors.white38,
                fontFamily: 'Cairo',
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final first = lines.first;
    final runId = first.runId;

    final currencies = <String>{for (final l in lines) l.currency}.toList()
      ..sort();
    final byCurrency = <String, List<PayrollLine>>{
      for (final c in currencies)
        c: lines.where((l) => l.currency == c).toList(),
    };

    final allSettled = lines.every((l) => l.expenseId != null);
    final anyPaid = lines.any((l) => l.expenseId != null);

    Color badgeColor;
    String badgeText;
    if (first.isPaid || allSettled) {
      badgeColor = AppColors.success;
      badgeText = 'مصروف ومقيد بالخزينة';
    } else if (first.isApproved) {
      badgeColor = AppColors.gold;
      badgeText = anyPaid ? 'معتمد — صرف جزئي' : 'معتمد (جاهز للصرف)';
    } else {
      badgeColor = AppColors.warning;
      badgeText = 'مسودة (قيد المراجعة)';
    }

    return Column(
      children: [
        // Action & Status Bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: badgeColor.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: badgeColor),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'عدد بنود المسير: ${lines.length} موظف — ${currencies.join(' / ')}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (first.isDraft)
                ElevatedButton.icon(
                  onPressed: _isApprovingPayroll
                      ? null
                      : () => _approvePayrollRun(runId),
                  icon: _isApprovingPayroll
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text(
                    'اعتماد المسير',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: ListView(
            children: [
              for (final entry in byCurrency.entries) ...[
                _buildPayrollCurrencyCard(runId, entry.key, entry.value),
                const SizedBox(height: 12),
              ],
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildPayrollLineCard(line),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPayrollCurrencyCard(
      String runId, String currency, List<PayrollLine> group) {
    final totalBase = group.fold<double>(0.0, (s, l) => s + l.baseSalary);
    final totalComm =
        group.fold<double>(0.0, (s, l) => s + l.referralCommission);
    final totalBonus =
        group.fold<double>(0.0, (s, l) => s + l.bonusAmount);
    final totalAdv =
        group.fold<double>(0.0, (s, l) => s + l.advanceDeduction);
    final totalNet = group.fold<double>(0.0, (s, l) => s + l.netAmount);

    // pay_payroll only settles lines matching the chosen account currency,
    // so each currency must be paid from its own account and totals.
    final unpaidPositive =
        group.where((l) => l.expenseId == null && l.netAmount > 0).toList();
    final unpaidZero =
        group.where((l) => l.expenseId == null && l.netAmount == 0).toList();
    final unpaidNet =
        unpaidPositive.fold<double>(0.0, (s, l) => s + l.netAmount);
    final paidCount = group.where((l) => l.expenseId != null).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.currency_exchange,
                  size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(
                'عملة $currency',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'مصروف: $paidCount من ${group.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _summaryBox('الأساسي الإجمالي', totalBase, currency,
                    AppColors.textPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox('عمولات الإحالة', totalComm, currency,
                    Colors.lightBlueAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox('المكافآت', totalBonus, currency,
                    AppColors.success),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox('السلف المخصومة', totalAdv, currency,
                    AppColors.error),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox('صافي المسير', totalNet, currency,
                    AppColors.gold),
              ),
            ],
          ),
          if (!group.first.isDraft) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (unpaidPositive.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () => PayPayrollDialog.show(
                      context,
                      runId: runId,
                      month: _selectedMonth,
                      lineCount: unpaidPositive.length,
                      netTotal: unpaidNet,
                      currency: currency,
                    ),
                    icon: const Icon(Icons.payments, size: 18),
                    label: Text(
                      'صرف ${AppFormatters.amount.format(unpaidNet)} $currency',
                      style: const TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  )
                else if (unpaidZero.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => PayPayrollDialog.show(
                      context,
                      runId: runId,
                      month: _selectedMonth,
                      lineCount: unpaidZero.length,
                      netTotal: 0,
                      currency: currency,
                    ),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text(
                      'إقفال البنود الصفرية ($currency)',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.gold),
                    ),
                  )
                else
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: AppColors.success),
                      SizedBox(width: 6),
                      Text(
                        'تم صرف جميع بنود هذه العملة',
                        style: TextStyle(
                          color: AppColors.success,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryBox(
      String title, double amount, String currency, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Cairo',
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${AppFormatters.amount.format(amount)} $currency',
            style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollLineCard(PayrollLine line) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.fullName,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  line.roleAr,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _columnValue(
                'الأساسي', line.baseSalary, line.currency),
          ),
          Expanded(
            flex: 2,
            child: _columnValue(
                'عمولة الإحالة', line.referralCommission, line.currency,
                color: Colors.lightBlueAccent),
          ),
          Expanded(
            flex: 2,
            child: _columnValue(
                'المكافآت', line.bonusAmount, line.currency,
                color: AppColors.success),
          ),
          Expanded(
            flex: 2,
            child: _columnValue(
                'خصم السلف', line.advanceDeduction, line.currency,
                color: AppColors.error),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'الصافي المستحق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${AppFormatters.amount.format(line.netAmount)} ${line.currency}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _columnValue(String label, double amount, String currency,
      {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          '${AppFormatters.amount.format(amount)} $currency',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Future<void> _approvePayrollRun(String runId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد اعتماد مسير الرواتب',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل أنت متأكد من اعتماد مسير رواتب شهر ${AppFormatters.monthYearAr.format(_selectedMonth)}؟\nبعد الاعتماد يمكن المتابعة لصرف الرواتب وقيدها في الخزينة.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              child: const Text('اعتماد', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _isApprovingPayroll = true);
      try {
        await ref
            .read(compensationRepositoryProvider)
            .approvePayroll(runId);
        ref.invalidate(payrollProvider(_selectedMonth));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.friendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isApprovingPayroll = false);
      }
    }
  }

  Widget _buildErrorCard(String error, VoidCallback onRetry) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
