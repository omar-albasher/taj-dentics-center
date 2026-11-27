import 'package:supabase_flutter/supabase_flutter.dart';

typedef EdgeFunctionInvoke = Future<dynamic> Function(
    String functionName, Map<String, dynamic> body);

/// الافتراضي: يستدعي Edge Function ويعيد `data` فقط، ليبقى قابلاً للحقن في الاختبارات.
Future<dynamic> defaultEdgeFunctionInvoke(
    String functionName, Map<String, dynamic> body) async {
  final response =
      await Supabase.instance.client.functions.invoke(functionName, body: body);
  return response.data;
}
