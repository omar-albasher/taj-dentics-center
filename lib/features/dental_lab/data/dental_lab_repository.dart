import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/dental_lab_models.dart';

final dentalLabRepositoryProvider = Provider<DentalLabRepository>((ref) {
  return DentalLabRepository();
});

class DentalLabRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Clients (عيادات وأطباء الأسنان)
  // ---------------------------------------------------------------------------
  Future<List<LabClient>> getClients({bool activeOnly = false}) async {
    var query = _client.from('lab_clients').select();
    if (activeOnly) {
      query = query.eq('is_active', true);
    }
    final response = await query.order('name', ascending: true);
    return (response as List).map((e) => LabClient.fromMap(e)).toList();
  }

  Future<LabClient> createClient({
    required String name,
    String? phone,
    String? clinicAddress,
    String? notes,
  }) async {
    final response = await _client.from('lab_clients').insert({
      'name': name.trim(),
      'phone': phone?.trim(),
      'clinic_address': clinicAddress?.trim(),
      'notes': notes?.trim(),
      'is_active': true,
    }).select().single();
    return LabClient.fromMap(response);
  }

  Future<void> updateClient({
    required String id,
    required String name,
    String? phone,
    String? clinicAddress,
    String? notes,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'name': name.trim(),
      'phone': phone?.trim(),
      'clinic_address': clinicAddress?.trim(),
      'notes': notes?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (isActive != null) {
      updates['is_active'] = isActive;
    }
    await _client.from('lab_clients').update(updates).eq('id', id);
  }

  // ---------------------------------------------------------------------------
  // Invoices (فواتير المخبر)
  // ---------------------------------------------------------------------------
  Future<List<LabInvoice>> getInvoices({
    String? clientId,
    String? status,
    String? currency,
  }) async {
    var query = _client.from('lab_invoices').select('''
      id, invoice_number, client_id, patient_name, status, currency,
      subtotal, discount, total_amount, paid_amount, issue_date, due_date,
      notes, created_by, created_at, updated_at,
      lab_clients(name, phone),
      lab_invoice_items(*),
      lab_payments(*)
    ''');

    if (clientId != null && clientId.isNotEmpty) {
      query = query.eq('client_id', clientId);
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      query = query.eq('status', status);
    }
    if (currency != null && currency.isNotEmpty && currency != 'all') {
      query = query.eq('currency', currency);
    }

    final response = await query.order('created_at', ascending: false);
    return (response as List).map((e) => LabInvoice.fromMap(e)).toList();
  }

  Future<LabInvoice> getInvoiceById(String id) async {
    final response = await _client.from('lab_invoices').select('''
      id, invoice_number, client_id, patient_name, status, currency,
      subtotal, discount, total_amount, paid_amount, issue_date, due_date,
      notes, created_by, created_at, updated_at,
      lab_clients(name, phone),
      lab_invoice_items(*),
      lab_payments(*)
    ''').eq('id', id).single();
    return LabInvoice.fromMap(response);
  }

  Future<LabInvoice> createInvoiceWithItems({
    required String clientId,
    String? patientName,
    String currency = 'SYP',
    double discount = 0.0,
    DateTime? issueDate,
    DateTime? dueDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    final date = issueDate ?? DateTime.now();

    // 1. Insert invoice header
    final invoiceRes = await _client.from('lab_invoices').insert({
      'client_id': clientId,
      'patient_name': patientName?.trim(),
      'currency': currency,
      'discount': discount,
      'issue_date': date.toIso8601String().split('T')[0],
      if (dueDate != null) 'due_date': dueDate.toIso8601String().split('T')[0],
      'notes': notes?.trim(),
      'created_by': currentUserId,
    }).select().single();

    final invoiceId = invoiceRes['id'].toString();

    // 2. Insert items (triggers will calculate item totals, subtotal, and invoice total)
    if (items.isNotEmpty) {
      final itemsToInsert = items.map((item) {
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        return {
          'invoice_id': invoiceId,
          'service_name': item['service_name'],
          if (item['tooth_number'] != null) 'tooth_number': item['tooth_number'],
          if (item['shade'] != null) 'shade': item['shade'],
          'quantity': qty,
          'unit_price': unitPrice,
          if (item['notes'] != null) 'notes': item['notes'],
        };
      }).toList();

      await _client.from('lab_invoice_items').insert(itemsToInsert);
    }

    return getInvoiceById(invoiceId);
  }

  Future<void> cancelInvoice(String id) async {
    await _client.from('lab_invoices').update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // ---------------------------------------------------------------------------
  // Payments (تسجيل دفعات المخبر)
  // ---------------------------------------------------------------------------
  Future<void> recordPayment({
    required String invoiceId,
    required double amount,
    String currency = 'SYP',
    DateTime? paidAt,
    required String method,
    String? receiptNumber,
    String? externalReference,
    String? notes,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    await _client.from('lab_payments').insert({
      'invoice_id': invoiceId,
      'amount': amount,
      'currency': currency,
      'paid_at': (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
      'method': method,
      'receipt_number': receiptNumber?.trim(),
      'external_reference': externalReference?.trim(),
      'notes': notes?.trim(),
      'performed_by': currentUserId,
    });
  }

  // ---------------------------------------------------------------------------
  // Lab Expenses (مصاريف المخبر)
  // ---------------------------------------------------------------------------
  Future<List<LabExpense>> getExpenses({
    String? category,
    String? currency,
  }) async {
    var query = _client.from('lab_expenses').select();
    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }
    if (currency != null && currency.isNotEmpty && currency != 'all') {
      query = query.eq('currency', currency);
    }

    final response = await query.order('expense_date', ascending: false);
    return (response as List).map((e) => LabExpense.fromMap(e)).toList();
  }

  Future<void> addExpense({
    required String title,
    required String category,
    required double amount,
    String currency = 'SYP',
    DateTime? expenseDate,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    final date = expenseDate ?? DateTime.now();

    await _client.from('lab_expenses').insert({
      'title': title.trim(),
      'category': category,
      'amount': amount,
      'currency': currency,
      'expense_date': date.toIso8601String().split('T')[0],
      'payment_method': paymentMethod,
      'notes': notes?.trim(),
      'performed_by': currentUserId,
    });
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('lab_expenses').delete().eq('id', id);
  }

  // ---------------------------------------------------------------------------
  // Lab Financial Summary (التقرير المالي المنفصل للمخبر)
  // ---------------------------------------------------------------------------
  Future<LabFinancialSummary> getFinancialSummary() async {
    final invoices = await getInvoices();
    final expenses = await getExpenses();

    int totalInv = invoices.length;
    int paidInv = 0;
    int partialInv = 0;
    int unpaidInv = 0;

    double billedSyp = 0.0;
    double collectedSyp = 0.0;
    double remainingSyp = 0.0;

    double billedUsd = 0.0;
    double collectedUsd = 0.0;
    double remainingUsd = 0.0;

    for (final inv in invoices) {
      if (inv.isCancelled) continue;
      if (inv.isPaid) {
        paidInv++;
      } else if (inv.isPartial) {
        partialInv++;
      } else {
        unpaidInv++;
      }

      if (inv.currency == 'USD') {
        billedUsd += inv.totalAmount;
        collectedUsd += inv.paidAmount;
        remainingUsd += inv.remainingAmount;
      } else {
        billedSyp += inv.totalAmount;
        collectedSyp += inv.paidAmount;
        remainingSyp += inv.remainingAmount;
      }
    }

    double expSyp = 0.0;
    double expUsd = 0.0;
    for (final exp in expenses) {
      if (exp.currency == 'USD') {
        expUsd += exp.amount;
      } else {
        expSyp += exp.amount;
      }
    }

    return LabFinancialSummary(
      totalInvoices: totalInv,
      paidInvoices: paidInv,
      partialInvoices: partialInv,
      unpaidInvoices: unpaidInv,
      billedSyp: billedSyp,
      collectedSyp: collectedSyp,
      remainingSyp: remainingSyp,
      expensesSyp: expSyp,
      netProfitSyp: collectedSyp - expSyp,
      billedUsd: billedUsd,
      collectedUsd: collectedUsd,
      remainingUsd: remainingUsd,
      expensesUsd: expUsd,
      netProfitUsd: collectedUsd - expUsd,
    );
  }
}

final labClientsProvider = FutureProvider<List<LabClient>>((ref) {
  return ref.watch(dentalLabRepositoryProvider).getClients();
});

final labInvoicesProvider = FutureProvider<List<LabInvoice>>((ref) {
  return ref.watch(dentalLabRepositoryProvider).getInvoices();
});

final labExpensesProvider = FutureProvider<List<LabExpense>>((ref) {
  return ref.watch(dentalLabRepositoryProvider).getExpenses();
});

final labFinancialSummaryProvider = FutureProvider<LabFinancialSummary>((ref) {
  return ref.watch(dentalLabRepositoryProvider).getFinancialSummary();
});
