package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipher;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipherFactory;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class PreservationTest {
    private static StorageCipher xor(int mask) {
        return new StorageCipher() {
            public byte[] encrypt(byte[] input) { byte[] out = input.clone(); for (int i=0;i<out.length;i++) out[i] ^= mask; return out; }
            public byte[] decrypt(byte[] input) { return encrypt(input); }
            public void deleteKey(Context context) { fail("must retain the existing key"); }
        };
    }
    private static final StorageCipher BROKEN = new StorageCipher() {
        public byte[] encrypt(byte[] input) { return input; }
        public byte[] decrypt(byte[] input) throws Exception { throw new Exception("TEST_ONLY invalid key"); }
        public void deleteKey(Context context) { fail("must not delete key"); }
    };

    private void field(Object target, String name, Object value) throws Exception {
        Field f = target.getClass().getDeclaredField(name);
        f.setAccessible(true);
        f.set(target, value);
    }

    @Test public void failedReadAllPreservesCiphertextAcrossReopen() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        SharedPreferences prefs = context.getSharedPreferences("TEST_ONLY_ciphertext", 0);
        Map<String, Object> options = new HashMap<>();
        options.put("resetOnError", "false");
        FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);
        String key = config.getSharedPreferencesKeyPrefix() + "_test";
        prefs.edit().putString(key, "VEVTVF9PTkxZ").commit();
        Map<String, ?> before = prefs.getAll();
        for (int reopen = 0; reopen < 2; reopen++) {
            FlutterSecureStorage storage = new FlutterSecureStorage(context);
            field(storage, "config", config);
            field(storage, "preferences", prefs);
            field(storage, "storageCipher", BROKEN);
            try { storage.readAll(); fail("crypto failure must surface"); }
            catch (Exception expected) { assertEquals(before, prefs.getAll()); }
        }
    }

    @Test public void corruptBackupCannotBecomePartialSuccessfulMigration() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        SharedPreferences prefs = context.getSharedPreferences("TEST_ONLY_backup", 0);
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(new HashMap<>());
        field(storage, "config", config);
        String key = config.getSharedPreferencesKeyPrefix() + "_test_BACKUP";
        prefs.edit().putString(key, "VEVTVF9PTkxZ").commit();
        Map<String, ?> before = prefs.getAll();
        Method decode = FlutterSecureStorage.class.getDeclaredMethod(
            "decryptAllWithSavedCipherFromBackup", SharedPreferences.class, SharedPreferences.class, StorageCipher.class);
        decode.setAccessible(true);
        try { decode.invoke(storage, prefs, null, BROKEN); fail("must abort migration"); }
        catch (InvocationTargetException expected) { assertEquals(before, prefs.getAll()); }
    }

    @Test public void migrationVerificationRejectsMissingOrDamagedTarget() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        SharedPreferences prefs = context.getSharedPreferences("TEST_ONLY_target", 0);
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        Method verify = FlutterSecureStorage.class.getDeclaredMethod(
            "verifyMigratedData", Map.class, SharedPreferences.class, StorageCipher.class);
        verify.setAccessible(true);
        Map<String, String> expected = Map.of("test", "TEST_ONLY");
        try { verify.invoke(storage, expected, prefs, BROKEN); fail("must reject missing target"); }
        catch (InvocationTargetException e) { assertNotNull(e.getCause()); }
        prefs.edit().putString("test", Base64.encodeToString(new byte[]{1}, 0)).commit();
        try { verify.invoke(storage, expected, prefs, BROKEN); fail("must reject corrupt target"); }
        catch (InvocationTargetException e) { assertNotNull(e.getCause()); }
    }

    @Test public void storageAlgorithmOnlyMigrationKeepsEveryRecordAndCommitsTarget() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        Map<String, Object> options = new HashMap<>();
        options.put("storageNamespace", "TEST_ONLY_migration");
        options.put("resetOnError", "false");
        options.put("migrateWithBackup", "true");
        FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);
        SharedPreferences prefs = context.getSharedPreferences(config.getEffectiveDataPrefsName(), 0);
        NamespacedConfigSource source = new NamespacedConfigSource(context, config.getEffectiveDataPrefsName());
        StorageCipher oldCipher = xor(12), newCipher = xor(42);
        String key = config.getSharedPreferencesKeyPrefix() + "_test";
        prefs.edit().putString(key, Base64.encodeToString(oldCipher.encrypt("TEST_ONLY".getBytes()), 0)).commit();
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        field(storage, "config", config);
        field(storage, "storageCipherFactory", new StorageCipherFactory(source,
                config.getPrefOptionKeyCipherAlgorithm(), config.getPrefOptionStorageCipherAlgorithm(), config) {
            public boolean changedKeyAlgorithm() { return false; }
            public StorageCipher getSavedStorageCipher(Context c, javax.crypto.Cipher cipher) { return oldCipher; }
            public StorageCipher getCurrentStorageCipher(Context c, javax.crypto.Cipher cipher) { return newCipher; }
        });
        Method migrate = FlutterSecureStorage.class.getDeclaredMethod("migrateNonBiometricWithBackup",
            NamespacedConfigSource.class, SharedPreferences.class, SecurePreferencesCallback.class);
        migrate.setAccessible(true);
        boolean[] complete = {false};
        migrate.invoke(storage, source, prefs, new SecurePreferencesCallback<Void>() {
            public void onSuccess(Void ignored) { complete[0] = true; }
            public void onError(Exception error) { throw new AssertionError(error); }
        });
        assertTrue(complete[0]);
        assertEquals("TEST_ONLY", new String(newCipher.decrypt(Base64.decode(prefs.getString(key, null), 0))));
        assertFalse(prefs.contains(key + "_BACKUP"));
        assertFalse(source.getBoolean("HA_MIGRATION_VERIFIED", false));
    }

    @Test public void verifiedMigrationCanFinishInterruptedCleanupWithoutOldCipher() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        Map<String, Object> options = new HashMap<>();
        options.put("storageNamespace", "TEST_ONLY_cleanup");
        FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);
        SharedPreferences prefs = context.getSharedPreferences(config.getEffectiveDataPrefsName(), 0);
        NamespacedConfigSource source = new NamespacedConfigSource(context, config.getEffectiveDataPrefsName());
        String key = config.getSharedPreferencesKeyPrefix() + "_test";
        prefs.edit().putString(key, "TEST_ONLY_NEW").putString(key + "_BACKUP", "TEST_ONLY_OLD").commit();
        source.edit().putBoolean("HA_MIGRATION_VERIFIED", true).commit();
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        field(storage, "config", config);
        Method cleanup = FlutterSecureStorage.class.getDeclaredMethod("finishVerifiedMigration", NamespacedConfigSource.class, SharedPreferences.class);
        cleanup.setAccessible(true);
        cleanup.invoke(storage, source, prefs);
        assertEquals("TEST_ONLY_NEW", prefs.getString(key, null));
        assertFalse(prefs.contains(key + "_BACKUP"));
        assertFalse(source.getBoolean("HA_MIGRATION_VERIFIED", false));
    }
}
