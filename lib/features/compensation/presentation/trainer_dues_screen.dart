import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/widgets/keep_alive_wrapper.dart';
import '../data/compensation_repository.dart';
import '../domain/compensation_models.dart';
import 'widgets/add_trainer_agreement_dialog.dart';
import 'widgets/generate_dues_dialog.dart';
import 'widgets/lock_cohort_rate_dialog.dart';
import 'widgets/pay_trainer_due_dialog.dart';

class TrainerDuesScreen extends ConsumerStatefulWidget {
  const TrainerDuesScreen({super.key});

  @override
  ConsumerState<TrainerDuesScreen> createState() => _TrainerDuesScreenState();
}

class _TrainerDuesScreenState extends ConsumerState<TrainerDuesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = firstOfMonth(DateTime.now());
  String _cohortSearch = '';
  String _agreementSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    final cohortRatesAsync = ref.watch(cohortRatesProvider);
    final agreementsAsync = ref.watch(agreementsProvider);
    final duesAsync = ref.watch(trainerDuesProvider(_selectedMonth));

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

              // Tabs Bar
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
                    icon: Icon(Icons.lock_clock_outlined, size: 20),
                    text: 'نسب الدفعات (Snapshots)',
                  ),
                  Tab(
                    icon: Icon(Icons.handshake_outlined, size: 20),
                    text: 'اتفاقيات المدربين',
                  ),
                  Tab(
                    icon: Icon(Icons.payments_outlined, size: 20),
                    text: 'مستحقات وصرف الأتعاب',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Cohort Snapshots
                    KeepAliveWrapper(
                      child: cohortRatesAsync.when(
                        data: (cohorts) => _buildCohortSnapshotsTab(cohorts),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.gold),
                        ),
                        error: (e, _) => _buildErrorCard(
                          'تعذر تحميل نسب الدفعات: $e',
                          () => ref.invalidate(cohortRatesProvider),
                        ),
                      ),
                    ),

                    // Tab 2: Trainer Agreements
                    KeepAliveWrapper(
                      child: agreementsAsync.when(
                        data: (agreements) =>
                            _buildAgreementsTab(agreements),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.gold),
                        ),
                        error: (e, _) => _buildErrorCard(
                          'تعذر تحميل اتفاقيات المدربين: $e',
                          () => ref.invalidate(agreementsProvider),
                        ),
                      ),
                    ),

                    // Tab 3: Monthly Dues & Payouts
                    KeepAliveWrapper(
                      child: Column(
                        children: [
                          _buildMonthNavigationBar(cohortRatesAsync),
                          const SizedBox(height: 14),
                          Expanded(
                            child: duesAsync.when(
                              data: (dues) => _buildDuesTab(dues),
                              loading: () => const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.gold),
                              ),
                              error: (e, _) => _buildErrorCard(
                                'تعذر تحميل مستحقات الشهر: $e',
                                () => ref.invalidate(
                                    trainerDuesProvider(_selectedMonth)),
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
              'أتعاب المدربين ونسب الدفعات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'إدارة اتفاقيات المدربين، تجميد نسب الدفعات، واحتساب وصرف الأتعاب من مقبوضات الطلاب',
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
            ref.invalidate(cohortRatesProvider);
            ref.invalidate(agreementsProvider);
            ref.invalidate(trainerDuesProvider(_selectedMonth));
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------- Tab 1 Snapshots
  Widget _buildCohortSnapshotsTab(List<CohortTrainerRate> cohorts) {
    final needle = _cohortSearch.trim().toLowerCase();
    final filtered = cohorts.where((c) {
      if (needle.isEmpty) return true;
      return c.courseName.toLowerCase().contains(needle) ||
          c.cohortName.toLowerCase().contains(needle) ||
          c.trainerName.toLowerCase().contains(needle);
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(
                    color: AppColors.textPrimary, fontFamily: 'Cairo', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الكورس أو الدفعة أو المدرب...',
                  hintStyle: const TextStyle(
                      color: Colors.white30, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.gold, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
                onChanged: (val) => setState(() => _cohortSearch = val),
              ),
            ),
            const SizedBox(width: 14),
            ElevatedButton.icon(
              onPressed: () => LockCohortRateDialog.show(
                context,
                availableCohorts: cohorts,
              ),
              icon: const Icon(Icons.lock_clock_outlined, size: 18),
              label: const Text(
                'تثبيت نسبة لدفعة',
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
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد دفعات تدريبية مطابقة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildCohortRateCard(item, cohorts);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCohortRateCard(
      CohortTrainerRate item, List<CohortTrainerRate> allCohorts) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isFrozen
              ? AppColors.darkGreen.withAlpha(120)
              : AppColors.warning.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.isFrozen
                  ? AppColors.darkGreen.withAlpha(40)
                  : AppColors.warning.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.isFrozen ? Icons.lock : Icons.lock_open,
              color: item.isFrozen ? AppColors.gold : AppColors.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.courseName,
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
                        item.cohortName,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'المدرب: ${item.trainerName.isEmpty ? "غير محدد" : item.trainerName} • تاريخ البدء: ${item.startsAt != null ? AppFormatters.dateOnly.format(item.startsAt!) : "غير محدد"}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (item.rateLockedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'تم التجميد بتاريخ: ${AppFormatters.dateOnly.format(item.rateLockedAt!)}',
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
              if (item.isFrozen) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Text(
                    'مقفل (${item.ratePercent!.toStringAsFixed(1)}%)',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () => LockCohortRateDialog.show(
                    context,
                    presetCohort: item,
                    availableCohorts: allCohorts,
                  ),
                  icon: const Icon(Icons.lock_clock, size: 16),
                  label: const Text(
                    'تثبيت النسبة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- Tab 2 Agreements
  Widget _buildAgreementsTab(List<TrainerAgreement> agreements) {
    final needle = _agreementSearch.trim().toLowerCase();
    final filtered = agreements.where((a) {
      if (needle.isEmpty) return true;
      return a.trainerName.toLowerCase().contains(needle) ||
          a.courseName.toLowerCase().contains(needle) ||
          (a.notes?.toLowerCase().contains(needle) ?? false);
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(
                    color: AppColors.textPrimary, fontFamily: 'Cairo', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'بحث باسم المدرب، الكورس، أو الملاحظات...',
                  hintStyle: const TextStyle(
                      color: Colors.white30, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.gold, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
                onChanged: (val) => setState(() => _agreementSearch = val),
              ),
            ),
            const SizedBox(width: 14),
            ElevatedButton.icon(
              onPressed: () => AddTrainerAgreementDialog.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'إضافة اتفاقية مدرب',
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
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد اتفاقيات مسجلة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildAgreementCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAgreementCard(TrainerAgreement item) {
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
            child: const Icon(Icons.person, color: AppColors.gold, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.trainerName,
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
                        item.courseName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'سارية من: ${AppFormatters.dateOnly.format(item.effectiveFrom)} إلى: ${item.effectiveTo == null ? "مستمرة" : AppFormatters.dateOnly.format(item.effectiveTo!)}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'ملاحظات: ${item.notes}',
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
                '${item.ratePercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                tooltip: 'حذف الاتفاقية',
                onPressed: () => _confirmDeleteAgreement(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAgreement(TrainerAgreement item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('تأكيد حذف الاتفاقية',
              style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
          content: Text(
            'هل أنت متأكد من حذف اتفاقية المدرب "${item.trainerName}" لكورس "${item.courseName}"؟',
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
            .deleteAgreement(item.id);
        ref.invalidate(agreementsProvider);
        ref.invalidate(cohortRatesProvider);
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

  // ------------------------------------------------------------- Tab 3 Dues
  Widget _buildMonthNavigationBar(
      AsyncValue<List<CohortTrainerRate>> cohortRatesAsync) {
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
          cohortRatesAsync.maybeWhen(
            data: (cohorts) => ElevatedButton.icon(
              onPressed: () => GenerateDuesDialog.show(
                context,
                initialMonth: _selectedMonth,
                cohorts: cohorts,
              ),
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text(
                'توليد مستحقات دفعة للشهر',
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
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildDuesTab(List<TrainerDue> dues) {
    if (dues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'لا توجد مستحقات مسجلة لشهر ${AppFormatters.monthYearAr.format(_selectedMonth)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اضغط على زر "توليد مستحقات دفعة للشهر" لحساب أتعاب أي دفعة من مقبوضاتها',
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

    final totalDue =
        dues.fold<double>(0.0, (sum, d) => sum + d.calculatedDue);
    final totalPaid =
        dues.fold<double>(0.0, (sum, d) => sum + d.paidTotal);
    final totalRemaining =
        dues.fold<double>(0.0, (sum, d) => sum + d.remaining);

    return Column(
      children: [
        // Dues summary banner
        Row(
          children: [
            Expanded(
              child: _buildDueSummaryItem(
                'إجمالي المستحق المحسوب',
                totalDue,
                AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDueSummaryItem(
                'إجمالي المصروف',
                totalPaid,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDueSummaryItem(
                'المتبقي للصرف',
                totalRemaining,
                AppColors.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            itemCount: dues.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final due = dues[index];
              return _buildDueCard(due);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDueSummaryItem(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
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
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatters.amount.format(amount),
            style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueCard(TrainerDue due) {
    Color statusColor;
    String statusText;

    if (due.isPaid) {
      statusColor = AppColors.success;
      statusText = 'مصروف بالكامل';
    } else if (due.isPartiallyPaid) {
      statusColor = AppColors.warning;
      statusText = 'مصروف جزئياً';
    } else {
      statusColor = AppColors.error;
      statusText = 'غير مصروف';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          due.trainerName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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
                            '${due.courseName} - ${due.cohortName}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'مقبوضات الدفعة: ${AppFormatters.amount.format(due.totalCollected)} ${due.currency} • النسبة المطبقة: ${due.appliedRatePercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _statItem('المستحق:',
                      '${AppFormatters.amount.format(due.calculatedDue)} ${due.currency}'),
                  const SizedBox(width: 20),
                  _statItem('المصروف:',
                      '${AppFormatters.amount.format(due.paidTotal)} ${due.currency}'),
                  const SizedBox(width: 20),
                  _statItem('المتبقي:',
                      '${AppFormatters.amount.format(due.remaining)} ${due.currency}',
                      color: AppColors.gold),
                ],
              ),
              if (due.remaining > 0)
                ElevatedButton.icon(
                  onPressed: () =>
                      PayTrainerDueDialog.show(context, due: due),
                  icon: const Icon(Icons.payments, size: 16),
                  label: const Text(
                    'صرف أتعاب',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, {Color? color}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: 13,
          ),
        ),
      ],
    );
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
