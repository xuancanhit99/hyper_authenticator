# Architectural & Technological Decisions Justification

This document provides justifications for the key architectural and technological choices made during the development of the Hyper Authenticator application. It aims to compare the chosen solutions with alternatives and explain the reasoning behind the final decisions, relevant for academic analysis (e.g., Master's Thesis).

## 1. Choice of Cross-Platform Framework: Flutter

*   **Chosen:** Flutter
*   **Alternatives Considered:** React Native, Native Development (Kotlin/Swift), Xamarin, etc.
*   **Justification:**
    *   Single codebase for multiple platforms (Android, iOS, Web, Desktop) -> Reduced development time and cost.
    *   High performance (compiles to native code, Skia rendering engine).
    *   Rich widget library and strong community support.
    *   Hot reload/restart for faster development cycles.
    *   Suitable UI/UX consistency across platforms.
*   **Trade-offs:** App size might be larger than native; requires learning Dart.

## 2. Choice of Application Architecture: Clean Architecture

*   **Chosen:** Clean Architecture (Layers: Presentation, Domain, Data)
*   **Alternatives Considered:** MVVM (Model-View-ViewModel), MVC (Model-View-Controller), Simple Layered Architecture.
*   **Justification:**
    *   **Separation of Concerns:** Clear boundaries between UI, business logic, and data access.
    *   **Testability:** Layers can be tested independently (especially Domain and Data layers). Dependencies are injected.
    *   **Maintainability & Scalability:** Easier to modify or replace components (e.g., change state management, data source) without affecting other layers. Business logic is independent of frameworks.
    *   **Framework Independence:** Domain layer is independent of Flutter framework details.
*   **Trade-offs:** Can introduce more boilerplate code compared to simpler architectures; requires discipline to maintain layer boundaries.

## 3. Choice of State Management: BLoC / Cubit

*   **Chosen:** `flutter_bloc` (BLoC/Cubit) for primary state management, `provider` for Theme.
*   **Alternatives Considered:** Riverpod, GetX, Provider (for all state), Redux, MobX.
*   **Justification:**
    *   **Predictable State:** Clear separation of events, states, and business logic. Makes state changes predictable and traceable.
    *   **Testability:** `bloc_test` package provides excellent support for testing BLoCs/Cubits.
    *   **Scalability:** Suitable for complex applications with multiple features interacting.
    *   **Separation from UI:** Encourages separation of business logic from widget code.
    *   `Provider` is sufficient and simpler for dependency injection and simple state like theme management.
*   **Trade-offs:** Can have a steeper learning curve initially compared to Provider or GetX; might involve more boilerplate for simple state changes compared to Cubit/Provider.

## 4. Choice of Backend Service: Supabase

*   **Chosen:** Supabase (Backend-as-a-Service)
*   **Alternatives Considered:** Firebase, AWS Amplify, Custom Backend (e.g., Node.js/Python/Go with PostgreSQL), Appwrite.
*   **Justification:**
    *   **Open Source:** Based on open-source tools (PostgreSQL, GoTrue, etc.), reducing vendor lock-in compared to some alternatives.
    *   **Integrated Services:** Provides Authentication, Database (PostgreSQL with real-time), Storage, and Edge Functions in one platform.
    *   **PostgreSQL:** Powerful and familiar relational database. Row Level Security (RLS) provides fine-grained access control.
    *   **Generous Free Tier:** Suitable for development and small-scale deployment.
    *   **Flutter Client Library:** Well-maintained `supabase_flutter` package.
*   **Trade-offs:** Newer compared to Firebase; ecosystem might be less mature in some areas; scaling costs need consideration for large applications.

## 5. Choice of Local Storage

*   **Chosen:** `FlutterSecureStorage` (for sensitive data), `SharedPreferences` (for non-sensitive data).
*   **Alternatives Considered:** Hive, Moor/Drift (SQLite wrappers), File System.
*   **Justification:**
    *   **`FlutterSecureStorage`:** Leverages platform-specific secure storage (Keystore/Keychain) for maximum security of TOTP secrets. Essential for sensitive data.
    *   **`SharedPreferences`:** Simple key-value store, easy to use for basic settings like theme preference or feature flags. Sufficient for non-critical data.
    *   Using dedicated secure storage for secrets is a security best practice.
*   **Trade-offs:** `FlutterSecureStorage` access can be slightly slower than `SharedPreferences`; `SharedPreferences` is not suitable for sensitive data.

## 6. Choice of Biometric Authentication: `local_auth` Plugin

*   **Chosen:** `local_auth`
*   **Alternatives Considered:** Platform-specific native implementations (more complex).
*   **Justification:**
    *   Official Flutter Favorite plugin, providing a unified API for accessing native biometric (fingerprint, face ID) and device credential (PIN, pattern, password) authentication.
    *   Abstracts platform differences.
*   **Trade-offs & Security Considerations:**
    *   **Reliance on OS Security:** The plugin acts as a bridge to the native OS authentication mechanisms. Its security fundamentally depends on the security of the underlying platform (Android Keystore, iOS Secure Enclave, etc.) and the OS's implementation of biometric handling. Vulnerabilities in the OS could potentially compromise the authentication.
    *   **No Direct Biometric Access:** The plugin does *not* provide the application with raw biometric data (e.g., fingerprint image). It only returns a boolean success/failure status from the OS, which is a good security practice (least privilege).
    *   **Platform Inconsistencies:** Behavior and available options (e.g., specific biometric types, error messages, UI presentation) can vary significantly between Android versions, iOS versions, and different device manufacturers. Requires careful testing across target devices.
    *   **Rooted/Jailbroken Devices:** On compromised devices (rooted Android, jailbroken iOS), the OS-level security guarantees might be bypassed, potentially allowing attackers to tamper with the authentication mechanism or bypass the lock screen. Detecting rooted/jailbroken status is complex and often unreliable.
    *   **Fallback Mechanism:** Relies on the device's PIN/pattern/password as a fallback. The security of this fallback depends on the strength of the user's chosen credential.
    *   **Limited Context:** The plugin primarily confirms the *presence* of the authenticated user at the time of the check, but doesn't guarantee continuous presence or prevent the app from being backgrounded and later resumed by an unauthorized user if the OS lock screen isn't triggered immediately. (The app lifecycle listener helps mitigate this by re-prompting on resume).

*(This section should be expanded with more detailed comparisons and specific project constraints that influenced the decisions.)*