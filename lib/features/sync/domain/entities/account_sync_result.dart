sealed class AccountSyncResult {
  const AccountSyncResult();
}

class AccountSyncSignedOut extends AccountSyncResult {
  const AccountSyncSignedOut();
}

class AccountSyncCompleted extends AccountSyncResult {
  const AccountSyncCompleted({
    required this.completedAt,
    required this.uploadedCount,
    required this.downloadedCount,
    required this.deletedCount,
    this.blockedAccountCount = 0,
  });

  final DateTime completedAt;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;

  /// Distinct local/cloud records retained unchanged with unsupported payloads.
  final int blockedAccountCount;
}
