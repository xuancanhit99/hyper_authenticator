# Development Guide

## Prerequisites

- Flutter stable and a Dart SDK compatible with pubspec.yaml.
- Git.
- Platform toolchain for the selected target.
- A non-production Supabase project for the current sign-in flow.
- CocoaPods for current iOS and macOS plugin integration.

Check the machine:

    flutter doctor -v
    flutter --version
    dart --version
    scripts/agent/doctor.sh

## First setup

1. Create local client configuration:

       cp .env.example .env

2. Set placeholder-safe development values:

       SUPABASE_URL=https://your-development-project.invalid
       SUPABASE_ANON_KEY=your-development-anon-key

3. Fetch dependencies:

       flutter pub get

4. Generate Injectable registrations after dependency-annotation changes:

       dart run build_runner build --delete-conflicting-outputs

5. Select a device and run:

       flutter devices
       flutter run

Never place a service-role key, database password, SMTP credential, TOTP secret, or real user token in .env.

## Daily workflow

Before editing:

    git status --short --branch
    scripts/agent/context.sh
    scripts/agent/check.sh docs

After documentation-only changes:

    scripts/agent/check.sh docs

After Dart changes:

    dart format lib test
    scripts/agent/check.sh quick

After auth, storage, sync, routing, DI, plugin, or platform changes:

    scripts/agent/check.sh full

Also run the affected platform build or test and record the result.

## Repository structure

    lib/
      main.dart
      app.dart
      injection_container.dart
      core/
      features/
    assets/
    docs/
    scripts/agent/
    test/
    reset-password-web/
    android/
    ios/
    macos/
    web/
    windows/
    linux/

Generated file:

- lib/injection_container.config.dart

Do not hand-edit generated output. Modify annotations or modules and regenerate.

## Common change paths

### Add or change an account field

Update:

1. AuthenticatorAccount constructor, equality, toJson, and fromJson.
2. Add/update use-case parameters.
3. Local data-source round trip.
4. Sync serialization and remote migration.
5. Import, edit, export, and display UI.
6. Tests for legacy and current formats.
7. DATA_MODELS.md and SUPABASE_INTEGRATION.md.

### Add a route

Update AppRoutes and AppRouter, define public/protected behavior, add redirect tests, and document the route in SYSTEM_DESIGN.md.

### Change dependency injection

1. Change annotations or RegisterModule.
2. Regenerate Injectable output.
3. Verify lifecycle: factory, lazy singleton, or shared provider.
4. Add a test when instance identity affects behavior.

### Change sync

Start with SECURITY.md and SUPABASE_INTEGRATION.md. Define idempotency, conflict behavior, deletion propagation, migration, and rollback before implementation.

## Local configuration model

The current app loads .env at runtime as a Flutter asset. That makes the file mandatory for asset-bundle construction and places client configuration into the built application.

This is acceptable only for public client configuration such as an anon key. It is not a secret-delivery mechanism. The long-term strategy is an open architectural decision.

## Platform notes

### Android

- Application ID: app.hyperz.authenticator.
- Release signing currently falls back to debug signing when the release key is unavailable; do not distribute that artifact.
- Verify INTERNET, camera, biometric, backup, and secure-storage behavior in the merged release manifest.

### iOS

- Verify bundle ID and signing in Xcode.
- Camera and Face ID usage descriptions exist.
- Password-recovery URL handling still needs a canonical deep-link configuration.

### macOS

- Verify sandbox network client, camera, keychain, and local-auth entitlements.
- Do not infer readiness from successful CocoaPods installation.

### Web and desktop

- Verify every plugin on the target.
- Remove or conditionally isolate unsupported dart:io imports for Web.
- Document the browser storage and threat model before claiming secure Web support.

## Password-recovery web page

The static page is separate from the Flutter Web app.

Run it only after implementing a safe public-client configuration injection path. Current Compose build arguments are not consumed by the Dockerfile.

Do not bake server secrets into script.js or an Nginx image.

## Debugging without leaking credentials

- Redact values after secret= in otpauth URIs.
- Log account IDs only when necessary; prefer an irreversible short fingerprint for correlation.
- Do not log emails by default.
- Do not print auth responses, sessions, encryption keys, salts, or full exceptions containing request data.
- Use synthetic accounts and invalid example domains.

## Cleaning and regeneration

Use clean only when diagnosing generated or build-cache problems:

    flutter clean
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs

Cleaning is not a substitute for understanding a build failure. Preserve unrelated platform changes in a dirty worktree.
