import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_dashboard/features/command_palette/domain/command_item.dart';
import 'package:admin_dashboard/features/dental_lab/domain/dental_lab_models.dart';

void main() {
  group('CommandItem Tests (Phase B6)', () {
    test('matches query by title, subtitle, and keywords', () {
      bool selected = false;
      final cmd = CommandItem(
        id: 'test_cmd',
        title: 'إضافة متدرب جديد',
        subtitle: 'تسجيل متدرب وتوليد كود',
        keywords: ['طالب', 'trainee', 'student'],
        icon: Icons.person_add,
        category: CommandCategory.action,
        onSelect: () => selected = true,
      );

      expect(cmd.matches('متدرب'), isTrue);
      expect(cmd.matches('طالب'), isTrue);
      expect(cmd.matches('trainee'), isTrue);
      expect(cmd.matches('كود'), isTrue);
      expect(cmd.matches('مخبر'), isFalse);

      cmd.onSelect();
      expect(selected, isTrue);
    });
  });

  group('Dental Lab Models Tests (Phase 10)', () {
    test('LabInvoice calculates remaining amount and statuses accurately', () {
      final inv = LabInvoice(
        id: 'inv-1',
        invoiceNumber: 1001,
        clientId: 'client-1',
        clientName: 'د. سمير أحمد',
        currency: 'SYP',
        subtotal: 500000,
        discount: 50000,
        totalAmount: 450000,
        paidAmount: 200000,
        status: 'partial',
        issueDate: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(inv.remainingAmount, 250000);
      expect(inv.isPartial, isTrue);
      expect(inv.isPaid, isFalse);
      expect(inv.statusAr, 'مدفوعة جزئياً');
      expect(inv.currencySymbol, 'ل.س');
    });

    test('LabInvoice with USD currency symbol', () {
      final inv = LabInvoice(
        id: 'inv-2',
        invoiceNumber: 1002,
        clientId: 'client-2',
        currency: 'USD',
        totalAmount: 300,
        paidAmount: 300,
        status: 'paid',
        issueDate: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(inv.remainingAmount, 0.0);
      expect(inv.isPaid, isTrue);
      expect(inv.statusAr, 'مسددة بالكامل');
      expect(inv.currencySymbol, '\$');
    });

    test('LabClient fromMap parses data correctly', () {
      final map = {
        'id': 'c-1',
        'name': 'عيادة الشفاء السنية',
        'phone': '0933112233',
        'clinic_address': 'دمشق - المزرعة',
        'notes': 'تعامل ممتاز',
        'is_active': true,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      };

      final client = LabClient.fromMap(map);
      expect(client.name, 'عيادة الشفاء السنية');
      expect(client.phone, '0933112233');
      expect(client.clinicAddress, 'دمشق - المزرعة');
      expect(client.isActive, isTrue);
    });
  });
}
