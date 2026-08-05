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
  });

  final DateTime completedAt;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;
}
