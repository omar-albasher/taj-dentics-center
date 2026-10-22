import 'package:url_launcher/url_launcher.dart';

/// معالج ومطهر أرقام الهواتف وتحويلها لرابط واتساب معتمد وآمن.
class PhoneUtils {
  PhoneUtils._();

  /// تطهير وتوحيد رقم الهاتف وتحويله للصيغة الدولية المناسبة لواتساب.
  /// يرجع null إذا كان الرقم فارغاً أو غير صالح.
  static String? sanitizePhone(String? rawPhone) {
    if (rawPhone == null || rawPhone.trim().isEmpty) return null;

    // استخراج الأرقام فقط (يزيل +, -, المسافات، الأقواس)
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    // معالجة بادئة 00 الدولية
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }

    // معالجة الأرقام السورية
    // 1) 09XXXXXXXX (10 أرقام) -> 9639XXXXXXXX (12 رقم)
    if (digits.startsWith('09') && digits.length == 10) {
      return '963${digits.substring(1)}';
    }

    // 2) 9XXXXXXXX (9 أرقام تبدأ بـ 9) -> 9639XXXXXXXX
    if (digits.startsWith('9') && digits.length == 9) {
      return '963$digits';
    }

    // 3) 96309XXXXXXXX (13 رقم تم إدخال الصفر بعد المفتاح) -> 9639XXXXXXXX
    if (digits.startsWith('96309') && digits.length == 13) {
      return '963${digits.substring(4)}';
    }

    // 4) 9639XXXXXXXX (12 رقم، الصيغة السورية النظامية)
    if (digits.startsWith('963') && digits.length == 12) {
      return digits;
    }

    // أرقام دولية أخرى مقبولة (بين 10 و 15 رقماً)
    if (digits.length >= 10 && digits.length <= 15) {
      return digits;
    }

    // أي رقم خارج هذه المعايير يُعتبر غير صالح
    return null;
  }

  /// إنشاء كائن Uri لرابط واتساب الرسمي عبر wa.me
  /// مع ترميز سليم 100% للرسالة النصية والرموز التعبيرية بدون دمج يدوي.
  static Uri? toWaMeUri({required String? phone, String? message}) {
    final cleaned = sanitizePhone(phone);
    if (cleaned == null) return null;

    return Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$cleaned',
      queryParameters: (message != null && message.trim().isNotEmpty)
          ? {'text': message.trim()}
          : null,
    );
  }

  /// فحص إمكانية فتح واتساب وفتحه بنافذة خارجية
  static Future<bool> launchWhatsApp({required String? phone, String? message}) async {
    final uri = toWaMeUri(phone: phone, message: message);
    if (uri == null) return false;

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
