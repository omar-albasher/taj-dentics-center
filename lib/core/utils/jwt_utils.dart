import 'dart:convert';

/// أداة لاستخراج الـ claims من Supabase Access Token (JWT).
///
/// ⚠️ ملاحظة أمنية حرجة:
/// هذا الـ decode لا يتحقق من التوقيع الرقمي (signature) للتوكن —
/// وهو غير مصمم ليكون كذلك. يُستخدم حصراً لاتخاذ قرارات توجيه (routing)
/// على مستوى الواجهة (مثل إخفاء شاشات الأدمن عن غير المخوَّلين).
///
/// خط الدفاع الحقيقي يبقى دائماً Row Level Security على مستوى
/// PostgreSQL، حيث تقوم `auth.jwt()` بالتحقق من التوقيع قبل الوثوق
/// بأي claim. حتى لو نجح مستخدم خبيث بتزوير القيمة المعروضة له هنا
/// محلياً (مثلاً عبر تعديل الكود المُصرَّف)، فلن يستطيع تمرير هذا
/// التزوير عبر RLS لأن الخادم يتحقق من التوقيع الحقيقي للتوكن.
class JwtUtils {
  JwtUtils._();

  static Map<String, dynamic>? decodeClaims(String? jwt) {
    if (jwt == null || jwt.isEmpty) return null;

    final parts = jwt.split('.');
    if (parts.length != 3) return null;

    try {
      final payloadJson = _base64UrlDecode(parts[1]);
      final decoded = jsonDecode(payloadJson);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // توكن مشوَّه أو غير قابل لفك الترميز — نتعامل معه كأنه غير موجود
      return null;
    }
  }

  /// يستخرج الدور المحقون بواسطة custom_access_token_hook
  /// من ضمن claim الـ user_metadata داخل الـ JWT نفسه.
  static String? extractRole(String? jwt) {
    final claims = decodeClaims(jwt);
    if (claims == null) return null;

    final userMetadata = claims['user_metadata'];
    if (userMetadata is! Map) return null;

    final role = userMetadata['role'];
    return role is String ? role : null;
  }

  static String _base64UrlDecode(String input) {
    var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
        break;
      case 3:
        normalized += '=';
        break;
    }
    return utf8.decode(base64.decode(normalized));
  }
}
