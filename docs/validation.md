# Stack validation

This repo includes an API/CLI validation harness intended for **deployed stacks** (homelab ingress, single-node GPU, or desktop worker).

## API/Ingress validation (preferred)

Runs probes through Nginx (basic-auth, TLS, registry secret, optional mTLS, and basic multimodal checks for Ollama).

- Single-node GPU:

```bash
./tools/tests/validate-stack.sh --env-file .env.single-node-gpu
```

- Homelab:

```bash
./tools/tests/validate-stack.sh --env-file .env.homelab
```

- Custom URL:

```bash
./tools/tests/validate-stack.sh --base-url https://homelab.lan:8443
```

Environment overrides:
- `BASIC_AUTH_USER`, `BASIC_AUTH_PASS` (defaults `admin/admin`)
- `CURL_INSECURE=1` (default) to allow self-signed TLS
- `OLLAMA_TEST_MODEL` (optional)
- `OLLAMA_VISION_TEST_MODEL` (optional)
- `REGISTRY_SECRET` (required to validate `/discover`)
- `MTLS_VERIFY=off|optional|on` and optional `REGISTRY_MTLS_CA`, `REGISTRY_MTLS_CERT`, `REGISTRY_MTLS_KEY`

## CLI validation

Execs into containers and checks basic CLI functionality.

```bash
./tools/tests/validate-cli.sh -f docker-compose.single-node-gpu.yml --env-file .env.single-node-gpu
```

## Notes

- ComfyUI deep workflow execution is **model-dependent**. The harness validates UI and lightweight introspection (`/object_info`) without requiring checkpoint downloads.
- Ollama vision checks are only run if `OLLAMA_VISION_TEST_MODEL` is set and pulled.
