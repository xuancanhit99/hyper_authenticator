import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_oauth_stub.dart'
    if (dart.library.io) 'google_oauth_io.dart'
    if (dart.library.js_interop) 'google_oauth_web.dart'
    as platform;

Future<void> startGoogleSignIn(SupabaseClient client) =>
    platform.startGoogleSignIn(client);
