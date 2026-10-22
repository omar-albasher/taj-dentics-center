class LabClient {
  final String id;
  final String name;
  final String? phone;
  final String? clinicAddress;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LabClient({
    required this.id,
    required this.name,
    this.phone,
    this.clinicAddress,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LabClient.fromMap(Map<String, dynamic> map) {
    return LabClient(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      clinicAddress: map['clinic_address']?.toString(),
      notes: map['notes']?.toString(),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (phone != null) 'phone': phone,
      if (clinicAddress != null) 'clinic_address': clinicAddress,
      if (notes != null) 'notes': notes,
      'is_active': isActive,
    };
  }
}

class LabInvoiceItem {
  final String id;
  final String invoiceId;
  final String serviceName;
  final String? toothNumber;
  final String? shade;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  const LabInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.serviceName,
    this.toothNumber,
    this.shade,
    this.quantity = 1,
    this.unitPrice = 0.0,
    this.totalPrice = 0.0,
    this.notes,
  });

  factory LabInvoiceItem.fromMap(Map<String, dynamic> map) {
    final qty = (map['quantity'] as num?)?.toInt() ?? 1;
    final unit = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
    final total = (map['total_price'] as num?)?.toDouble() ?? (qty * unit);

    return LabInvoiceItem(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      serviceName: map['service_name']?.toString() ?? '',
      toothNumber: map['tooth_number']?.toString(),
      shade: map['shade']?.toString(),
      quantity: qty,
      unitPrice: unit,
      totalPrice: total,
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'service_name': serviceName,
      if (toothNumber != null && toothNumber!.isNotEmpty) 'tooth_number': toothNumber,
      if (shade != null && shade!.isNotEmpty) 'shade': shade,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

class LabPayment {
  final String id;
  final String invoiceId;
  final double amount;
  final String currency;
  final DateTime paidAt;
  final String method;
  final String? receiptNumber;
  final String? externalReference;
  final String? notes;
  final String? performedBy;

  const LabPayment({
    required this.id,
    required this.invoiceId,
    required this.amount,
    this.currency = 'SYP',
    required this.paidAt,
    this.method = 'cash',
    this.receiptNumber,
    this.externalReference,
    this.notes,
    this.performedBy,
  });

  factory LabPayment.fromMap(Map<String, dynamic> map) {
    return LabPayment(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency']?.toString() ?? 'SYP',
      paidAt: map['paid_at'] != null
          ? (DateTime.tryParse(map['paid_at'].toString()) ?? DateTime.now()).toLocal()
          : DateTime.now(),
      method: map['method']?.toString() ?? 'cash',
      receiptNumber: map['receipt_number']?.toString(),
      externalReference: map['external_reference']?.toString(),
      notes: map['notes']?.toString(),
      performedBy: map['performed_by']?.toString(),
    );
  }

  String get paymentMethodAr {
    switch (method) {
      case 'cash':
        return 'نقداً';
      case 'sham_cash':
        return 'شام كاش';
      case 'hawala':
        return 'حوالة هرم';
      case 'bank_transfer':
      case 'bank':
        return 'تحويل مصرفي';
      default:
        return method;
    }
  }

  String get currencySymbol => currency == 'USD' ? '\$' : 'ل.س';
}

class LabInvoice {
  final String id;
  final int invoiceNumber;
  final String clientId;
  final String? clientName;
  final String? clientPhone;
  final String? patientName;
  final String status;
  final String currency;
  final double subtotal;
  final double discount;
  final double totalAmount;
  final double paidAmount;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final List<LabInvoiceItem> items;
  final List<LabPayment> payments;

  const LabInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.clientId,
    this.clientName,
    this.clientPhone,
    this.patientName,
    this.status = 'unpaid',
    this.currency = 'SYP',
    this.subtotal = 0.0,
    this.discount = 0.0,
    this.totalAmount = 0.0,
    this.paidAmount = 0.0,
    required this.issueDate,
    this.dueDate,
    this.notes,
    this.createdBy,
    required this.createdAt,
    this.items = const [],
    this.payments = const [],
  });

  factory LabInvoice.fromMap(Map<String, dynamic> map) {
    String? cName;
    String? cPhone;
    if (map['lab_clients'] is Map<String, dynamic>) {
      cName = map['lab_clients']['name']?.toString();
      cPhone = map['lab_clients']['phone']?.toString();
    }

    final itemsList = <LabInvoiceItem>[];
    if (map['lab_invoice_items'] is List) {
      for (final item in map['lab_invoice_items']) {
        if (item is Map<String, dynamic>) {
          itemsList.add(LabInvoiceItem.fromMap(item));
        }
      }
    }

    final paymentsList = <LabPayment>[];
    if (map['lab_payments'] is List) {
      for (final p in map['lab_payments']) {
        if (p is Map<String, dynamic>) {
          paymentsList.add(LabPayment.fromMap(p));
        }
      }
    }

    return LabInvoice(
      id: map['id']?.toString() ?? '',
      invoiceNumber: (map['invoice_number'] as num?)?.toInt() ?? 0,
      clientId: map['client_id']?.toString() ?? '',
      clientName: cName ?? map['client_name']?.toString(),
      clientPhone: cPhone ?? map['client_phone']?.toString(),
      patientName: map['patient_name']?.toString(),
      status: map['status']?.toString() ?? 'unpaid',
      currency: map['currency']?.toString() ?? 'SYP',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      issueDate: map['issue_date'] != null
          ? DateTime.tryParse(map['issue_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'].toString())
          : null,
      notes: map['notes']?.toString(),
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: itemsList,
      payments: paymentsList,
    );
  }

  double get remainingAmount => (totalAmount - paidAmount).clamp(0.0, double.infinity);
  bool get isPaid => status == 'paid';
  bool get isPartial => status == 'partial';
  bool get isUnpaid => status == 'unpaid';
  bool get isCancelled => status == 'cancelled';

  String get statusAr {
    switch (status) {
      case 'paid':
        return 'مسددة بالكامل';
      case 'partial':
        return 'مدفوعة جزئياً';
      case 'cancelled':
        return 'ملغاة';
      case 'unpaid':
      default:
        return 'غير مدفوعة';
    }
  }

  String get currencySymbol => currency == 'USD' ? '\$' : 'ل.س';
}

class LabExpense {
  final String id;
  final String title;
  final String category;
  final double amount;
  final String currency;
  final DateTime expenseDate;
  final String paymentMethod;
  final String? notes;
  final String? performedBy;

  const LabExpense({
    required this.id,
    required this.title,
    this.category = 'materials',
    required this.amount,
    this.currency = 'SYP',
    required this.expenseDate,
    this.paymentMethod = 'cash',
    this.notes,
    this.performedBy,
  });

  factory LabExpense.fromMap(Map<String, dynamic> map) {
    return LabExpense(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      category: map['category']?.toString() ?? 'materials',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency']?.toString() ?? 'SYP',
      expenseDate: map['expense_date'] != null
          ? DateTime.tryParse(map['expense_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: map['payment_method']?.toString() ?? 'cash',
      notes: map['notes']?.toString(),
      performedBy: map['performed_by']?.toString(),
    );
  }

  String get categoryAr {
    switch (category) {
      case 'materials':
        return 'شراء مواد وخامات';
      case 'equipment_maintenance':
        return 'صيانة أجهزة ومعدات';
      case 'utilities':
        return 'فواتير ومرافق (كهرباء/غاز)';
      case 'salaries':
        return 'رواتب وأجور مخبر';
      case 'other':
      default:
        return 'مصاريف مخبر أخرى';
    }
  }

  String get paymentMethodAr {
    switch (paymentMethod) {
      case 'cash':
        return 'نقداً';
      case 'sham_cash':
        return 'شام كاش';
      case 'hawala':
        return 'حوالة هرم';
      case 'bank_transfer':
      case 'bank':
        return 'تحويل مصرفي';
      default:
        return paymentMethod;
    }
  }

  String get currencySymbol => currency == 'USD' ? '\$' : 'ل.س';
}

class LabFinancialSummary {
  final int totalInvoices;
  final int paidInvoices;
  final int partialInvoices;
  final int unpaidInvoices;
  final double billedSyp;
  final double collectedSyp;
  final double remainingSyp;
  final double expensesSyp;
  final double netProfitSyp;
  final double billedUsd;
  final double collectedUsd;
  final double remainingUsd;
  final double expensesUsd;
  final double netProfitUsd;

  const LabFinancialSummary({
    required this.totalInvoices,
    required this.paidInvoices,
    required this.partialInvoices,
    required this.unpaidInvoices,
    required this.billedSyp,
    required this.collectedSyp,
    required this.remainingSyp,
    required this.expensesSyp,
    required this.netProfitSyp,
    required this.billedUsd,
    required this.collectedUsd,
    required this.remainingUsd,
    required this.expensesUsd,
    required this.netProfitUsd,
  });

  factory LabFinancialSummary.zero() {
    return const LabFinancialSummary(
      totalInvoices: 0,
      paidInvoices: 0,
      partialInvoices: 0,
      unpaidInvoices: 0,
      billedSyp: 0,
      collectedSyp: 0,
      remainingSyp: 0,
      expensesSyp: 0,
      netProfitSyp: 0,
      billedUsd: 0,
      collectedUsd: 0,
      remainingUsd: 0,
      expensesUsd: 0,
      netProfitUsd: 0,
    );
  }
}
