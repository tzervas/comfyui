# Keycloak SSO (self-hosted, FOSS)

Okta is not a self-hosted FOSS IdP (it’s primarily SaaS). For a self-hosted OSS solution, this stack supports **Keycloak**.

## What you get
- A Keycloak instance behind Nginx at `/keycloak/`
- A pre-imported realm `comfyui`
- Baseline realm roles: `comfyui_admin`, `comfyui_user`
- Baseline groups: `comfyui-admins`, `comfyui-users`
- Baseline users: `admin`, `user1`, `user2` (passwords generated at bootstrap)
- oauth2-proxy configured to authenticate via the Keycloak realm

## Enable Keycloak profile
In `.env.single-node-gpu`:
- `KEYCLOAK_ENABLED=1`
- `SSO_ENABLED=1`
- `SSO_EMAIL_DOMAIN=local.lan` (optional)

Then run:
- `ENV_FILE=.env.single-node-gpu tools/bootstrap-single-node.sh`

## URLs
- Keycloak admin console: `https://<fqdn>:<port>/keycloak/admin/`
- Issuer URL: `https://<fqdn>:<port>/keycloak/realms/comfyui`

## Credentials
Bootstrap prints:
- Keycloak bootstrap admin (for the Keycloak admin console)
- Realm user passwords for `admin`, `user1`, `user2`
- oauth2-proxy client secret (stored in `.env.single-node-gpu`)

## Notes
- Password change (all users, first login): baseline users are configured with the required action `UPDATE_PASSWORD`, which forces them to set a new password immediately after first login.
- MFA (admins, first login): the baseline `admin` user is also configured with the required action `CONFIGURE_TOTP`, which forces a TOTP enrollment prompt on first login (no pre-provisioned seed).
- MFA (more admins): for any additional admin accounts you create, you can force the same behavior in the Keycloak UI:
	- Users → pick user → Required user actions → add `Configure OTP`
- If you want Keycloak reachable only on LAN/VPN, restrict ingress at firewall.
