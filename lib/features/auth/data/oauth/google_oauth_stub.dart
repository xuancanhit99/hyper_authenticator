import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> startGoogleSignIn(SupabaseClient client) =>
    Future.error(UnsupportedError('Google sign-in is unavailable.'));
