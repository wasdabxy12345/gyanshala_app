import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:gyanshala_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepositoryImpl(client);
});
