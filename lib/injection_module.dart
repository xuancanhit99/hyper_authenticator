import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// This module tells GetIt how to create instances of external dependencies
// that are needed by other injectable classes.
@module
abstract class RegisterModule {
  // Provides the SupabaseClient instance.
  // Assumes Supabase.initialize() has been called before GetIt setup.
  @lazySingleton
  SupabaseClient get supabaseClient => Supabase.instance.client;

  // Provides an http.Client instance.
  @lazySingleton
  http.Client get httpClient => http.Client();
}
