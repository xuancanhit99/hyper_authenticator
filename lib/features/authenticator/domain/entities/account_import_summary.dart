import 'package:equatable/equatable.dart';

/// Non-sensitive outcome of one atomic account import.
class AccountImportSummary extends Equatable {
  const AccountImportSummary({
    required this.importedCount,
    required this.duplicateCount,
  });

  final int importedCount;
  final int duplicateCount;

  @override
  List<Object?> get props => [importedCount, duplicateCount];
}
