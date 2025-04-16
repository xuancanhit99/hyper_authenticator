# Non-Functional Requirements (NFRs) Analysis

This document outlines key non-functional requirements for the Hyper Authenticator application and discusses how the chosen architecture and technologies aim to address them. This analysis is relevant for academic work like a Master's Thesis.

## 1. Security

*   **Requirement:** Protect sensitive user data (TOTP secrets) both locally and during optional cloud synchronization. Prevent unauthorized access to the application.
*   **Architectural Solution:**
    *   **Local Storage:** Use of `FlutterSecureStorage` leverages platform-native secure enclaves (Keystore/Keychain) for storing TOTP secrets.
    *   **App Lock:** Integration with `local_auth` provides device-level biometric/PIN protection against unauthorized app access.
    *   **Cloud Sync (Planned E2EE):** The planned client-side End-to-End Encryption ensures secrets are encrypted before leaving the device, making them unreadable by the backend provider (Supabase). Requires robust key management.
    *   **Cloud Sync (Transport & Auth):** HTTPS ensures secure data transmission. Supabase authentication and Row Level Security (RLS) restrict data access on the backend to authorized users.
    *   **Clean Architecture:** Separation of concerns helps isolate security-critical components.

## 2. Performance

*   **Requirement:** The application should feel responsive. TOTP code generation must be fast. UI interactions (scrolling, navigation) should be smooth. App startup time should be reasonable.
*   **Architectural Solution:**
    *   **Flutter:** Compiles to native code, generally offering good performance. Skia rendering engine provides smooth UI.
    *   **TOTP Generation:** The `otp` library performs calculations locally and quickly.
    *   **State Management (BLoC):** Efficient state updates, minimizing unnecessary widget rebuilds when implemented correctly.
    *   **Asynchronous Operations:** Use of `async/await` and background processing (e.g., for sync) prevents blocking the UI thread.
    *   **Web Renderer:** Choice between CanvasKit (better performance/fidelity) and HTML (smaller initial load size) allows optimization for web deployment.
    *   **Code Optimization:** Standard Dart/Flutter optimization practices (e.g., `const` widgets, efficient list building).

## 3. Reliability / Availability

*   **Requirement:** The application must reliably generate correct TOTP codes. Core functionality should work offline. Optional sync features depend on backend availability but should handle failures gracefully.
*   **Architectural Solution:**
    *   **Offline-First Core:** TOTP generation and account storage are entirely local, ensuring core functionality works without network access.
    *   **Error Handling:** Use of `Either<Failure, SuccessType>` allows graceful handling of expected errors (network issues, storage errors, etc.) without crashing the app. Specific `Failure` types allow targeted error reporting/recovery.
    *   **Testing:** Comprehensive testing strategy (Unit, Widget, Integration) helps catch bugs and ensure reliability.
    *   **Supabase Availability:** Relies on Supabase's SLA for sync/auth features. The app should clearly indicate sync status and handle backend unavailability (e.g., show cached data, disable sync actions).

## 4. Usability

*   **Requirement:** The application should be intuitive and easy to use for adding accounts, viewing codes, and managing settings. Biometric login should be seamless.
*   **Architectural Solution:**
    *   **Flutter:** Provides tools for building modern, user-friendly interfaces.
    *   **Presentation Layer:** Dedicated layer for UI and user interaction logic. BLoC helps manage UI state clearly.
    *   **`local_auth`:** Provides a standard, familiar interface for biometric/PIN authentication.
    *   **QR Code Scanning/Image Picking:** Simplifies account addition using `mobile_scanner` and `image_picker`.
    *   **GoRouter:** Enables clear navigation flows.

## 5. Maintainability

*   **Requirement:** The codebase should be easy to understand, modify, and extend over time. Bugs should be relatively easy to locate and fix.
*   **Architectural Solution:**
    *   **Clean Architecture:** Strong separation of concerns is the primary driver for maintainability. Changes in one layer have minimal impact on others.
    *   **Modularity:** Feature-based directory structure (`auth`, `authenticator`, `sync`, `settings`).
    *   **Dependency Injection (`GetIt`/`Injectable`):** Reduces coupling between components, making them easier to replace or modify.
    *   **State Management (BLoC):** Clear state transition logic makes debugging easier.
    *   **Testing:** A good test suite makes refactoring safer and helps document component behavior.
    *   **Code Conventions:** Consistent coding style (enforced by `analysis_options.yaml`).

## 6. Portability / Cross-Platform Compatibility

*   **Requirement:** The application must run consistently across target platforms (Android, iOS, Web, Windows, macOS).
*   **Architectural Solution:**
    *   **Flutter:** Designed specifically for cross-platform development from a single codebase.
    *   **Plugin Abstraction:** Platform-specific features (like biometrics, secure storage) are accessed via plugins (`local_auth`, `flutter_secure_storage`) that abstract away native differences.
    *   **Responsive UI:** Flutter's layout system allows building UIs that adapt to different screen sizes and orientations.

## 7. Scalability

*   **Requirement:** (Primarily for Sync Feature) The backend should handle a growing number of users and synchronized accounts. The client app architecture should support adding new features.
*   **Architectural Solution:**
    *   **Supabase:** As a BaaS, Supabase is designed to scale. Its PostgreSQL backend can handle significant load (scaling plans available).
    *   **Clean Architecture:** Makes adding new features (new layers/modules) or modifying existing ones more manageable without disrupting the entire application.
    *   **RLS:** Efficiently filters data on the backend, reducing load.

*(This section provides a starting point. A full NFR analysis in a thesis would likely involve more specific metrics and deeper discussion.)*