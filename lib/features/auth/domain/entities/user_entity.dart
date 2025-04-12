// lib/features/auth/domain/entities/user_entity.dart
import 'package:equatable/equatable.dart';
// Add Supabase User import temporarily for the factory constructor
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class UserEntity extends Equatable {
  final String id;
  final String? email;
  // final String? displayName; // Example: Add if needed

  const UserEntity({
    required this.id,
    this.email,
    // this.displayName, // Example
  });

  // Optional: Factory constructor for easy mapping from Supabase User
  factory UserEntity.fromSupabaseUser(User supabaseUser) {
    return UserEntity(
      id: supabaseUser.id,
      email: supabaseUser.email,
      // displayName: supabaseUser.userMetadata?['display_name'], // Example
    );
  }


  @override
  List<Object?> get props => [id, email /*, displayName */];
}