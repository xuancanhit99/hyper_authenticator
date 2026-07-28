package app.hyperz.authenticator

import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var backupChannel: MethodChannel? = null
    private var pendingBackupBytes: ByteArray? = null
    private var pendingBackupResult: MethodChannel.Result? = null

    private val createBackupDocument =
        registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri ->
            completeBackupSave(uri)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                BACKUP_CHANNEL,
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method != "saveEncryptedBackup") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    startBackupSave(
                        bytes = call.argument<ByteArray>("bytes"),
                        suggestedName = call.argument<String>("suggestedName"),
                        result = result,
                    )
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backupChannel?.setMethodCallHandler(null)
        backupChannel = null
        clearPendingBackup()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun startBackupSave(
        bytes: ByteArray?,
        suggestedName: String?,
        result: MethodChannel.Result,
    ) {
        if (pendingBackupResult != null) {
            result.error(
                "BACKUP_SAVE_BUSY",
                "Một document picker khác đang mở.",
                null,
            )
            return
        }
        if (bytes == null || bytes.isEmpty() || suggestedName.isNullOrBlank()) {
            bytes?.fill(0)
            result.error(
                "INVALID_BACKUP",
                "Dữ liệu hoặc tên file backup không hợp lệ.",
                null,
            )
            return
        }

        pendingBackupBytes = bytes
        pendingBackupResult = result
        try {
            createBackupDocument.launch(suggestedName)
        } catch (error: Exception) {
            clearPendingBackup()
            result.error(
                "BACKUP_PICKER_UNAVAILABLE",
                "Không thể mở Android document picker.",
                null,
            )
        }
    }

    private fun completeBackupSave(uri: Uri?) {
        val result = pendingBackupResult ?: return
        val bytes = pendingBackupBytes
        pendingBackupResult = null
        pendingBackupBytes = null

        if (uri == null) {
            bytes?.fill(0)
            result.success("cancelled")
            return
        }
        if (bytes == null) {
            result.error(
                "BACKUP_DATA_MISSING",
                "Dữ liệu backup không còn khả dụng.",
                null,
            )
            return
        }

        try {
            contentResolver.openOutputStream(uri, "w").use { stream ->
                requireNotNull(stream) {
                    "Không thể mở output stream cho document đã chọn."
                }
                stream.write(bytes)
                stream.flush()
            }
            result.success("saved")
        } catch (error: Exception) {
            result.error(
                "BACKUP_WRITE_FAILED",
                "Không thể ghi file backup vào vị trí đã chọn.",
                null,
            )
        } finally {
            bytes.fill(0)
        }
    }

    private fun clearPendingBackup() {
        pendingBackupBytes?.fill(0)
        pendingBackupBytes = null
        pendingBackupResult = null
    }

    private companion object {
        const val BACKUP_CHANNEL =
            "app.hyperz.authenticator/encrypted_backup"
    }
}
