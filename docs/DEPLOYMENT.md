# Deployment Notes

This document provides high-level notes and considerations for building and deploying the Hyper Authenticator application to its target platforms.

## 1. Prerequisites

*   Ensure Flutter SDK is correctly installed and configured for each target platform.
*   Platform-specific build tools are required (Android Studio/SDK, Xcode/Command Line Tools, Web build tools, Visual Studio for Windows, etc.).
*   Code signing certificates and provisioning profiles are necessary for iOS and macOS distribution.
*   Keystore file and credentials are needed for signing Android release builds.
*   Web server or hosting platform for deploying the web version.

## 2. General Build Commands

*   **Check Setup:** `flutter doctor`
*   **Clean Build:** `flutter clean`
*   **Get Dependencies:** `flutter pub get`
*   **Build Release:** (Specific commands per platform below)

## 3. Platform-Specific Deployment

### 3.1. Android

*   **Build Command:** `flutter build apk --release` or `flutter build appbundle --release` (Recommended for Google Play).
*   **Signing:** Requires a signing key (keystore). Configure signing in `android/app/build.gradle`. Refer to Flutter's official documentation for detailed steps on creating a keystore and configuring signing.
    *   Securely store your keystore file and passwords.
*   **Distribution:** Upload the signed APK or App Bundle (`.aab`) to Google Play Store or distribute manually.

### 3.2. iOS

*   **Build Command:** `flutter build ipa --release`
*   **Configuration:** Requires Xcode setup.
    *   Configure Bundle ID, version, build number in `ios/Runner.xcodeproj`.
    *   Set up code signing with an Apple Developer account (Certificates, Identifiers & Profiles). Xcode can often manage this automatically or manually configure signing settings.
*   **Distribution:**
    *   **TestFlight:** Archive the build in Xcode (`Product > Archive`) and upload to App Store Connect for internal/external testing.
    *   **App Store:** Submit the archived build through App Store Connect for review and release.

### 3.3. Web

*   **Build Command:** `flutter build web --release --web-renderer canvaskit` (CanvasKit recommended for performance and fidelity, but HTML renderer is an option: `--web-renderer html`).
*   **Output:** The build output will be in the `build/web` directory.
*   **Deployment:** Deploy the contents of the `build/web` directory to any static web hosting provider (e.g., Firebase Hosting, Netlify, Vercel, GitHub Pages, traditional web server).
    *   Ensure the server is configured correctly to handle single-page application routing (redirecting all paths to `index.html`).

### 3.4. Windows

*   **Build Command:** `flutter build windows --release`
*   **Output:** An executable and associated files will be generated in `build/windows/runner/Release`.
*   **Distribution:**
    *   Package the contents of the `Release` directory into an installer (e.g., using Inno Setup, NSIS) or distribute as a zipped archive.
    *   Consider code signing the executable for better user trust (requires a Windows code signing certificate).

### 3.5. macOS

*   **Build Command:** `flutter build macos --release`
*   **Output:** A `.app` bundle will be created in `build/macos/Build/Products/Release/`.
*   **Distribution:**
    *   **Code Signing & Notarization:** Essential for distribution outside the Mac App Store. Requires an Apple Developer ID certificate. Sign the app using `codesign` and submit for notarization using `altool`.
    *   **Mac App Store:** Configure the app in App Store Connect, archive using Xcode (`Product > Archive`), and submit for review.
    *   **Direct Distribution:** Distribute the signed and notarized `.app` bundle (often within a `.dmg` disk image).

## 4. Environment Variables (.env)

*   The `.env` file containing Supabase keys is **not** included in Git.
*   For CI/CD pipelines or build servers, ensure these environment variables (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) are securely injected during the build process. Flutter's `--dart-define-from-file` flag or specific CI/CD environment variable mechanisms can be used.

## 5. Versioning

*   Update the `version` number in `pubspec.yaml` (e.g., `1.0.0+1`) before building a release. The part before `+` is the public version name, and the part after `+` is the build number. Follow semantic versioning principles.