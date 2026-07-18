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

val releaseStoreFile = keystoreProperties["storeFile"]
    ?.toString()
    ?.takeIf { it.isNotBlank() }
    ?.let { file("../$it") }
val hasReleaseSigningConfig =
    keystorePropertiesFile.exists() &&
    releaseStoreFile?.exists() == true &&
    listOf("keyAlias", "keyPassword", "storePassword").all {
        !keystoreProperties[it]?.toString().isNullOrBlank()
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
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                // Resolve storeFile path relative to this build script's directory (android/app)
                // Path in properties (app/upload-keystore.jks) is relative to android/
                // So, go up one level ('../') then append the path from properties.
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String?
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
