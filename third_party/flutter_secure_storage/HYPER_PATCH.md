# Hyper Authenticator preservation patch

Vendored from pub.dev flutter_secure_storage 10.3.1 (BSD license in LICENSE).
Federated desktop/Apple/Web implementations remain the pinned pub dependencies.

Android options preserve the existing namespace and algorithms, disable
resetOnError, and enable migration backup. No change to biometric key policy.
Upstream's backup decryption skipped corrupt entries and then removed the backup;
this copy aborts instead, verifies all re-encrypted records before cleanup, and
checks migration commits. Non-biometric migration always backs up (including a
storage-only algorithm change), retries from the complete original backup and
atomically publishes algorithm markers plus a verified-target flag. Initialization
finishes interrupted cleanup before exposing reads. Errors retain recovery material and surface
through the storage failure boundary. Never advise users to reset storage to
recover from crypto errors. An invalidated Keystore key remains unrecoverable
without an independent backup; preserving ciphertext does not recreate that key.

Regression: Android Robolectric PreservationTest; Dart plugin option test and
local datasource read-failure tests. Do not replace this path dependency with an
unpatched release until equivalent behavior is verified.

Five upstream public storage-identifier/algorithm constants carry line-scoped
gitleaks allow comments. These names are not key material; secret scanning stays
enabled for the rest of the vendored implementation. Imported text line endings
and trailing whitespace are normalized without changing runtime behavior.
