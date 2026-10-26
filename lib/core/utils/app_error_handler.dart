import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppErrorHandler {
  AppErrorHandler._();

  static const Map<String, String> _domainMessages = {
    'COHORT_CAPACITY_REACHED':
        'المجموعة ممتلئة — أضف المتدرب إلى قائمة الانتظار أو ارفع السعة',
    'COHORT_CAPACITY_BELOW_ENROLLED':
        'لا يمكن تقليل السعة إلى أقل من عدد المتدربين المسجلين حالياً',
    'COHORT_CAPACITY_INVALID': 'قيمة السعة غير صالحة — يجب أن تكون أكبر من صفر',
    'COHORT_HAS_AVAILABLE_SEATS':
        'توجد مقاعد متاحة في هذه المجموعة — يمكن التسجيل مباشرة',
    'COHORT_NOT_ACTIVE': 'هذه المجموعة غير مفعّلة',
    'COHORT_NOT_FOUND': 'المجموعة غير موجودة',
    'TRAINEE_NOT_FOUND': 'المتدرب غير موجود أو حسابه غير مفعّل',
    'ALREADY_ENROLLED': 'هذا المتدرب مسجل بالفعل في هذه المجموعة',
    'ALREADY_ON_WAITLIST': 'هذا المتدرب موجود مسبقاً في قائمة الانتظار',
    'WAITLIST_NOT_FOUND': 'لم يتم العثور على طلب الانتظار',
    'WAITLIST_NOT_ACTIVE': 'طلب الانتظار لم يعد فعّالاً — حدّث القائمة',
    'WAITLIST_ENROLLMENT_MISSING':
        'لا يوجد تسجيل فعلي مرتبط بطلب الانتظار — أعد المحاولة',
    'WAITLIST_PROMOTION_FIELDS_REQUIRED':
        'بيانات الترقية غير مكتملة (وقت الترقية والمسؤول)',
    'WAITLIST_IDENTITY_IMMUTABLE': 'لا يمكن تعديل هوية طلب الانتظار',
    'WAITLIST_INITIAL_STATUS_INVALID': 'حالة طلب الانتظار الأولية غير صالحة',
    'INVALID_WAITLIST_TRANSITION':
        'لا يمكن تنفيذ هذا الانتقال على طلب الانتظار',
    'ADMIN_ONLY': 'هذه العملية مخصصة للإدارة فقط',
    'NOT_AUTHORIZED': 'ليس لديك الصلاحيات الكافية لتنفيذ هذا الإجراء',
    'AUTH_REQUIRED': 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً',
    'INVALID_TOTAL_DUE': 'قيمة المبلغ المطلوب غير صالحة',
    'INVALID_DISCOUNT': 'قيمة الخصم غير صالحة',
    'INVALID_CURRENCY': 'العملة غير مدعومة — استخدم SYP أو USD',
    'REFERRAL_CODE_INVALID': 'كود الإحالة غير صحيح',
    'REFERRAL_REFERRER_INACTIVE': 'حساب صاحب كود الإحالة غير مفعّل',
    'REFERRAL_SELF': 'لا يمكن استخدام كود الإحالة الخاص بالمتدرب نفسه',
    'REFERRAL_REFEREE_ENROLLED':
        'المتدرب مسجل حالياً في دورة من نفس نوع هذه الدورة — لا يمكن تطبيق الإحالة',
    'REFERRAL_ALREADY_REFERRED':
        'تم استخدام كود إحالة لهذا المتدرب في هذه الدورة مسبقاً',
    'REFERRAL_MUTUAL': 'لا يمكن تبادل الإحالة بين المتدربين في الدورة نفسها',
    'REFERRAL_NOTHING_DUE': 'لا يوجد مبلغ مستحق بعد الخصم لتطبيق خصم الإحالة',
    'REFERRAL_DISCOUNT_TOO_HIGH':
        'قيمة خصم الإحالة أكبر من المبلغ المتبقي بعد الخصم اليدوي',
    'REFERRAL_DISCOUNT_INVALID': 'قيمة خصم الإحالة غير صالحة',
  };

  /// Converts any technical or database exception into a clear, user-friendly Arabic message.
  static String friendlyMessage(Object? error) {
    if (error == null) {
      return 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً';
    }

    // 1. Supabase PostgREST Database Exceptions
    if (error is PostgrestException) {
      return _handlePostgrestException(error);
    }

    // 2. Supabase Auth Exceptions
    if (error is AuthException) {
      return _handleAuthException(error);
    }

    // 3. Network & Connection Exceptions
    if (error is SocketException) {
      return 'تعذر الاتصال بالخادم، يرجى التحقق من اتصال الإنترنت';
    }

    if (error is TimeoutException) {
      return 'استغرقت الاستجابة وقتاً أطول من المعتاد، يرجى إعادة المحاولة';
    }

    final rawString = error.toString();

    // Check common network error keywords in string form (for web & platform differences)
    final lower = rawString.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('clientexception') ||
        lower.contains('xmlhttprequest error') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset')) {
      return 'تعذر الاتصال بالخادم، يرجى التحقق من اتصال الإنترنت';
    }

    if (lower.contains('jwt expired') || lower.contains('token has expired')) {
      return 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً';
    }

    // If an application exception was already thrown with friendly Arabic text (e.g. Exception('غير مصرح'))
    if (_containsArabic(rawString)) {
      final cleaned =
          rawString.replaceAll(RegExp(r'^Exception:\s*'), '').trim();
      if (cleaned.isNotEmpty && !cleaned.contains('PostgrestException')) {
        return cleaned;
      }
    }

    return 'حدث خطأ أثناء معالجة الطلب، يرجى المحاولة لاحقاً';
  }

  static String _handlePostgrestException(PostgrestException e) {
    final code = e.code;
    final msg = e.message.toLowerCase();

    final domainMessage = _domainMessage(e);
    if (domainMessage != null) return domainMessage;

    // Specific PostgreSQL error codes
    switch (code) {
      case '23505': // unique_violation
        if (msg.contains('uq_trainees_trainee_code')) {
          return 'كود المتدرب مستخدم لمتدرب آخر — اختر كوداً مختلفاً';
        }
        if (msg.contains('attendance')) {
          return 'تم تسجيل حضور هذا المتدرب في هذه الجلسة مسبقاً';
        }
        if (msg.contains('survey_responses') || msg.contains('dispatch')) {
          return 'تمت الإجابة على هذا الاستبيان مسبقاً';
        }
        return 'هذا السجل أو البيان موجود مسبقاً في النظام';
      case '23503': // foreign_key_violation
        return 'لا يمكن إتمام العملية لارتباط هذا السجل ببيانات أخرى في النظام';
      case '42501': // insufficient_privilege
        return 'ليس لديك الصلاحيات الكافية لتنفيذ هذا الإجراء';
      case 'PGRST116': // JSON object requested, multiple or zero results
        return 'لم يتم العثور على السجل المطلوب';
      default:
        break;
    }

    // Check message content
    if (e.message.contains('غير مصرح')) {
      return e.message;
    }
    if (msg.contains('jwt') || msg.contains('expired')) {
      return 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً';
    }

    return 'حدث خطأ في قاعدة البيانات (${code ?? "غير محدد"})، يرجى إعادة المحاولة';
  }

  static String? _domainMessage(PostgrestException e) {
    final raw = e.message.trim();
    final direct = _domainMessages[raw];
    if (direct != null) return direct;

    final details = e.details?.toString() ?? '';
    for (final entry in _domainMessages.entries) {
      if (raw.contains(entry.key) || details.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static String _handleAuthException(AuthException e) {
    final msg = e.message.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_grant')) {
      return 'بيانات تسجيل الدخول غير صحيحة، يرجى التأكد من البريد وكلمة المرور';
    }
    if (msg.contains('email not confirmed')) {
      return 'يرجى تأكيد الحساب عبر البريد الإلكتروني أولاً';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already exists')) {
      return 'البريد الإلكتروني مسجل بالفعل لمستخدم آخر';
    }
    if (msg.contains('password should be at least')) {
      return 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل';
    }

    return 'حدث خطأ في المصادقة: ${e.message}';
  }

  static bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }
}
