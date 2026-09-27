import 'package:admin_dashboard/core/shell/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/trainees/presentation/trainees_screen.dart';
import '../../features/trainees/presentation/trainee_profile_screen.dart';
import '../../features/courses/presentation/courses_screen.dart';
import '../../features/sessions/presentation/sessions_screen.dart';
import '../../features/payments/presentation/payments_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/surveys/presentation/surveys_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/audit/presentation/audit_screen.dart';
import '../utils/jwt_utils.dart';
import '../auth/authorization_policy.dart';

/// الأدوار المخوَّلة بالوصول للوحة التحكم.
// ignore: unused_element
const _authorizedDashboardRoles = {'admin', 'reception'};

class AppRouter {
  AppRouter._();

  static const login = '/login';
  static const dashboard = '/dashboard';
  static const trainees = '/trainees';
  static const courses = '/courses';
  static const sessions = '/sessions';
  static const payments = '/payments';
  static const expenses = '/expenses';
  static const reports = '/reports';
  static const surveys = '/surveys';
  static const calendar = '/calendar';
  static const users = '/users';
  static const audit = '/audit';

  static final router = GoRouter(
    initialLocation: dashboard,
    refreshListenable: _AuthNotifier(),
    redirect: _guardRedirect,
    routes: [
      GoRoute(
        path: login,
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: dashboard, builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: trainees,
            builder: (_, __) => const TraineesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return TraineeProfileScreen(traineeId: id);
                },
              ),
            ],
          ),
          GoRoute(path: courses, builder: (_, __) => const CoursesScreen()),
          GoRoute(path: sessions, builder: (_, __) => const SessionsScreen()),
          GoRoute(path: payments, builder: (_, __) => const PaymentsScreen()),
          GoRoute(path: expenses, builder: (_, __) => const ExpensesScreen()),
          GoRoute(path: reports, builder: (_, __) => const ReportsScreen()),
          GoRoute(path: surveys, builder: (_, __) => const SurveysScreen()),
          GoRoute(path: calendar, builder: (_, __) => const CalendarScreen()),
          GoRoute(path: users, builder: (_, __) => const UsersScreen()),
          GoRoute(path: audit, builder: (_, __) => const AuditScreen()),
        ],
      ),
    ],
  );

  /// منطق الحماية الكامل: مصادقة + تخويل حسب الدور.
  ///
  /// ⚠️ يعمل هذا الفحص على جهاز العميل فقط ولا يُعتبر بديلاً عن RLS
  /// بقاعدة البيانات. خط الدفاع الحقيقي هو Postgres RLS عبر `auth.jwt()`،
  /// الذي يتحقق من توقيع التوكن قبل الوثوق بأي claim بداخله.
  static String? _guardRedirect(
    BuildContext context,
    GoRouterState state,
  ) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoginRoute = state.matchedLocation == login;

    if (session == null) {
      return isLoginRoute ? null : login;
    }

    final role = JwtUtils.extractRole(session.accessToken);
    final isAuthorized = AuthorizationPolicy.isDashboardRole(role);

    if (kDebugMode) {
      debugPrint(
          '[Router] path=${state.matchedLocation} role="$role" authorized=$isAuthorized');
    }

    if (!isAuthorized) {
      return isLoginRoute ? null : login;
    }

    if (isLoginRoute) return dashboard;

    return null;
  }
}

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
}
