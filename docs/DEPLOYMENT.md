# Deployment and Release Guide

The repository is not currently release-ready. This document defines gates; it does not certify that they pass.

## Release environments

Maintain separate development, test, staging, and production Supabase projects. Each environment needs:

- distinct client configuration;
- explicit redirect URLs;
- versioned schema and RLS migrations;
- isolated users and synthetic test data;
- documented owner and rollback plan.

Never distribute a service-role key.

## Global release gates

- All release blockers in PROJECT_STATUS.md and SECURITY.md resolved or explicitly accepted.
- Product name, bundle IDs, application ID, URLs, icons, and store metadata consistent.
- Explicit LICENSE file added.
- Privacy policy reviewed against actual behavior.
- No plaintext production TOTP secrets in Supabase.
- Atomic and recoverable sync.
- Local data is not silently removed on logout.
- RLS migrations and cross-user negative tests pass.
- Analyzer has no errors and no unexplained warnings.
- Unit, widget, and critical integration tests pass.
- Dependency and secret scans pass.
- Upgrade and rollback rehearsed.
- Release artifact is signed with production credentials.

## Versioning

Flutter version is defined in pubspec.yaml:

    version: major.minor.patch+build

Before release:

1. update the version;
2. update release notes;
3. confirm schema and encrypted-format compatibility;
4. tag the exact tested commit;
5. archive checksums and build provenance.

## Client configuration

The current build expects a root .env asset with SUPABASE_URL and SUPABASE_ANON_KEY.

Before standardizing deployment, accept an ADR for configuration injection. Requirements:

- deterministic per environment;
- no server secrets in artifacts;
- no manual post-build editing;
- environment visible in non-secret diagnostics;
- production builds cannot point to development by accident.

## Android

Build candidates:

    flutter build appbundle --release
    flutter build apk --release

Before distribution:

- remove debug-signing fallback for release;
- verify the resolved keystore and alias;
- inspect the merged release manifest;
- verify network, camera, biometric, and backup behavior;
- decide code shrinking and keep rules;
- upload native debug symbols as required;
- test install, upgrade, sign-in, TOTP, lock, sync, and recovery on representative API levels;
- complete Play data-safety declarations from actual behavior.

## iOS

Build candidate:

    flutter build ipa --release

Before distribution:

- verify bundle ID, team, signing, and provisioning;
- verify camera and Face ID descriptions;
- configure and test password-recovery universal links or custom schemes;
- test Keychain behavior across reinstall, logout, backup, and device restore;
- complete App Store privacy details from actual behavior;
- validate on physical devices and TestFlight.

## macOS

Build candidate:

    flutter build macos --release

Before distribution:

- configure network-client, camera, keychain, and local-auth sandbox entitlements;
- sign and notarize;
- test a hardened runtime artifact outside the development machine;
- verify plugin registration and secure-storage behavior.

## Web

Build candidate:

    flutter build web --release

Before distribution:

- remove or isolate unsupported platform imports;
- verify secure-storage semantics and document the browser threat model;
- configure SPA routing;
- set CSP, HSTS, referrer, permissions, and cache policies;
- pin and integrity-protect external scripts or self-host them;
- test auth redirects and recovery URLs;
- do not claim equivalent security to mobile without review.

## Windows and Linux

Runners exist but product support is unverified. Before release:

- verify every plugin;
- define installer, signing, update, secure storage, device-lock, and rollback behavior;
- add platform integration tests;
- update the public supported-platform matrix.

## Password-recovery web page

Before deploying reset-password-web:

- implement a public-client configuration injection mechanism;
- pin or self-host the Supabase JavaScript dependency;
- add CSP and other security headers;
- allow only production recovery redirects;
- disable caching of recovery pages and sensitive URL material where appropriate;
- test expired, malformed, reused, and successful sessions;
- remove verbose session logging;
- provide privacy and support links.

## Backend rollout

Every backend change requires:

1. migration ID and review;
2. backward/forward client compatibility;
3. staging rehearsal;
4. RLS negative tests;
5. backup or rollback;
6. monitoring without credential logging;
7. migration completion evidence.

E2EE rollout must follow E2EE_DESIGN.md and an accepted ADR.

## Rollback

Rollback must preserve the last valid local and remote snapshots. Never roll back to a client that cannot read the current encrypted or schema version without a compatibility plan.

Record:

- client versions affected;
- schema and format versions;
- safe downgrade path;
- data restoration steps;
- user communication;
- incident owner.

## Release evidence

Archive for every release:

- commit and tag;
- Flutter and Dart versions;
- dependency lockfile;
- generated-code verification;
- analyzer and test results;
- platform build logs;
- schema migration version and RLS test result;
- artifact hashes;
- signing identity reference, never private key material;
- approved privacy and store declarations.
