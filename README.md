# Hyper Authenticator

**Repository:** [https://github.com/xuancanhit99/hyper_authenticator](https://github.com/xuancanhit99/hyper_authenticator)

A cross-platform Flutter application providing Time-based One-Time Password (TOTP) two-factor authentication (2FA). This project focuses on delivering a secure 2FA experience across multiple platforms (Android, iOS, Web, Windows, macOS) leveraging biometric technologies and offering optional secure cloud synchronization.

## Key Features
*   **Cross-Platform:** Designed to run on Android, iOS, Web, Windows, and macOS.
*   **TOTP Generation:** Implements the standard TOTP algorithm (RFC 6238) for generating time-based codes.
*   **Account Management:** Add accounts easily via:
    *   QR code scanning.
    *   Manual entry of secret keys.
    *   Selecting QR code images from the device gallery.
*   **Biometric App Lock:** Secure the application using device biometrics (fingerprint, face ID) or PIN via `local_auth`.
*   **Secure Cloud Sync (Optional):** Synchronize accounts across devices using Supabase backend. (End-to-end encryption is planned for future implementation).
*   **User Authentication:** Optional user accounts via Supabase for enabling sync features.
*   **Customizable UI:** Light and Dark mode support.
*   **Service Logo Recognition:** Displays logos for many common online services.

## Getting Started

### Prerequisites
*   Flutter SDK (version specified in `pubspec.yaml`)
*   Target platform setup (Android Studio, Xcode, Web browser, Windows/macOS desktop environment).
*   (Optional) A Supabase account for using sync and user authentication features.

### Installation
1.  Clone the repository: `git clone https://github.com/xuancanhit99/hyper_authenticator.git`
2.  Navigate to the project directory: `cd hyper_authenticator`
3.  Create a `.env` file from `.env.example` and fill in your Supabase URL and Anon Key if you plan to use backend features.
4.  Install dependencies: `flutter pub get`

### Running the App
*   Select your target device/platform.
*   Run the application: `flutter run`

## Technology Stack
*   **Framework:** Flutter (for cross-platform UI)
*   **Language:** Dart
*   **Architecture:** Clean Architecture
*   **State Management:** BLoC, Provider (for Theme)
*   **Dependency Injection:** GetIt, Injectable
*   **Routing:** GoRouter
*   **Backend:** Supabase (Auth, Database/Storage for Sync)
*   **Local Storage:** SharedPreferences (settings), FlutterSecureStorage (sensitive data like TOTP secrets)
*   **Local Authentication:** local_auth (Biometrics/PIN)
*   **QR Scanning/Analysis:** mobile_scanner
*   **TOTP Generation:** otp (Implements RFC 6238)
*   **Image Picking:** image_picker
*   **Encryption (Planned for Sync):** cryptography

## License
MIT License - Copyright (c) 2025 Hyper
