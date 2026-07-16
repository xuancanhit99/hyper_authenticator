# Hyper Authenticator

Hyper Authenticator is a Flutter application for storing TOTP accounts and generating RFC 6238 one-time passwords. The repository also contains Supabase authentication and cloud synchronization, device-credential app locking, QR import/export, and a small password-recovery web page.

> Project status: alpha. The local authenticator flow is implemented, but cloud synchronization is not end-to-end encrypted and the repository is not ready for production use. Read [Project Status](docs/PROJECT_STATUS.md) before using real 2FA secrets.

[Vietnamese overview](README.vi.md)

## Implemented

- Email/password registration and sign-in through Supabase.
- Add TOTP accounts by camera QR scan, gallery image, or manual entry.
- Generate SHA1, SHA256, or SHA512 TOTP codes with configurable digits and period.
- Search, edit, delete, copy, and export accounts as otpauth QR codes.
- Store account records in FlutterSecureStorage.
- Optional device biometric or device-credential lock.
- Light, dark, and system themes.
- Manual cloud merge or cloud overwrite through Supabase.

Some implemented paths still contain correctness or security defects. The authoritative list is in docs/PROJECT_STATUS.md.

## Architecture

The Flutter code is organized by feature and broadly follows Presentation, Domain, and Data layers:

    UI pages
      -> BLoCs
        -> use cases and repository contracts
          -> FlutterSecureStorage / SharedPreferences / Supabase

Start with:

- [Documentation map](docs/README.md)
- [System design](docs/SYSTEM_DESIGN.md)
- [Verified project status](docs/PROJECT_STATUS.md)
- [Security model](docs/SECURITY.md)
- [AI agent contract](AGENTS.md)

## Local setup

Prerequisites:

- Flutter stable with a Dart SDK compatible with pubspec.yaml.
- Platform tooling for the target device.
- A Supabase project for the current mandatory sign-in flow.

Setup:

    cp .env.example .env
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

The environment file must contain SUPABASE_URL and SUPABASE_ANON_KEY. It is ignored by Git but is currently bundled as a Flutter asset. Do not place a Supabase service-role key or any server secret in this file.

Run the repository harness before and after a change:

    scripts/agent/doctor.sh
    scripts/agent/check.sh quick

Use the full gate when the test baseline is available:

    scripts/agent/check.sh full

See [Development Guide](docs/DEVELOPMENT.md) and [Testing Strategy](docs/TESTING_STRATEGY.md) for details.

## Platforms

Flutter runners exist for Android, iOS, Web, Windows, macOS, and Linux. Presence of a runner does not mean a platform is release-ready. Android and iOS are the primary mobile targets; every other target requires explicit compatibility and security verification.

## Security notice

Cloud sync currently serializes TOTP secrets into Supabase rows without client-side encryption. Upload is implemented as delete-all followed by insert-all. Do not market the current sync as encrypted backup or use it with sensitive production accounts until the blockers in docs/SECURITY.md are resolved.

## Contributing

Read [Contributing](CONTRIBUTING.md). Significant architectural or security changes must update the relevant canonical document and add an ADR when the decision changes a long-lived contract.

## License

No license file is currently tracked. Do not assume reuse rights until the project owner adds an explicit license.
