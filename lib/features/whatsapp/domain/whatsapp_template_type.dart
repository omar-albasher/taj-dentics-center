enum WhatsAppTemplateType {
  paymentReminder('تذكير بدفعة'),
  paymentReceipt('إشعار استلام دفعة'),
  sessionReminder('تذكير بموعد جلسة'),
  custom('رسالة مخصصة');

  final String label;
  const WhatsAppTemplateType(this.label);
}
