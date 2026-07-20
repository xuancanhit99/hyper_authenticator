import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties relative to this build script (android/app/build.gradle.kts)
val keystorePropertiesFile = file("../key.properties") // Go up one level to android/
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(propertyName: String, environmentName: String): String? =
    keystoreProperties[propertyName]
        ?.toString()
        ?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseStorePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
val releaseStoreFile = releaseStorePath?.let { rootProject.file(it) }
val hasReleaseSigningConfig =
    releaseStoreFile?.exists() == true &&
    listOf(releaseKeyAlias, releaseKeyPassword, releaseStorePassword).all {
        !it.isNullOrBlank()
    }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "app.hyperz.authenticator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Define signing configurations
    signingConfigs {
        create("release") {
            if (hasReleaseSigningConfig) {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.hyperz.authenticator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            } else if (releaseTaskRequested) {
                throw GradleException(
                    "Android release signing chưa được cấu hình đầy đủ. " +
                        "Dùng android/key.properties hoặc ANDROID_KEYSTORE_PATH/" +
                        "ANDROID_KEY_ALIAS/ANDROID_KEY_PASSWORD/ANDROID_STORE_PASSWORD. " +
                        "Release build bị dừng để tránh tạo artifact debug-signed hoặc unsigned.",
                )
            }
            // Re-add: Include native debug symbols in the release build
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE" // Or "FULL" for more detailed symbols
            }
            // You might also want to add other release configurations like ProGuard/R8 here
            // minifyEnabled = true
            // shrinkResources = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
