# Base Application Manifests

Deployment, Service, ConfigMap, and ServiceAccount for all 8 microservices
(PETPLAT-38 through PETPLAT-44). Environment-agnostic — `k8s/overlays/{dev,prod}/`
patch replica counts, namespace, and image references on top of this base.

## Contents

| Path | Story |
|------|-------|
| `namespaces.yaml` | PETPLAT-38 — `petclinic-dev` and `petclinic-prod` Namespaces |
| `config-server/` | PETPLAT-39 |
| `discovery-server/` | PETPLAT-40 |
| `customers-service/`, `visits-service/`, `vets-service/` | PETPLAT-41 |
| `genai-service/` | PETPLAT-42 |
| `api-gateway/` | PETPLAT-43 |
| `admin-server/` | PETPLAT-44 |

`namespaces.yaml` is applied directly (once per cluster) — it is **not** part
of `kustomization.yaml` in this directory, since Namespace objects are
cluster-scoped and shouldn't go through an overlay's `namespace:` transformer:

```bash
kubectl apply -f k8s/base/namespaces.yaml
```

## Startup order (PETPLAT-39/40)

Config Server → Discovery Server → everything else, enforced with
`busybox:1.36` init containers that poll `/actuator/health` in a wget loop
(technical-spec.md#kubernetes-manifests):

| Service | waits for config-server | waits for discovery-server |
|---------|:---:|:---:|
| config-server | — | — |
| discovery-server | ✓ | — |
| api-gateway, customers-service, visits-service, vets-service, genai-service, admin-server | ✓ | ✓ |

customers-service must additionally be deployed before visits-service
(FK dependency: `visits.pet_id` → `pets.id`) — this is a deploy-order
concern, not an init-container check (technical-spec.md#rds-database).

## Placeholders

Two values are intentionally left as `envsubst`-style placeholders, same
pattern as `k8s/base/ingress/` and `k8s/base/external-secrets/`:

| Placeholder | Where | Source |
|-------------|-------|--------|
| `${RDS_ENDPOINT}` | `customers-service/configmap.yaml`, `visits-service/configmap.yaml`, `vets-service/configmap.yaml` | `rds` Terraform module output (`endpoint`) |
| `${AWS_ACCOUNT_ID}` / `${IMAGE_TAG}` | `k8s/overlays/{dev,prod}/kustomization.yaml` (`images:` transformer) | AWS account, CI-built commit SHA |

Base `image:` fields use an inert placeholder (`petclinic/{service}:0.0.0-placeholder`)
that the overlays' `images:` transformer rewrites to the real ECR URL — the
base directory is never applied directly with a working image.

## Rendering and applying

```bash
ENV=dev   # or prod
export AWS_ACCOUNT_ID="$(AWS_PROFILE=dev aws sts get-caller-identity --query Account --output text)"
export IMAGE_TAG="<commit-sha-or-tag>"
export RDS_ENDPOINT="$(AWS_PROFILE=dev terraform -chdir="terraform/environments/${ENV}" output -raw rds_endpoint)"

kubectl kustomize "k8s/overlays/${ENV}" | envsubst | kubectl apply --dry-run=client -f -   # validate
kubectl kustomize "k8s/overlays/${ENV}" | envsubst | kubectl apply -f -                    # apply
```

## Standards applied to every Deployment

- `startupProbe` / `readinessProbe` / `livenessProbe` on `/actuator/health*`
  (startup gates the other two so Spring Boot gets time to initialize —
  technical-spec.md#kubernetes-manifests)
- Pod `securityContext`: `runAsNonRoot`, `runAsUser: 1000`, `fsGroup: 1000`,
  `seccompProfile.type: RuntimeDefault`
- Container `securityContext`: `allowPrivilegeEscalation: false`,
  `capabilities.drop: ["ALL"]`, `readOnlyRootFilesystem: false` (Spring Boot
  needs `/tmp` for uploads/caching)
- `imagePullPolicy: Always` on every container, including init containers
- Resource requests/limits per technical-spec.md#kubernetes-manifests
