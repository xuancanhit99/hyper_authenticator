// lib/features/auth/domain/entities/user_entity.dart
import 'package:equatable/equatable.dart';
// Add Supabase User import temporarily for the factory constructor
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class UserEntity extends Equatable {
  final String id;
  final String? email;
  final String? name; // Add name field

  const UserEntity({
    required this.id,
    this.email,
    this.name, // Add to constructor
  });

  // Optional: Factory constructor for easy mapping from Supabase User
  factory UserEntity.fromSupabaseUser(User supabaseUser) {
    return UserEntity(
      id: supabaseUser.id,
      email: supabaseUser.email,
      name:
          supabaseUser.userMetadata?['name']
              as String?, // Extract name from metadata
    );
  }

  @override
  List<Object?> get props => [id, email, name]; // Add name to props
}
