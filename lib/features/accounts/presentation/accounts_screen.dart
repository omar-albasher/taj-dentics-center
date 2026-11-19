import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/widgets/keep_alive_wrapper.dart';
import '../data/accounts_repository.dart';
import '../domain/account_models.dart';
import 'widgets/transfer_dialog.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _amountFormat = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openTransferDialog(List<FinancialAccountBalance> accounts,
      {String? fromAccountId}) {
    TransferDialog.show(
      context,
      accounts: accounts,
      initialFromAccountId: fromAccountId,
    );
  }

  void _filterByAccountAndGoToLedger(String accountId) {
    ref.read(accountFilterParamsProvider.notifier).updateParams(
          (p) => p.copyWith(
            accountId: accountId,
            page: 1,
          ),
        );
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(accountBalancesProvider);
    final ledgerAsync = ref.watch(accountLedgerProvider);
    final filterParams = ref.watch(accountFilterParamsProvider);

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
              _buildHeader(balancesAsync),
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
                    icon: Icon(Icons.account_balance_wallet_outlined, size: 20),
                    text: 'أرصدة الخزينة والحسابات',
                  ),
                  Tab(
                    icon: Icon(Icons.receipt_long_outlined, size: 20),
                    text: 'سجل دفتر الحركات (Ledger)',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Balances (Cards)
                    KeepAliveWrapper(
                      child: balancesAsync.when(
                        data: (accounts) =>
                            _buildBalancesTab(accounts, balancesAsync),
                        loading: () => const Center(
                          child:
                              CircularProgressIndicator(color: AppColors.gold),
                        ),
                        error: (e, _) => _buildErrorCard(
                          'تعذر تحميل أرصدة الخزينة والحسابات: $e',
                          () => ref.invalidate(accountBalancesProvider),
                        ),
                      ),
                    ),

                    // Tab 2: Custody Ledger (Table)
                    KeepAliveWrapper(
                      child: Column(
                        children: [
                          balancesAsync.maybeWhen(
                            data: (accounts) =>
                                _buildFilterBar(accounts, filterParams),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: ledgerAsync.when(
                              data: (result) =>
                                  _buildLedgerSection(result, filterParams),
                              loading: () => const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.gold),
                              ),
                              error: (e, _) => _buildErrorCard(
                                'تعذر تحميل دفتر الحركات: $e',
                                () => ref.invalidate(accountLedgerProvider),
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

  Widget _buildHeader(AsyncValue<List<FinancialAccountBalance>> balancesAsync) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الخزينة والحسابات المالية',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'أرصدة الصناديق والمصارف والمحافظ وسجل الحركات المحاسبية الموثقة (Custody Ledger)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
              tooltip: 'تحديث البيانات',
              onPressed: () {
                ref.invalidate(accountBalancesProvider);
                ref.invalidate(accountLedgerProvider);
              },
            ),
            const SizedBox(width: 8),
            balancesAsync.maybeWhen(
              data: (accounts) => ElevatedButton.icon(
                onPressed: () => _openTransferDialog(accounts),
                icon: const Icon(Icons.swap_horiz, size: 20),
                label: const Text(
                  'تحويل مالي داخلي',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBalancesTab(
    List<FinancialAccountBalance> accounts,
    AsyncValue<List<FinancialAccountBalance>> balancesAsync,
  ) {
    final sypTotal = accounts
        .where((a) => a.currency == 'SYP')
        .fold<double>(0.0, (sum, a) => sum + a.balance);
    final usdTotal = accounts
        .where((a) => a.currency == 'USD')
        .fold<double>(0.0, (sum, a) => sum + a.balance);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Liquidity Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'إجمالي السيولة النقدية (ليرة سورية)',
                  amount: sypTotal,
                  currency: 'SYP',
                  icon: Icons.account_balance_wallet,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: 'إجمالي السيولة النقدية (دولار أمريكي)',
                  amount: usdTotal,
                  currency: 'USD',
                  icon: Icons.monetization_on_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Subtitle
          const Text(
            'تفاصيل الحسابات والصناديق الستة:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // The 6 Account Cards
          _buildAccountsGrid(accounts),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required String currency,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(60), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _amountFormat.format(amount),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currency,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsGrid(List<FinancialAccountBalance> accounts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 750) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1150) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.15,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: accounts.length,
          itemBuilder: (context, index) {
            final acc = accounts[index];
            return _buildAccountCard(acc, accounts);
          },
        );
      },
    );
  }

  Widget _buildAccountCard(
    FinancialAccountBalance acc,
    List<FinancialAccountBalance> allAccounts,
  ) {
    final isUsd = acc.currency == 'USD';
    final isPositive = acc.balance >= 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUsd
              ? Colors.blue.withAlpha(50)
              : AppColors.gold.withAlpha(50),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Row: Name + Badges + Quick Actions
          Row(
            children: [
              Icon(acc.typeIcon,
                  color: isUsd ? Colors.lightBlueAccent : AppColors.gold,
                  size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  acc.nameAr,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isUsd
                      ? Colors.blue.withAlpha(40)
                      : AppColors.gold.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  acc.currency,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUsd ? Colors.lightBlueAccent : AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  acc.accountTypeLabel,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          // Middle: Current Balance
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _amountFormat.format(acc.balance),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColors.textPrimary : AppColors.error,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                acc.currency,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              // Quick action buttons
              IconButton(
                icon: const Icon(Icons.receipt_long, size: 18),
                tooltip: 'عرض حركات هذا الحساب في الدفتر',
                color: AppColors.gold,
                onPressed: () =>
                    _filterByAccountAndGoToLedger(acc.accountId),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 18),
                tooltip: 'تحويل من هذا الحساب',
                color: AppColors.textSecondary,
                onPressed: () => _openTransferDialog(
                  allAccounts,
                  fromAccountId: acc.accountId,
                ),
              ),
            ],
          ),

          // Bottom: Inflow / Outflow / Tx count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'وارد: +${_amountFormat.format(acc.totalInflow)}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.success,
                ),
              ),
              Text(
                'صادر: -${_amountFormat.format(acc.totalOutflow)}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.error,
                ),
              ),
              Text(
                '${acc.transactionCount} حركة',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
    List<FinancialAccountBalance> accounts,
    AccountFilterParams filterParams,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Filter by Account
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('filter_acc_${filterParams.accountId}'),
              initialValue: filterParams.accountId ?? 'الكل',
              isExpanded: true,
              dropdownColor: AppColors.cardBg,
              decoration: const InputDecoration(
                labelText: 'تصفية حسب الحساب',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'الكل',
                  child: Text('كافة الحسابات (الكل)',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                ...accounts.map(
                  (a) => DropdownMenuItem(
                    value: a.accountId,
                    child: Text(
                      '${a.nameAr} (${a.currency})',
                      style:
                          const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                ref.read(accountFilterParamsProvider.notifier).updateParams(
                      (p) => p.copyWith(
                        accountId: val == 'الكل' ? null : val,
                        clearAccountId: val == 'الكل',
                        page: 1,
                      ),
                    );
              },
            ),
          ),

          // Filter by Source Type
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: ValueKey('filter_source_${filterParams.sourceType}'),
              initialValue: filterParams.sourceType ?? 'الكل',
              isExpanded: true,
              dropdownColor: AppColors.cardBg,
              decoration: const InputDecoration(
                labelText: 'نوع الحركة المصدرية',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'الكل',
                  child: Text('كافة الحركات (الكل)',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'payment',
                  child: Text('دفعة متدرب',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'expense',
                  child: Text('مصروف تشغيلي',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'refund',
                  child: Text('استرداد دفعة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'transfer',
                  child: Text('تحويل داخلي',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'adjustment',
                  child: Text('قيد تسوية',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                ref.read(accountFilterParamsProvider.notifier).updateParams(
                      (p) => p.copyWith(
                        sourceType: val == 'الكل' ? null : val,
                        clearSourceType: val == 'الكل',
                        page: 1,
                      ),
                    );
              },
            ),
          ),

          // Date Range Filter Button
          OutlinedButton.icon(
            onPressed: () => _pickDateRange(filterParams),
            icon: const Icon(Icons.date_range,
                size: 18, color: AppColors.gold),
            label: Text(
              filterParams.fromDate != null && filterParams.toDate != null
                  ? '${AppFormatters.dateOnly.format(filterParams.fromDate!)} - ${AppFormatters.dateOnly.format(filterParams.toDate!)}'
                  : 'الفترة الزمنية',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: const BorderSide(color: AppColors.divider),
            ),
          ),

          // Clear Filters
          if (filterParams.accountId != null ||
              filterParams.sourceType != null ||
              filterParams.fromDate != null)
            TextButton.icon(
              onPressed: () {
                ref.read(accountFilterParamsProvider.notifier).updateParams(
                      (p) => const AccountFilterParams(),
                    );
              },
              icon: const Icon(Icons.clear, size: 16, color: AppColors.error),
              label: const Text(
                'إعادة ضبط',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(AccountFilterParams currentParams) async {
    DateTimeRange? initialRange;
    if (currentParams.fromDate != null && currentParams.toDate != null) {
      initialRange = DateTimeRange(
        start: currentParams.fromDate!,
        end: currentParams.toDate!,
      );
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.cardBg,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(accountFilterParamsProvider.notifier).updateParams(
            (p) => p.copyWith(
              fromDate: picked.start,
              toDate: picked.end,
              page: 1,
            ),
          );
    }
  }

  Widget _buildLedgerSection(
    AccountLedgerQueryResult result,
    AccountFilterParams filterParams,
  ) {
    if (result.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: AppColors.textSecondary.withAlpha(100)),
            const SizedBox(height: 12),
            const Text(
              'لا توجد حركات مالية مطابقة للفلاتر المحددة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table Container
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(AppColors.surface),
                    horizontalMargin: 16,
                    columnSpacing: 24,
                    columns: const [
                      DataColumn(
                        label: Text('التاريخ والوقت',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('الحساب',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('نوع الحركة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('المبلغ والاتجاه',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('طريقة الاشتقاق',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('الموظف المنفذ',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                      DataColumn(
                        label: Text('ملاحظات / بيان',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold)),
                      ),
                    ],
                    rows: result.entries.map((tx) {
                      final isInflow = tx.direction == 'inflow';
                      final isUsd = tx.currency == 'USD';

                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              AppFormatters.dateTime
                                  .format(tx.occurredAt.toLocal()),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 12),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tx.accountNameAr,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isUsd
                                        ? Colors.blue.withAlpha(30)
                                        : AppColors.gold.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tx.currency,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: isUsd
                                          ? Colors.lightBlueAccent
                                          : AppColors.gold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tx.sourceTypeLabel,
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 11),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${isInflow ? "+" : "-"}${_amountFormat.format(tx.amount)} ${tx.currency}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isInflow
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              tx.derivationLabel,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              tx.performedByName ?? 'النظام',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              tx.notes ?? '—',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Pagination Bar
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'إجمالي الحركات: ${result.totalCount} (صفحة ${result.currentPage} من ${result.totalPages.clamp(1, 999999)})',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'الصفحة السابقة',
                  onPressed: result.hasPrevPage
                      ? () {
                          ref
                              .read(accountFilterParamsProvider.notifier)
                              .updateParams(
                                (p) => p.copyWith(page: p.page - 1),
                              );
                        }
                      : null,
                ),
                Text(
                  '${result.currentPage}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'الصفحة التالية',
                  onPressed: result.hasNextPage
                      ? () {
                          ref
                              .read(accountFilterParamsProvider.notifier)
                              .updateParams(
                                (p) => p.copyWith(page: p.page + 1),
                              );
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard(String error, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.error,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}
