# Trusted TLS (Private CA)

This stack uses a private Certificate Authority (CA) to generate a TLS certificate for the ingress (Nginx).

Browsers and clients will *not* trust private certificates automatically. You must install the CA certificate on each device that will access the stack.

## What gets generated

After running the bootstrap (or `tools/generate-mtls-pki.sh`), you will have:

- `ssl/ca.pem` — the private CA certificate (safe to distribute)
- `ssl/cert.pem` + `ssl/key.pem` — ingress server certificate + key

Only the CA cert (`ssl/ca.pem`) needs to be installed on clients.

## Linux (Debian/Ubuntu) trust

Run:

- `sudo ./tools/install-ca-linux.sh`

This will:

- copy `ssl/ca.pem` into `/usr/local/share/ca-certificates/`
- run `update-ca-certificates`

After this, tools that use the system trust store (curl, Chrome, etc.) should trust `https://akula-prime.lan:8443`.

## Firefox note

Firefox may use its own certificate store.

Options:

- Enable `security.enterprise_roots.enabled=true` in `about:config`, OR
- Import the CA manually: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import `ssl/ca.pem`.

## macOS / iOS / Android

### macOS trust

- Install: `./tools/install-ca-macos.sh`
- Uninstall: `./tools/uninstall-ca-macos.sh`

This adds/removes the CA to/from the System keychain (requires admin).

### Windows trust

Run PowerShell as Administrator:

- Install: `./tools/install-ca-windows.ps1`
- Uninstall: `./tools/uninstall-ca-windows.ps1`

These add/remove the CA in `LocalMachine\Root`.

### iOS / Android

Install `ssl/ca.pem` as a trusted CA profile on the device. The exact steps differ by OS.

## Security notes

- Anyone who has your CA cert can trust certificates signed by it (which is fine).
- Anyone who has your CA **private key** can impersonate your services. Do not distribute the CA private key.
- For a “real” trust chain, use ACME/Let’s Encrypt with a public DNS name, or an internal CA integrated with your network.
