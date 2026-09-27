import 'package:admin_dashboard/core/auth/authorization_policy.dart';
import 'package:admin_dashboard/core/utils/jwt_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة مستقلة تفرض تسجيل خروج فوري لأي جلسة تحمل دوراً غير مخوَّل
/// بالوصول للوحة التحكم — سواء كانت الجلسة ناتجة عن:
///
///  1. [AuthChangeEvent.signedIn] — تسجيل دخول تفاعلي جديد (المستخدم
///     كتب بياناته وضغط زر الدخول خلال الجلسة الحالية للتطبيق)
///  2. [AuthChangeEvent.initialSession] — استعادة جلسة محفوظة مسبقاً
///     بـ localStorage عند إقلاع التطبيق، دون أي تفاعل من المستخدم
///
/// ── لماذا كلا الحدثين ضروريان (Defense in Depth) ──
/// الاعتماد على [signedIn] فقط يترك فجوة: حساب غير مخوَّل سجّل دخوله
/// سابقاً ثم أعاد فتح التطبيق لاحقاً (دون تسجيل خروج صريح) ستُستعاد
/// جلسته عبر [initialSession] فقط. رغم أن `redirect()` بالراوتر يمنع
/// وصول هذه الجلسة للمسارات المحمية، تبقى الجلسة "حيّة" تقنياً بذاكرة
/// Supabase Client دون داعٍ — وهذا انتهاك لمبدأ تقليل سطح الهجوم
/// (Attack Surface Minimization)، حتى لو لم يُستغَل فعلياً بالوضع
/// الحالي بفضل RLS وحارس التوجيه.
///
/// ⚠️ ملاحظة أمنية جوهرية: هذه الخدمة طبقة UX/نظافة جلسات على مستوى
/// العميل فقط. الحماية الفعلية والوحيدة الموثوقة ضد الوصول غير
/// المخوَّل للبيانات تبقى دائماً Row Level Security على مستوى
/// PostgreSQL — لأن أي منطق بجهة العميل (بما فيه هذه الخدمة) قابل
/// نظرياً للتجاوز من قِبل عميل معدَّل أو استدعاء API مباشر.
class SessionAuthorizationEnforcer {
  SessionAuthorizationEnforcer._();

  static final SessionAuthorizationEnforcer instance =
      SessionAuthorizationEnforcer._();

  bool _initialized = false;

  /// الأحداث التي تمثّل "جلسة نشطة يجب فحص تخويلها" — أي حدث آخر
  /// (signedOut, tokenRefreshed, userUpdated, إلخ) لا يعنينا هنا.
  static const _sessionEstablishedEvents = {
    AuthChangeEvent.signedIn,
    AuthChangeEvent.initialSession,
  };

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      if (!_sessionEstablishedEvents.contains(event) || session == null) {
        return;
      }

      final role = JwtUtils.extractRole(session.accessToken);

      if (kDebugMode) {
        debugPrint(
          '[AuthEnforcer] $event — role from JWT = "$role"',
        );
      }

      if (!AuthorizationPolicy.isDashboardRole(role)) {
        if (kDebugMode) {
          debugPrint(
            '[AuthEnforcer] Unauthorized role "$role" via $event '
            '— enforcing sign-out',
          );
        }
        await Supabase.instance.client.auth.signOut();
      }
    });
  }
}
