import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsersRepository {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _client.from('users').select().inFilter(
        'role', ['admin', 'reception']).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> toggleUserStatus(String userId, bool isActive) async {
    await _invokeManageUser({
      'action': 'set_active',
      'user_id': userId,
      'is_active': isActive,
    });
  }

  Future<void> updateUserRole(String userId, String role) async {
    await _invokeManageUser({
      'action': 'set_role',
      'user_id': userId,
      'role': role,
    });
  }

  // Role/activation changes must go through the Edge Function: it also bans or
  // unbans the auth account, which a direct table update cannot do.
  Future<void> _invokeManageUser(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('manage-user', body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error']);
      }
      rethrow;
    }
  }

  Future<void> addUser({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    final response = await _client.functions.invoke(
      'create-trainee',
      body: {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
      },
    );

    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }
  }
}

final usersRepositoryProvider = Provider((_) => UsersRepository());

final usersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(usersRepositoryProvider).getUsers();
});
