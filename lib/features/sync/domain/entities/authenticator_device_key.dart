import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';

enum AuthenticatorDeviceKeyState { pending, wrapped, active }

class AuthenticatorDeviceKey extends Equatable {
  final String deviceKeyId;
  final String installationId;
  final Uint8List publicKeyBytes;
  final AuthenticatorDeviceKeyState state;
  final DateTime createdAt;
  final DateTime? wrappedAt;
  final DateTime? activatedAt;
  final bool isCurrent;
  final DeviceWrappedVaultKey? wrappedVaultKey;
  final String? membershipProof;

  AuthenticatorDeviceKey({
    required this.deviceKeyId,
    required this.installationId,
    required List<int> publicKeyBytes,
    required this.state,
    required this.createdAt,
    required this.wrappedAt,
    required this.activatedAt,
    required this.isCurrent,
    required this.wrappedVaultKey,
    required this.membershipProof,
  }) : publicKeyBytes = Uint8List.fromList(publicKeyBytes);

  int? get keyGeneration => wrappedVaultKey?.keyGeneration;

  @override
  List<Object?> get props => <Object?>[
    deviceKeyId,
    installationId,
    publicKeyBytes,
    state,
    createdAt,
    wrappedAt,
    activatedAt,
    isCurrent,
    wrappedVaultKey,
    membershipProof,
  ];

  @override
  String toString() =>
      'AuthenticatorDeviceKey(state: ${state.name}, current: $isCurrent, '
      'generation: $keyGeneration, <redacted>)';
}

class DeviceKeyEnrollment extends Equatable {
  final String deviceKeyId;
  final AuthenticatorDeviceKeyState state;
  final int keyGeneration;

  const DeviceKeyEnrollment({
    required this.deviceKeyId,
    required this.state,
    required this.keyGeneration,
  });

  @override
  List<Object?> get props => <Object?>[deviceKeyId, state, keyGeneration];

  @override
  String toString() =>
      'DeviceKeyEnrollment(state: ${state.name}, '
      'generation: $keyGeneration, <redacted>)';
}

class ActiveDeviceKeyAuthorization {
  final AuthenticatorDeviceKey deviceKey;
  final Uint8List bindingSecretBytes;

  ActiveDeviceKeyAuthorization({
    required this.deviceKey,
    required List<int> bindingSecretBytes,
  }) : bindingSecretBytes = Uint8List.fromList(bindingSecretBytes);

  @override
  String toString() =>
      'ActiveDeviceKeyAuthorization(generation: '
      '${deviceKey.keyGeneration}, <redacted>)';
}

class DeviceKeyRotationWrap {
  final String deviceKeyId;
  final DeviceWrappedVaultKey wrappedVaultKey;
  final String membershipProof;

  const DeviceKeyRotationWrap({
    required this.deviceKeyId,
    required this.wrappedVaultKey,
    required this.membershipProof,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'device_key_id': deviceKeyId,
    ...wrappedVaultKey.toJson(),
    'membership_proof': membershipProof,
  };

  @override
  String toString() =>
      'DeviceKeyRotationWrap(generation: '
      '${wrappedVaultKey.keyGeneration}, <redacted>)';
}

class DeviceKeyRotationPlan {
  final Uint8List bindingSecretBytes;
  final String nextVaultMembershipVerifier;
  final List<DeviceKeyRotationWrap> wraps;

  DeviceKeyRotationPlan({
    required List<int> bindingSecretBytes,
    required this.nextVaultMembershipVerifier,
    required List<DeviceKeyRotationWrap> wraps,
  }) : bindingSecretBytes = Uint8List.fromList(bindingSecretBytes),
       wraps = List<DeviceKeyRotationWrap>.unmodifiable(wraps);

  @override
  String toString() =>
      'DeviceKeyRotationPlan(wraps: ${wraps.length}, <redacted>)';
}
