# SSO: first-time access vs baseline users

This stack uses **oauth2-proxy** in front of Nginx (`auth_request`) for OAuth/OIDC SSO.

For a self-hosted FOSS IdP, use **Keycloak** (see `docs/keycloak-sso.md`).

There are two supported onboarding modes:

## 1) First-time access (open login)
- Anyone who can authenticate with your IdP is allowed through (subject to optional `email_domains`).
- **User registration happens at your IdP** (Keycloak/Authentik/AzureAD/etc). If your IdP supports self-service signup, that covers “first time use registration”.

Defaults (open mode):
- `email_domains = ["*"]` (any email)

## 2) Baseline users (explicit allowlist)
- Only specific emails are allowed to log in.
- Configure the allowlist by setting `SSO_ALLOWED_EMAILS` and re-running bootstrap.

If you enable Keycloak via `KEYCLOAK_ENABLED=1`, bootstrap will default the allowlist
to `admin@<domain>,user1@<domain>,user2@<domain>` unless you override it.

### Configure baseline allowlist
In `.env.single-node-gpu`:
- `SSO_ALLOWED_EMAILS=admin@example.com,user1@example.com`

Then run:
- `ENV_FILE=.env.single-node-gpu tools/bootstrap-single-node.sh`

This will:
- Write `config/oauth2-proxy/allowed_emails.txt`
- Enable `authenticated_emails_file` in `config/oauth2-proxy/oauth2-proxy.cfg`

## Notes
- You can also restrict by domain using oauth2-proxy `email_domains`.
- For group-based allow, oauth2-proxy supports `allowed_groups` when your IdP provides a groups claim.
