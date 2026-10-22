import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/dental_lab_repository.dart';
import '../domain/dental_lab_models.dart';
import 'widgets/create_client_dialog.dart';
import 'widgets/create_invoice_dialog.dart';
import 'widgets/create_lab_expense_dialog.dart';
import 'widgets/record_lab_payment_dialog.dart';

class DentalLabScreen extends ConsumerStatefulWidget {
  const DentalLabScreen({super.key});

  @override
  ConsumerState<DentalLabScreen> createState() => _DentalLabScreenState();
}

class _DentalLabScreenState extends ConsumerState<DentalLabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Filters for invoices
  String _invoiceSearch = '';
  String _invoiceStatusFilter = 'all';
  String _invoiceCurrencyFilter = 'all';

  // Filters for clients
  String _clientSearch = '';

  // Filters for expenses
  String _expenseCategoryFilter = 'all';
  String _expenseCurrencyFilter = 'all';

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

  void _refreshAll() {
    ref.invalidate(labClientsProvider);
    ref.invalidate(labInvoicesProvider);
    ref.invalidate(labExpensesProvider);
    ref.invalidate(labFinancialSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            _buildTopBar(context),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.gold,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'فواتير وحالات التعويضات'),
                  Tab(icon: Icon(Icons.medical_services_outlined), text: 'سجل العيادات والأطباء'),
                  Tab(icon: Icon(Icons.money_off_csred_outlined), text: 'مصاريف المخبر'),
                  Tab(icon: Icon(Icons.analytics_outlined), text: 'التقرير المالي المنفصل'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInvoicesTab(context),
                  _buildClientsTab(context),
                  _buildExpensesTab(context),
                  _buildFinancialReportTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Header with Title and Global Action Buttons
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.biotech, color: AppColors.gold, size: 28),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المخبر — إدارة أعمال التعويضات السنية',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 22),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Text(
                  'نظام فواتير، عملاء، دفعات مقسطة، ومصاريف مستقلة تماماً عن المركز',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'فاتورة جديدة',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const CreateInvoiceDialog(),
                );
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.gold),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text(
                'طبيب/عيادة جديدة',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const CreateClientDialog(),
                );
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text(
                'تسجيل مصروف مخبر',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const CreateLabExpenseDialog(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.gold),
              tooltip: 'تحديث البيانات',
              onPressed: _refreshAll,
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Invoices and Cases
  // ---------------------------------------------------------------------------
  Widget _buildInvoicesTab(BuildContext context) {
    final invoicesAsync = ref.watch(labInvoicesProvider);

    return Column(
      children: [
        // Filter Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'بحث برقم الفاتورة، العميل، أو المريض...',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: AppColors.gold, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => _invoiceSearch = val.trim().toLowerCase()),
                ),
              ),
              DropdownButton<String>(
                value: _invoiceStatusFilter,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('جميع الحالات')),
                  DropdownMenuItem(value: 'unpaid', child: Text('غير مدفوعة')),
                  DropdownMenuItem(value: 'partial', child: Text('مدفوعة جزئياً')),
                  DropdownMenuItem(value: 'paid', child: Text('مسددة بالكامل')),
                  DropdownMenuItem(value: 'cancelled', child: Text('ملغاة')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _invoiceStatusFilter = val);
                },
              ),
              DropdownButton<String>(
                value: _invoiceCurrencyFilter,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('جميع العملات')),
                  DropdownMenuItem(value: 'SYP', child: Text('ل.س فقط')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار \$ فقط')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _invoiceCurrencyFilter = val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Invoices List
        Expanded(
          child: invoicesAsync.when(
            data: (invoices) {
              final filtered = invoices.where((inv) {
                if (_invoiceStatusFilter != 'all' && inv.status != _invoiceStatusFilter) return false;
                if (_invoiceCurrencyFilter != 'all' && inv.currency != _invoiceCurrencyFilter) return false;
                if (_invoiceSearch.isNotEmpty) {
                  final s = _invoiceSearch;
                  final matchNo = inv.invoiceNumber.toString().contains(s);
                  final matchClient = (inv.clientName ?? '').toLowerCase().contains(s);
                  final matchPatient = (inv.patientName ?? '').toLowerCase().contains(s);
                  if (!matchNo && !matchClient && !matchPatient) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'لا توجد فواتير مطابقة للبحث أو الفلتر',
                    style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 14),
                  ),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, index) => _buildInvoiceCard(ctx, filtered[index]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Text('خطأ في تحميل الفواتير: $e', style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(BuildContext context, LabInvoice invoice) {
    Color statusColor;
    switch (invoice.status) {
      case 'paid':
        statusColor = AppColors.success;
        break;
      case 'partial':
        statusColor = AppColors.warning;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      case 'unpaid':
      default:
        statusColor = AppColors.error;
        break;
    }

    final dateStr = DateFormat('yyyy/MM/dd').format(invoice.issueDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: invoice.isPaid ? AppColors.success.withValues(alpha: 0.3) : AppColors.divider,
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        iconColor: AppColors.gold,
        collapsedIconColor: Colors.white70,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: Text(
            '#INV-${invoice.invoiceNumber}',
            style: const TextStyle(
              color: AppColors.gold,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        title: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              invoice.clientName ?? 'عميل غير مسجل',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            if (invoice.patientName != null && invoice.patientName!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'المريض: ${invoice.patientName}',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 14,
            children: [
              Text('التاريخ: $dateStr', style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
              Text('الإجمالي: ${invoice.totalAmount.toStringAsFixed(0)} ${invoice.currencySymbol}',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
              Text('المسدد: ${invoice.paidAmount.toStringAsFixed(0)} ${invoice.currencySymbol}',
                  style: const TextStyle(color: AppColors.success, fontFamily: 'Cairo', fontSize: 12)),
              if (invoice.remainingAmount > 0)
                Text('المتبقي: ${invoice.remainingAmount.toStringAsFixed(0)} ${invoice.currencySymbol}',
                    style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
          ),
          child: Text(
            invoice.statusAr,
            style: TextStyle(
              color: statusColor,
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(color: AppColors.divider),
                const SizedBox(height: 8),

                // Items list header
                const Text(
                  'بنود وخدمات الفاتورة:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),

                // Items
                if (invoice.items.isEmpty)
                  const Text('لا توجد بنود مفصلة لهذه الفاتورة', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo'))
                else
                  ...invoice.items.map((item) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.serviceName,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ),
                          if (item.toothNumber != null && item.toothNumber!.isNotEmpty)
                            Expanded(
                              flex: 1,
                              child: Text('السن: ${item.toothNumber}', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                            ),
                          if (item.shade != null && item.shade!.isNotEmpty)
                            Expanded(
                              flex: 1,
                              child: Text('اللون: ${item.shade}', style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12)),
                            ),
                          Expanded(
                            flex: 1,
                            child: Text('${item.quantity} × ${item.unitPrice.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                          ),
                          Text(
                            '${item.totalPrice.toStringAsFixed(0)} ${invoice.currencySymbol}',
                            style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 12),

                // Payments History
                const Text(
                  'سجل الدفعات المسددة:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                if (invoice.payments.isEmpty)
                  const Text('لم يتم تسديد أي دفعة حتى الآن', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo'))
                else
                  ...invoice.payments.map((p) {
                    final pDate = DateFormat('yyyy/MM/dd - hh:mm a').format(p.paidAt);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                              const SizedBox(width: 8),
                              Text(pDate, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(p.paymentMethodAr, style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 11)),
                              ),
                              if (p.receiptNumber != null && p.receiptNumber!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text('وصل: #${p.receiptNumber}', style: const TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 11)),
                              ],
                            ],
                          ),
                          Text(
                            '${p.amount.toStringAsFixed(0)} ${invoice.currencySymbol}',
                            style: const TextStyle(color: AppColors.success, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 14),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!invoice.isCancelled && invoice.remainingAmount > 0)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.payment, size: 16),
                        label: const Text('تسجيل دفعة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => RecordLabPaymentDialog(invoice: invoice),
                          );
                        },
                      ),
                    const SizedBox(width: 8),
                    if (!invoice.isCancelled)
                      TextButton.icon(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                        label: const Text('إلغاء الفاتورة', style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              title: const Text('تأكيد إلغاء الفاتورة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                              content: Text(
                                'هل أنت متأكد من إلغاء الفاتورة #${invoice.invoiceNumber}؟',
                                style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('رجوع', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('تأكيد الإلغاء', style: TextStyle(fontFamily: 'Cairo')),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await ref.read(dentalLabRepositoryProvider).cancelInvoice(invoice.id);
                            ref.invalidate(labInvoicesProvider);
                            ref.invalidate(labFinancialSummaryProvider);
                          }
                        },
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

  // ---------------------------------------------------------------------------
  // Tab 2: Clients Directory
  // ---------------------------------------------------------------------------
  Widget _buildClientsTab(BuildContext context) {
    final clientsAsync = ref.watch(labClientsProvider);

    return Column(
      children: [
        // Filter & Search
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'بحث باسم الطبيب، العيادة، أو الهاتف...',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: AppColors.gold, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => _clientSearch = val.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة عميل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const CreateClientDialog(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: clientsAsync.when(
            data: (clients) {
              final filtered = clients.where((c) {
                if (_clientSearch.isNotEmpty) {
                  final s = _clientSearch;
                  final matchName = c.name.toLowerCase().contains(s);
                  final matchPhone = (c.phone ?? '').toLowerCase().contains(s);
                  final matchAddr = (c.clinicAddress ?? '').toLowerCase().contains(s);
                  if (!matchName && !matchPhone && !matchAddr) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('لا يوجد عملاء مطابقين للبحث', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final client = filtered[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                          child: const Icon(Icons.person, color: AppColors.gold),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 14,
                                children: [
                                  if (client.phone != null && client.phone!.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.phone, size: 14, color: AppColors.gold),
                                        const SizedBox(width: 4),
                                        Text(client.phone!, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                                      ],
                                    ),
                                  if (client.clinicAddress != null && client.clinicAddress!.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.white60),
                                        const SizedBox(width: 4),
                                        Text(client.clinicAddress!, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: AppColors.gold),
                          tooltip: 'تعديل البيانات',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => CreateClientDialog(initialClient: client),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Text('خطأ في تحميل العملاء: $e', style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Dental Lab Expenses
  // ---------------------------------------------------------------------------
  Widget _buildExpensesTab(BuildContext context) {
    final expensesAsync = ref.watch(labExpensesProvider);

    return Column(
      children: [
        // Filter & Add
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _expenseCategoryFilter,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('جميع تصنيفات المصاريف')),
                  DropdownMenuItem(value: 'materials', child: Text('مواد وخامات')),
                  DropdownMenuItem(value: 'equipment_maintenance', child: Text('صيانة أجهزة')),
                  DropdownMenuItem(value: 'utilities', child: Text('فواتير ومرافق')),
                  DropdownMenuItem(value: 'salaries', child: Text('رواتب')),
                  DropdownMenuItem(value: 'other', child: Text('أخرى')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _expenseCategoryFilter = val);
                },
              ),
              const SizedBox(width: 14),
              DropdownButton<String>(
                value: _expenseCurrencyFilter,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('جميع العملات')),
                  DropdownMenuItem(value: 'SYP', child: Text('ل.س فقط')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار \$ فقط')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _expenseCurrencyFilter = val);
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('تسجيل مصروف مخبر', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const CreateLabExpenseDialog(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: expensesAsync.when(
            data: (expenses) {
              final filtered = expenses.where((e) {
                if (_expenseCategoryFilter != 'all' && e.category != _expenseCategoryFilter) return false;
                if (_expenseCurrencyFilter != 'all' && e.currency != _expenseCurrencyFilter) return false;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('لا توجد مصاريف مطابقة', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final exp = filtered[index];
                  final dateStr = DateFormat('yyyy/MM/dd').format(exp.expenseDate);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_outlined, color: AppColors.gold, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exp.title,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 10,
                                children: [
                                  Text(exp.categoryAr, style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 11)),
                                  Text(dateStr, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 11)),
                                  Text('طريقة الدفع: ${exp.paymentMethodAr}', style: const TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${exp.amount.toStringAsFixed(0)} ${exp.currencySymbol}',
                          style: const TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                content: Text('حذف مصروف "${exp.title}"؟', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await ref.read(dentalLabRepositoryProvider).deleteExpense(exp.id);
                              ref.invalidate(labExpensesProvider);
                              ref.invalidate(labFinancialSummaryProvider);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Text('خطأ في تحميل المصاريف: $e', style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Independent Lab Financial Report
  // ---------------------------------------------------------------------------
  Widget _buildFinancialReportTab(BuildContext context) {
    final summaryAsync = ref.watch(labFinancialSummaryProvider);

    return summaryAsync.when(
      data: (summary) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notice banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.gold, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تقرير مالي مستقل بالكامل — خاص بنشاط وأعمال المخبر ولا يندمج مع تقارير مركز التدريب بناءً على قرارات الإدارة الصريحة.',
                        style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Currency 1: SYP (الليرة السورية)
              const Text(
                'العمليات والحسابات المالية بالليرة السورية (SYP)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildKpiCard('إجمالي الفواتير الصادرة', '${summary.billedSyp.toStringAsFixed(0)} ل.س', Icons.receipt_long, Colors.blue),
                  _buildKpiCard('إجمالي التحصيل الفعلي', '${summary.collectedSyp.toStringAsFixed(0)} ل.س', Icons.account_balance_wallet, AppColors.success),
                  _buildKpiCard('الديون والمستحقات المتبقية', '${summary.remainingSyp.toStringAsFixed(0)} ل.س', Icons.hourglass_top, AppColors.gold),
                  _buildKpiCard('مصاريف المخبر الكلية', '${summary.expensesSyp.toStringAsFixed(0)} ل.س', Icons.money_off, Colors.redAccent),
                  _buildKpiCard('صافي أرباح المخبر', '${summary.netProfitSyp.toStringAsFixed(0)} ل.س', Icons.trending_up, summary.netProfitSyp >= 0 ? AppColors.success : Colors.red),
                ],
              ),

              const SizedBox(height: 24),

              // Currency 2: USD (الدولار الأمريكي)
              const Text(
                'العمليات والحسابات المالية بالدولار الأمريكي (USD)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildKpiCard('إجمالي الفواتير الصادرة', '\$${summary.billedUsd.toStringAsFixed(0)}', Icons.receipt_long, Colors.blue),
                  _buildKpiCard('إجمالي التحصيل الفعلي', '\$${summary.collectedUsd.toStringAsFixed(0)}', Icons.account_balance_wallet, AppColors.success),
                  _buildKpiCard('الديون والمستحقات المتبقية', '\$${summary.remainingUsd.toStringAsFixed(0)}', Icons.hourglass_top, AppColors.gold),
                  _buildKpiCard('مصاريف المخبر الكلية', '\$${summary.expensesUsd.toStringAsFixed(0)}', Icons.money_off, Colors.redAccent),
                  _buildKpiCard('صافي أرباح المخبر', '\$${summary.netProfitUsd.toStringAsFixed(0)}', Icons.trending_up, summary.netProfitUsd >= 0 ? AppColors.success : Colors.red),
                ],
              ),

              const SizedBox(height: 24),

              // Status Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إحصائيات إنجاز وسداد الفواتير:',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatChip('إجمالي الفواتير', summary.totalInvoices.toString(), Colors.white),
                        _buildStatChip('مسددة بالكامل', summary.paidInvoices.toString(), AppColors.success),
                        _buildStatChip('مسددة جزئياً', summary.partialInvoices.toString(), AppColors.warning),
                        _buildStatChip('غير مدفوعة', summary.unpaidInvoices.toString(), AppColors.error),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
        child: Text('خطأ في تحميل التقرير: $e', style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String title, String count, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(color: color, fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
      ],
    );
  }
}
