# Privacy Policy for Hyper Authenticator

Last updated: July 17, 2026

> Release note: this is an engineering-aligned draft, not legal advice. The project owner must review it for the laws, stores, regions, backend configuration, and product behavior of the actual release.

## Scope

This policy describes the data handled by the Hyper Authenticator client application and its password-recovery web page.

## Data handled

The current application requires a Supabase account. Depending on the features used, it handles:

- email address, authentication identifiers, and optional display name for registration and sign-in;
- authentication sessions managed by Supabase;
- authenticator account data, including issuer, account label, TOTP secret, algorithm, digits, and period;
- local preferences such as theme, biometric-lock status, remembered email, and sync status;
- camera frames or a selected image while decoding a QR code.

The Remember Me option stores the email address and checkbox state. It does not intentionally store the account password.

## Local processing and storage

Authenticator account records are stored through FlutterSecureStorage. Non-sensitive preferences are stored through SharedPreferences.

Camera frames and selected QR images are used to decode account data. The application does not intentionally upload the image itself as part of this flow. The decoded account data may be uploaded if the user enables and runs cloud sync.

Signing out currently clears the application secure-storage namespace, including locally stored authenticator accounts. This behavior is a known product issue and must be made explicit or changed before release.

## Cloud services

The application uses Supabase for:

- user registration, sign-in, session management, and password recovery;
- storage of synchronized authenticator account records.

Cloud sync is user-controlled from Settings, but Supabase authentication is currently required to enter the application.

Important: the current sync implementation does not apply client-side end-to-end encryption to TOTP secrets before upload. Data is protected in transit by the configured HTTPS service and by the deployed Supabase access controls, but authorized backend operators or a database compromise may be able to read synchronized secrets.

The separate password-recovery page may load the Supabase JavaScript client from a public CDN. Its production hosting and dependency policy must be documented before release.

## Sharing

Data is sent to Supabase when required for authentication, password recovery, or a user-triggered synchronization. The project does not intentionally sell personal information. Other disclosure obligations depend on the actual production infrastructure and must be reviewed by the project owner.

## Retention and deletion

Local authenticator records remain until deleted in the app, cleared by app storage behavior, or removed during sign-out under the current implementation. Cloud records remain according to the production Supabase database and account-retention configuration. The current client does not provide a complete self-service account-deletion flow.

## Security

No method of storage or transmission is risk-free. Before a production release, the project must complete the security blockers in docs/SECURITY.md, including end-to-end encryption for cloud secrets, tested RLS migrations, safe synchronization semantics, and data-loss protections.

## Changes and contact

This policy must be updated whenever authentication, analytics, logging, storage, synchronization, hosting, or third-party services change.

Project contact: xuancanhit99@gmail.com
