import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/utils/responsive.dart';
import '../domain/whatsapp_template_type.dart';

class WhatsAppTemplateDialog extends StatefulWidget {
  final String traineeName;
  final String? whatsappNumber;
  final String? courseName;
  final num? amount;
  final String? receiptNumber;
  final num? balance;
  final String? currency;
  final String? sessionTitle;
  final DateTime? sessionDate;
  final WhatsAppTemplateType initialType;

  const WhatsAppTemplateDialog({
    super.key,
    required this.traineeName,
    required this.whatsappNumber,
    this.courseName,
    this.amount,
    this.receiptNumber,
    this.balance,
    this.currency = 'ل.س',
    this.sessionTitle,
    this.sessionDate,
    this.initialType = WhatsAppTemplateType.paymentReminder,
  });

  static Future<void> show(
    BuildContext context, {
    required String traineeName,
    required String? whatsappNumber,
    String? courseName,
    num? amount,
    String? receiptNumber,
    num? balance,
    String? currency = 'ل.س',
    String? sessionTitle,
    DateTime? sessionDate,
    WhatsAppTemplateType initialType = WhatsAppTemplateType.paymentReminder,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => WhatsAppTemplateDialog(
        traineeName: traineeName,
        whatsappNumber: whatsappNumber,
        courseName: courseName,
        amount: amount,
        receiptNumber: receiptNumber,
        balance: balance,
        currency: currency,
        sessionTitle: sessionTitle,
        sessionDate: sessionDate,
        initialType: initialType,
      ),
    );
  }

  @override
  State<WhatsAppTemplateDialog> createState() => _WhatsAppTemplateDialogState();
}

class _WhatsAppTemplateDialogState extends State<WhatsAppTemplateDialog> {
  late WhatsAppTemplateType _selectedType;
  late final TextEditingController _msgController;
  final _amountFmt = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _msgController = TextEditingController(text: _generateMessage(_selectedType));
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  String _formatAmount(num? val) {
    if (val == null) return '0';
    return _amountFmt.format(val.toInt());
  }

  String _generateMessage(WhatsAppTemplateType type) {
    final tName = widget.traineeName.trim().isNotEmpty ? widget.traineeName.trim() : 'المتدرب الكريم';
    final cName = widget.courseName ?? 'الكورس التدريبي';
    final curr = widget.currency ?? 'ل.س';

    switch (type) {
      case WhatsAppTemplateType.paymentReminder:
        final b = _formatAmount(widget.balance);
        return 'مرحباً د. $tName 🌸\n'
            'نود تذكيركم بلطف بوجود دفعة مستحقة لدورة $cName بقيمة $b $curr.\n'
            'نرجو التكرم بالتسديد في أقرب وقت.\n\n'
            'شاكرين حسن تعاونكم،\n'
            'مركز تاج لطب الأسنان التدريبي';

      case WhatsAppTemplateType.paymentReceipt:
        final a = _formatAmount(widget.amount);
        final receiptStr = (widget.receiptNumber != null && widget.receiptNumber!.trim().isNotEmpty)
            ? 'رقم الإيصال: ${widget.receiptNumber!.trim()}\n'
            : '';
        final balanceStr = (widget.balance != null)
            ? 'الرصيد المتبقي: ${_formatAmount(widget.balance)} $curr\n'
            : '';
        return 'مرحباً د. $tName 🌸\n'
            'تم بنجاح استلام دفعة بقيمة $a $curr لدورة $cName.\n'
            '$receiptStr'
            '$balanceStr\n'
            'شكراً لثقتكم واختياركم مركز تاج لطب الأسنان التدريبي ✨';

      case WhatsAppTemplateType.sessionReminder:
        final title = (widget.sessionTitle != null && widget.sessionTitle!.trim().isNotEmpty)
            ? widget.sessionTitle!.trim()
            : 'جلسة تدريبية';
        final dateStr = widget.sessionDate != null
            ? DateFormat('EEEE yyyy/MM/dd', 'ar').format(widget.sessionDate!)
            : 'الموعد المحدد';
        final timeStr = widget.sessionDate != null
            ? DateFormat('hh:mm a', 'ar').format(widget.sessionDate!)
            : '';
        final timePart = timeStr.isNotEmpty ? 'الساعة $timeStr' : '';

        return 'مرحباً د. $tName 🌸\n'
            'نود تذكيركم بموعد $title لدورة $cName\n'
            'يوم $dateStr $timePart.\n\n'
            'نتمنى لكم كل التوفيق،\n'
            'مركز تاج لطب الأسنان التدريبي';

      case WhatsAppTemplateType.custom:
        return 'مرحباً د. $tName 🌸\n\nمركز تاج لطب الأسنان التدريبي';
    }
  }

  void _onTypeChanged(WhatsAppTemplateType type) {
    setState(() {
      _selectedType = type;
      _msgController.text = _generateMessage(type);
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _msgController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ نص الرسالة إلى الحافظة', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendWhatsApp() async {
    final success = await PhoneUtils.launchWhatsApp(
      phone: widget.whatsappNumber,
      message: _msgController.text,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح واتساب. يرجى التأكد من صحة الرقم.', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sanitizedPhone = PhoneUtils.sanitizePhone(widget.whatsappNumber);
    final isValid = sanitizedPhone != null;

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إرسال رسالة واتساب',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.traineeName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sanitizedPhone != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        '+$sanitizedPhone',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Template Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WhatsAppTemplateType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return ChoiceChip(
                    label: Text(
                      type.label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.black : AppColors.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.gold,
                    backgroundColor: AppColors.surface,
                    onSelected: (_) => _onTypeChanged(type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Message Preview & Editor
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  controller: _msgController,
                  maxLines: 7,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'اكتب نص الرسالة هنا...',
                    hintStyle: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('نسخ النص', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: isValid ? _sendWhatsApp : null,
                    icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    label: const Text('إرسال عبر واتساب', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      disabledBackgroundColor: AppColors.divider,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
