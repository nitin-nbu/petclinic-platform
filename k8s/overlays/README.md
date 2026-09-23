# Environment Overlays

Kustomize overlays on top of `k8s/base/` (PETPLAT-45, PETPLAT-46, PETPLAT-47).
See `k8s/base/README.md` for the placeholders each overlay's `images:`
transformer needs rendered with `envsubst`.

| Overlay | Namespace | Replicas | HPA |
|---------|-----------|----------|-----|
| `dev/` | `petclinic-dev` | 1 (all services) | none |
| `prod/` | `petclinic-prod` | 2 (config-server, discovery-server, api-gateway, customers/visits/vets-service), 1 (genai-service, admin-server) | api-gateway (2-6), customers/visits/vets-service (2-4 each), genai-service (1-3) — all at 70% CPU target |

Prod HPA requires the cluster Metrics Server (PETPLAT-72) — outside the
scope of these manifests.

## Validate

```bash
kubectl apply --dry-run=client -k k8s/overlays/dev
kubectl apply --dry-run=client -k k8s/overlays/prod
```

(Passes even before `envsubst` rendering — the `${AWS_ACCOUNT_ID}` /
`${IMAGE_TAG}` / `${RDS_ENDPOINT}` placeholders are syntactically valid
strings; client-side dry-run only checks schema, not registry/DNS
resolvability.)

## Apply

See the "Rendering and applying" section in `k8s/base/README.md` — the
overlay path (`k8s/overlays/${ENV}`) is what gets rendered and applied, not
`k8s/base` directly.
