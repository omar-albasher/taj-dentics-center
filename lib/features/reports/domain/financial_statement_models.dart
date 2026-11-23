const String financialSectionAcademy = 'academy';
const String financialSectionLab = 'lab';

const double _moneyTolerance = 0.005;

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

String _sectionLabel(String section) {
  switch (section) {
    case financialSectionAcademy:
      return 'الأكاديمية';
    case financialSectionLab:
      return 'المخبر';
    default:
      return section;
  }
}

String _accountTypeLabel(String accountType) {
  switch (accountType) {
    case 'cash':
      return 'صندوق نقدي';
    case 'bank':
      return 'حساب بنكي';
    case 'wallet':
      return 'محفظة إلكترونية';
    default:
      return accountType;
  }
}

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class FinancialStatementPeriod {
  final DateTime from;
  final DateTime to;

  const FinancialStatementPeriod({required this.from, required this.to});

  bool get isValid => !to.isBefore(from);

  String get fromIso => _isoDate(from);

  String get toIso => _isoDate(to);
}

class ProfitLossLine {
  final String currency;
  final String section;
  final double income;
  final double refunds;
  final double expenses;
  final double net;
  final double memorandumUncollected;

  const ProfitLossLine({
    required this.currency,
    required this.section,
    required this.income,
    required this.refunds,
    required this.expenses,
    required this.net,
    this.memorandumUncollected = 0,
  });

  factory ProfitLossLine.fromMap(Map<String, dynamic> map) {
    return ProfitLossLine(
      currency: map['currency']?.toString() ?? '',
      section: map['section']?.toString() ?? financialSectionAcademy,
      income: _asDouble(map['income']),
      refunds: _asDouble(map['refunds']),
      expenses: _asDouble(map['expenses']),
      net: _asDouble(map['net']),
      memorandumUncollected: _asDouble(map['memorandum_uncollected']),
    );
  }

  bool get isAcademy => section == financialSectionAcademy;

  bool get isLab => section == financialSectionLab;

  bool get hasMemorandum => memorandumUncollected > 0;

  String get sectionLabel => _sectionLabel(section);

  double get computedNet => income - refunds - expenses;

  bool get reconciles => (net - computedNet).abs() < _moneyTolerance;
}

class ProfitLossStatement {
  final List<ProfitLossLine> lines;

  const ProfitLossStatement(this.lines);

  factory ProfitLossStatement.fromRows(List<Map<String, dynamic>> rows) {
    return ProfitLossStatement(
      List<ProfitLossLine>.unmodifiable(
        rows.map(ProfitLossLine.fromMap),
      ),
    );
  }

  List<ProfitLossLine> get academy => List<ProfitLossLine>.unmodifiable(
        lines.where((line) => line.isAcademy),
      );

  List<ProfitLossLine> get lab => List<ProfitLossLine>.unmodifiable(
        lines.where((line) => line.isLab),
      );

  List<String> get currencies {
    final seen = <String>{};
    for (final line in lines) {
      if (line.currency.isNotEmpty) seen.add(line.currency);
    }
    return List<String>.unmodifiable(seen);
  }

  ProfitLossLine? lineFor(String section, String currency) {
    for (final line in lines) {
      if (line.section == section && line.currency == currency) return line;
    }
    return null;
  }

  double memorandumFor(String currency) =>
      lineFor(financialSectionLab, currency)?.memorandumUncollected ?? 0;

  bool get allReconcile => lines.every((line) => line.reconciles);

  bool get hasLabActivity =>
      lab.any((line) => line.income != 0 || line.expenses != 0);

  bool get hasMemorandum => lab.any((line) => line.memorandumUncollected > 0);
}

class ExpenseBreakdownItem {
  static const Map<String, String> _labCategoryLabels = {
    'materials': 'مواد',
    'equipment_maintenance': 'صيانة أجهزة',
    'utilities': 'فواتير ومرافق',
    'salaries': 'رواتب',
    'other': 'أخرى',
  };

  final String section;
  final String currency;
  final String? accountId;
  final String? accountNameAr;
  final String category;
  final double amount;
  final int expenseCount;

  const ExpenseBreakdownItem({
    required this.section,
    required this.currency,
    this.accountId,
    this.accountNameAr,
    required this.category,
    required this.amount,
    required this.expenseCount,
  });

  factory ExpenseBreakdownItem.fromMap(Map<String, dynamic> map) {
    return ExpenseBreakdownItem(
      section: map['section']?.toString() ?? financialSectionAcademy,
      currency: map['currency']?.toString() ?? '',
      accountId: map['account_id']?.toString(),
      accountNameAr: map['account_name_ar']?.toString(),
      category: map['category']?.toString() ?? '',
      amount: _asDouble(map['amount']),
      expenseCount: _asInt(map['expense_count']),
    );
  }

  bool get isAcademy => section == financialSectionAcademy;

  bool get isLab => section == financialSectionLab;

  String get sectionLabel => _sectionLabel(section);

  String get categoryLabel {
    if (section == financialSectionLab) {
      return _labCategoryLabels[category] ?? category;
    }
    return category;
  }
}

class CashFlowAccountStatement {
  final String accountId;
  final String accountNameAr;
  final String accountType;
  final String currency;
  final double openingBalance;
  final double inflows;
  final double outflows;
  final double closingBalance;
  final double paymentIn;
  final double expenseOut;
  final double refundOut;
  final double transferIn;
  final double transferOut;
  final double adjustmentIn;
  final double adjustmentOut;
  final int txCount;

  const CashFlowAccountStatement({
    required this.accountId,
    required this.accountNameAr,
    required this.accountType,
    required this.currency,
    required this.openingBalance,
    required this.inflows,
    required this.outflows,
    required this.closingBalance,
    required this.paymentIn,
    required this.expenseOut,
    required this.refundOut,
    required this.transferIn,
    required this.transferOut,
    required this.adjustmentIn,
    required this.adjustmentOut,
    required this.txCount,
  });

  factory CashFlowAccountStatement.fromMap(Map<String, dynamic> map) {
    return CashFlowAccountStatement(
      accountId: map['account_id']?.toString() ?? '',
      accountNameAr: map['account_name_ar']?.toString() ?? '',
      accountType: map['account_type']?.toString() ?? 'cash',
      currency: map['currency']?.toString() ?? '',
      openingBalance: _asDouble(map['opening_balance']),
      inflows: _asDouble(map['inflows']),
      outflows: _asDouble(map['outflows']),
      closingBalance: _asDouble(map['closing_balance']),
      paymentIn: _asDouble(map['payment_in']),
      expenseOut: _asDouble(map['expense_out']),
      refundOut: _asDouble(map['refund_out']),
      transferIn: _asDouble(map['transfer_in']),
      transferOut: _asDouble(map['transfer_out']),
      adjustmentIn: _asDouble(map['adjustment_in']),
      adjustmentOut: _asDouble(map['adjustment_out']),
      txCount: _asInt(map['tx_count']),
    );
  }

  String get accountTypeLabel => _accountTypeLabel(accountType);

  double get netFlow => inflows - outflows;

  bool get identityHolds =>
      (closingBalance - (openingBalance + netFlow)).abs() < _moneyTolerance;
}

class CashFlowStatement {
  final List<CashFlowAccountStatement> accounts;

  const CashFlowStatement(this.accounts);

  factory CashFlowStatement.fromRows(List<Map<String, dynamic>> rows) {
    return CashFlowStatement(
      List<CashFlowAccountStatement>.unmodifiable(
        rows.map(CashFlowAccountStatement.fromMap),
      ),
    );
  }

  List<CashFlowAccountStatement> accountsFor(String currency) =>
      List<CashFlowAccountStatement>.unmodifiable(
        accounts.where((account) => account.currency == currency),
      );

  double openingFor(String currency) => accountsFor(currency)
      .fold(0.0, (sum, account) => sum + account.openingBalance);

  double inflowsFor(String currency) =>
      accountsFor(currency).fold(0.0, (sum, account) => sum + account.inflows);

  double outflowsFor(String currency) =>
      accountsFor(currency).fold(0.0, (sum, account) => sum + account.outflows);

  double closingFor(String currency) => accountsFor(currency)
      .fold(0.0, (sum, account) => sum + account.closingBalance);

  bool get allIdentitiesHold =>
      accounts.every((account) => account.identityHolds);
}

class FinancialIntegrityLine {
  final String sourceType;
  final String currency;
  final double eventsTotal;
  final double ledgerTotal;
  final double diff;
  final bool isBalanced;

  const FinancialIntegrityLine({
    required this.sourceType,
    required this.currency,
    required this.eventsTotal,
    required this.ledgerTotal,
    required this.diff,
    required this.isBalanced,
  });

  factory FinancialIntegrityLine.fromMap(Map<String, dynamic> map) {
    final diff = _asDouble(map['diff']);
    return FinancialIntegrityLine(
      sourceType: map['source_type']?.toString() ?? '',
      currency: map['currency']?.toString() ?? '',
      eventsTotal: _asDouble(map['events_total']),
      ledgerTotal: _asDouble(map['ledger_total']),
      diff: diff,
      isBalanced: map['is_balanced'] is bool
          ? map['is_balanced'] as bool
          : diff.abs() < _moneyTolerance,
    );
  }

  String get sourceTypeLabel {
    switch (sourceType) {
      case 'payment':
        return 'الدفعات';
      case 'refund':
        return 'الاستردادات';
      case 'expense':
        return 'المصاريف';
      default:
        return sourceType;
    }
  }
}

class FinancialIntegrityReport {
  final List<FinancialIntegrityLine> lines;

  const FinancialIntegrityReport(this.lines);

  factory FinancialIntegrityReport.fromRows(List<Map<String, dynamic>> rows) {
    return FinancialIntegrityReport(
      List<FinancialIntegrityLine>.unmodifiable(
        rows.map(FinancialIntegrityLine.fromMap),
      ),
    );
  }

  bool get isBalanced => lines.every((line) => line.isBalanced);

  List<FinancialIntegrityLine> get unbalanced =>
      List<FinancialIntegrityLine>.unmodifiable(
        lines.where((line) => !line.isBalanced),
      );
}
