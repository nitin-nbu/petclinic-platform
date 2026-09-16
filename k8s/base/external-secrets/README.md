# External Secrets

Syncs AWS Secrets Manager secrets into Kubernetes Secrets via [External
Secrets Operator](https://external-secrets.io) (ESO). ESO itself, its CRDs,
and its IRSA-authenticated service account are installed separately — see
`scripts/install-external-secrets.sh`.

## Prerequisites

1. External Secrets Operator installed — `./scripts/install-external-secrets.sh --env {env}`
2. `petclinic-{env}` namespace exists — `k8s/base/namespaces.yaml`
3. The secrets themselves exist in Secrets Manager — `petclinic/{env}/rds-credentials`
   (created by the `rds` module, PETPLAT-23) and `petclinic/{env}/openai-api-key`
   (created by the `secrets` module, PETPLAT-33)

## Applying

`cluster-secret-store.yaml` has no placeholders — apply it once per cluster:

```bash
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml
```

`rds-credentials.yaml` and `openai-api-key.yaml` carry two placeholders each
(environment-specific values). Render with `envsubst`, same pattern as
`k8s/base/ingress/`:

```bash
ENV=dev
export ENVIRONMENT="${ENV}"
export PETCLINIC_NAMESPACE="petclinic-${ENV}"

envsubst < k8s/base/external-secrets/rds-credentials.yaml | kubectl apply -f -
envsubst < k8s/base/external-secrets/openai-api-key.yaml | kubectl apply -f -
```

## Verifying

```bash
kubectl get externalsecret -n "petclinic-${ENV}"
kubectl get secret rds-credentials -n "petclinic-${ENV}"
kubectl get secret openai-api-key -n "petclinic-${ENV}"
```

A healthy `ExternalSecret` reports `SecretSynced` in its status; a failing
one usually means the ESO IRSA role can't read the target secret, or the
`petclinic/{env}/...` key doesn't exist yet.

## Adding a new secret

1. Create the secret value in AWS Secrets Manager, named `petclinic/{env}/{name}`
   (add it to the `secrets` module if it's a new non-RDS application secret,
   or to the owning module if it belongs to one — e.g. RDS credentials stay
   in the `rds` module).
2. The ESO IRSA role (`petclinic-{env}-eso-role`, `terraform/modules/eks`)
   already grants `secretsmanager:GetSecretValue` / `DescribeSecret` on all
   of `petclinic/*` — no IAM change needed for a new secret under that prefix.
3. Add a new `ExternalSecret` manifest here, following `openai-api-key.yaml`
   (plaintext secret) or `rds-credentials.yaml` (JSON secret, one `data[]`
   entry per property) as a template.
4. Render with `envsubst` and apply as above, then verify with `kubectl get
   externalsecret` / `kubectl get secret`.
