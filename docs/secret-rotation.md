# Secret Management

**Last Updated:** 2026-09-15
**Purpose:** How secrets are stored, synced into the cluster, and how to add a new one. Rotation procedures land here as they're defined per secret type.

## Table of Contents

- [Architecture](#architecture)
- [Procedure: Add a new secret](#procedure-add-a-new-secret)
- [Procedure: Verify a secret synced correctly](#procedure-verify-a-secret-synced-correctly)

## Architecture

All application secrets live in AWS Secrets Manager under the `petclinic/{env}/...`
naming convention, encrypted with the default `aws/secretsmanager` KMS key.
External Secrets Operator (ESO), running in the `external-secrets` namespace
on each cluster, reads them via an IRSA-scoped role
(`petclinic-{env}-eso-role`, `terraform/modules/eks`) and syncs them into
Kubernetes Secrets via `ExternalSecret` resources in `k8s/base/external-secrets/`.

| Secret | Owning Terraform module | K8s Secret name |
|--------|--------------------------|------------------|
| `petclinic/{env}/rds-credentials` | `terraform/modules/rds` (PETPLAT-23) | `rds-credentials` |
| `petclinic/{env}/openai-api-key` | `terraform/modules/secrets` (PETPLAT-33) | `openai-api-key` |

The `secrets` module never manages RDS credentials — those are created
alongside the RDS instance itself so the master password never needs to
leave that module's state.

## Procedure: Add a new secret

**When:** A new service needs a credential or API key that shouldn't live in a ConfigMap or Helm values.
**Who:** Anyone with Terraform apply access to the target environment.
**Time:** ~10 minutes, plus one `terraform apply`.

**Steps:**
1. Add the secret to the owning Terraform module (the `secrets` module for a
   generic application secret, or a dedicated module if it belongs to one —
   e.g. RDS credentials stay in the `rds` module). Follow the
   `openai_api_key` variable in `terraform/modules/secrets/` as a template:
   a `sensitive = true` Terraform variable, never a hardcoded value.
2. `terraform apply` in the target environment. This creates
   `petclinic/{env}/{name}` in Secrets Manager.
3. No IAM change is needed if the secret name is under `petclinic/*` — the
   ESO IRSA role already grants `secretsmanager:GetSecretValue` and
   `DescribeSecret` on that whole prefix.
4. Add an `ExternalSecret` manifest in `k8s/base/external-secrets/`,
   following `openai-api-key.yaml` (plaintext secret) or
   `rds-credentials.yaml` (JSON secret, one `data[]` entry per property).
5. Render with `envsubst` and apply — see `k8s/base/external-secrets/README.md`.

**Verify:**
- `kubectl get externalsecret -n petclinic-{env}` shows `SecretSynced`
- `kubectl get secret {name} -n petclinic-{env}` shows the created secret

**Rollback:**
- `kubectl delete -f` the `ExternalSecret` manifest to stop syncing (the
  Secrets Manager secret itself is untouched)
- `terraform destroy -target` the secret resource to remove it from Secrets
  Manager entirely (never run this without reviewing the plan first)

## Procedure: Verify a secret synced correctly

**When:** After installing ESO, after adding a new secret, or when a pod can't find an expected environment variable.
**Who:** Anyone with `kubectl` access to the cluster.
**Time:** < 5 minutes.

**Steps:**
1. Check the `ExternalSecret` status:
   ```bash
   kubectl describe externalsecret {name} -n petclinic-{env}
   ```
   Look for `SecretSynced` in the conditions. A `SecretSyncedError` usually
   means the ESO IRSA role can't read the target secret, or the
   `petclinic/{env}/...` key doesn't exist.
2. Check the resulting Kubernetes Secret exists and has the expected keys:
   ```bash
   kubectl get secret {name} -n petclinic-{env} -o jsonpath='{.data}' | jq 'keys'
   ```
3. If the `ClusterSecretStore` itself is unhealthy, check its status:
   ```bash
   kubectl describe clustersecretstore aws-secrets-manager
   ```

**Verify:**
- The `ExternalSecret`'s `status.conditions` includes `type: Ready, status: "True"`
- `kubectl get secret` shows the expected key names (values are base64-encoded, not printed)

**Rollback:**
- N/A — this is a read-only diagnostic procedure.
