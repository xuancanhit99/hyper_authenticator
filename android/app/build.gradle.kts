import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties relative to this build script (android/app/build.gradle.kts)
val keystorePropertiesFile = file("../key.properties") // Go up one level to android/
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    println("Warning: key.properties file not found at ${keystorePropertiesFile.absolutePath}")
}

android {
    namespace = "app.hyperz.authenticator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // Define signing configurations
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                // Resolve storeFile path relative to this build script's directory (android/app)
                // Path in properties (app/upload-keystore.jks) is relative to android/
                // So, go up one level ('../') then append the path from properties.
                storeFile = keystoreProperties["storeFile"]?.let { file("../${it}") }
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
            val releaseSigningConfig = signingConfigs.findByName("release")
            // Check if storeFile was successfully resolved and exists
            val storeFileResolved = releaseSigningConfig?.storeFile
            val storeFileExists = storeFileResolved?.exists() ?: false

            if (keystorePropertiesFile.exists() && storeFileExists) {
                signingConfig = releaseSigningConfig // Use the release config
            } else {
                // Print more detailed info for debugging
                println("Warning: Falling back to debug signing for release build.")
                println("  - key.properties found: ${keystorePropertiesFile.exists()} at ${keystorePropertiesFile.absolutePath}")
                println("  - storeFile path from properties: ${keystoreProperties["storeFile"]}")
                println("  - Resolved storeFile path: ${storeFileResolved?.absolutePath}")
                println("  - Resolved storeFile exists: ${storeFileExists}")
                signingConfig = signingConfigs.getByName("debug") // Fallback to debug
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

flutter {
    source = "../.."
}
