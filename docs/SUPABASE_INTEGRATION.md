# Supabase Integration

This document details how the Hyper Authenticator application integrates with Supabase for backend services, specifically Authentication and Database (for cloud synchronization).

## 1. Project Setup

*   A Supabase project is required for backend functionality.
*   The project's **URL** and **Anon Key** must be configured in a `.env` file at the root of the Flutter project, based on the `.env.example` template. These keys are used by the `supabase_flutter` package to initialize the connection.

```dotenv
# .env example
SUPABASE_URL=YOUR_SUPABASE_URL
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

*   The `SupabaseClient` instance is initialized (likely in `main.dart` or an injection module) and made available throughout the application via dependency injection (`GetIt`).

## 2. Supabase Authentication

*   **Purpose:** Manages user accounts (registration, login, logout, session management) to associate synchronized data with a specific user.
*   **Mechanism:** Primarily uses email and password authentication provided by `supabase_flutter`.
    *   `supabase.auth.signUp(email: ..., password: ...)`
    *   `supabase.auth.signInWithPassword(email: ..., password: ...)`
    *   `supabase.auth.signOut()`
    *   `supabase.auth.currentSession`, `supabase.auth.currentUser`
    *   `supabase.auth.onAuthStateChange` stream is listened to (likely by `AuthBloc`) to reactively update the application's authentication state.
*   **User Data:** Supabase automatically manages user data in the `auth.users` table. The application primarily uses the `id` and `email` from the `User` object provided by the client library.
*   **Password Reset:** Supabase Auth provides password reset functionality. The current implementation might leverage Supabase's built-in email templates or a custom solution (like the `reset-password-web` component included in the project).

## 3. Supabase Database

*   **Purpose:** Stores user account data (`AuthenticatorAccount`) securely when the cloud synchronization feature is enabled.
*   **Technology:** Supabase PostgreSQL database.
*   **Schema:**
    *   A primary table (e.g., `synced_accounts`) is used to store the account data.
    *   **Table: `synced_accounts`** (Refer to `DATA_MODELS.md` for DTO structure)
        *   `id` (uuid, primary key): Matches `AuthenticatorAccount.id`.
        *   `user_id` (uuid, foreign key -> `auth.users.id`): Links the account to the authenticated user. **Crucial for RLS.**
        *   `encrypted_data` (text): Stores the client-side encrypted account details (if E2EE is implemented). Alternatively, individual fields (`secret_key`, `issuer`, `account_name`, etc.) might be stored if E2EE is not yet active (less secure).
        *   `created_at` (timestamptz): Original creation timestamp from the client.
        *   `order_index` (integer): User-defined sort order.
        *   `updated_at` (timestamptz, default `now()`): Automatically managed by Supabase to track last modification.
*   **Data Access:**
    *   The `SyncRemoteDataSource` implementation in the Flutter app's Data Layer interacts with this table using the `supabase_flutter` client library.
    *   Operations include:
        *   Fetching accounts for the current user (`select().eq('user_id', currentUser.id)`).
        *   Uploading/Upserting accounts (`upsert([...])`).
        *   Deleting accounts (`delete().eq('id', accountId)`).

## 4. Row Level Security (RLS)

*   **CRITICAL:** RLS policies **must** be enabled on the `synced_accounts` table (and any other tables containing user data) to ensure users can only access their own data.
*   **Example Policies for `synced_accounts`:**
    *   **SELECT Policy:** Allow users to select rows where `user_id` matches their authenticated user ID.
        ```sql
        -- Policy name: Allow individual user select access
        CREATE POLICY "Allow individual user select access"
        ON public.synced_accounts
        FOR SELECT
        USING (auth.uid() = user_id);
        ```
    *   **INSERT Policy:** Allow users to insert rows where the `user_id` column matches their authenticated user ID.
        ```sql
        -- Policy name: Allow individual user insert access
        CREATE POLICY "Allow individual user insert access"
        ON public.synced_accounts
        FOR INSERT
        WITH CHECK (auth.uid() = user_id);
        ```
    *   **UPDATE Policy:** Allow users to update rows where `user_id` matches their authenticated user ID.
        ```sql
        -- Policy name: Allow individual user update access
        CREATE POLICY "Allow individual user update access"
        ON public.synced_accounts
        FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id); -- Optional: Re-check on update
        ```
    *   **DELETE Policy:** Allow users to delete rows where `user_id` matches their authenticated user ID.
        ```sql
        -- Policy name: Allow individual user delete access
        CREATE POLICY "Allow individual user delete access"
        ON public.synced_accounts
        FOR DELETE
        USING (auth.uid() = user_id);
        ```
*   **Verification:** RLS policies should be thoroughly tested using the Supabase SQL editor and by simulating requests from different users.

## 5. Supabase Functions (Edge Functions)

*   **Current Use:** As of the current design, there might not be a direct need for Supabase Edge Functions.
*   **Potential Future Use:** Could be used for:
    *   Sending custom emails (e.g., welcome emails, sync notifications) triggered by database changes (using webhooks or triggers).
    *   Performing complex server-side validation or operations if needed.
    *   Integrating with third-party services securely without exposing keys to the client.

## 6. Supabase Storage

*   **Current Use:** Not explicitly mentioned for core features in the current design documents.
*   **Potential Future Use:** Could potentially be used for storing user-uploaded custom icons for accounts, although this adds complexity.