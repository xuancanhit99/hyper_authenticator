# Password-Recovery Web Page

This directory contains a static Supabase password-recovery page served by Nginx.

## Status

Incomplete and not deployable as committed.

- index.html loads the Supabase JavaScript v2 bundle from jsDelivr.
- script.js listens for a PASSWORD_RECOVERY session and calls auth.updateUser.
- SUPABASE_URL and SUPABASE_ANON_KEY are empty constants.
- compose.yml passes build arguments.
- Dockerfile does not declare or consume those arguments.
- No runtime env-config.js file is generated or loaded.

Do not deploy this page until one configuration path is implemented and tested.

## Intended flow

1. The mobile app requests a recovery email.
2. Supabase sends a link to an allowed recovery URL.
3. The page receives and validates the recovery session.
4. The user enters and confirms a new password.
5. The page calls Supabase auth.updateUser.
6. The page clears sensitive URL/session state and provides a safe completion message.

## Production requirements

- Choose this page or the Flutter /update-password route as the canonical recovery surface.
- Inject only the public Supabase URL and anon key.
- Never embed a service-role key.
- Pin or self-host external scripts and define a Content Security Policy.
- Remove session and user-object logging.
- Configure exact allowed redirect URLs per environment.
- Test successful, expired, malformed, replayed, and cross-environment links.
- Add rate-limit and abuse expectations.
- Add privacy, support, and incident contact links.
- Configure no-store caching where appropriate for recovery responses.

## Local development

The current Compose command is intentionally not documented as working. First implement and review configuration injection. Then document an environment-safe local command and an automated browser test in this file.

See:

- [Supabase Integration](../docs/SUPABASE_INTEGRATION.md)
- [Security Model](../docs/SECURITY.md)
- [Deployment Guide](../docs/DEPLOYMENT.md)
