#!/usr/bin/env bash
set -euo pipefail

#
# install-external-secrets.sh — Install External Secrets Operator on EKS
#                                (PETPLAT-34)
#
# ESO syncs secrets from AWS Secrets Manager into Kubernetes Secret objects
# for ExternalSecret resources to consume. It is a cluster add-on rather than
# infrastructure, so it is installed here; its IAM policy and IRSA role live
# in Terraform (modules/eks) next to the OIDC provider they depend on.
#
# Per PETPLAT-34's acceptance criteria, both the CRDs and the controller are
# installed via `kubectl apply`, not `helm install`/`helm upgrade`: the chart
# is rendered locally with `helm template` (pinned version, for reproducible,
# reviewable manifests) and the result is applied with kubectl.
#
# What this does:
#   1. Resolves clusterName / IRSA role ARN from the environment's Terraform
#      outputs (override with flags to skip Terraform entirely).
#   2. Updates kubeconfig for the cluster.
#   3. Creates the external-secrets namespace if it doesn't exist.
#   4. Adds the external-secrets Helm repo and renders the chart (CRDs +
#      controller + webhook + cert-controller) with `helm template`.
#   5. Applies the rendered manifest with `kubectl apply --server-side`.
#   6. Applies the ClusterSecretStore (k8s/base/external-secrets).
#   7. Verifies the rollout and the service account's IRSA annotation.
#
# Usage:
#   ./scripts/install-external-secrets.sh --env dev [options]
#
# Options:
#   --env <dev|prod>       Target environment (required)
#   --profile <name>       AWS profile to use (default: whatever the AWS CLI resolves)
#   --region <region>      AWS region (default: eu-central-1)
#   --chart-version <ver>  external-secrets chart version (default: 2.10.0)
#   --cluster-name <name>  Skip the Terraform lookup for the cluster name
#   --role-arn <arn>       Skip the Terraform lookup for the IRSA role ARN
#   --values <file>        Helm values file (default: k8s/addons/external-secrets/values.yaml)
#   --dry-run              Render manifests without applying anything (no cluster required)
#   --yes                  Do not prompt for confirmation of the target account/cluster
#   -h, --help             Show this help
#
# Examples:
#   ./scripts/install-external-secrets.sh --env dev --profile dev
#   ./scripts/install-external-secrets.sh --env prod --profile prod --dry-run
#

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENVIRONMENT=""
AWS_PROFILE_ARG=""
REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
CHART_VERSION="2.10.0"
CHART_REPO_NAME="external-secrets"
CHART_REPO_URL="https://charts.external-secrets.io"
RELEASE_NAME="external-secrets"
NAMESPACE="external-secrets"
CLUSTER_NAME=""
ROLE_ARN=""
VALUES_FILE="${REPO_ROOT}/k8s/addons/external-secrets/values.yaml"
CLUSTER_SECRET_STORE_FILE="${REPO_ROOT}/k8s/base/external-secrets/cluster-secret-store.yaml"
DRY_RUN="false"
ASSUME_YES="false"

usage() {
  cat <<'USAGE'
install-external-secrets.sh — Install External Secrets Operator on EKS

Usage:
  ./scripts/install-external-secrets.sh --env dev [options]

Options:
  --env <dev|prod>       Target environment (required)
  --profile <name>       AWS profile to use (default: whatever the AWS CLI resolves)
  --region <region>      AWS region (default: eu-central-1)
  --chart-version <ver>  external-secrets chart version (default: 2.10.0)
  --cluster-name <name>  Skip the Terraform lookup for the cluster name
  --role-arn <arn>       Skip the Terraform lookup for the IRSA role ARN
  --values <file>        Helm values file
                         (default: k8s/addons/external-secrets/values.yaml)
  --dry-run              Render manifests without applying anything. No
                         reachable cluster required.
  --yes, -y              Do not prompt to confirm the target account/cluster
  -h, --help             Show this help

Examples:
  ./scripts/install-external-secrets.sh --env dev --profile dev
  ./scripts/install-external-secrets.sh --env prod --profile prod --dry-run
USAGE
  exit "${1:-1}"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)           ENVIRONMENT="${2:-}"; shift 2 ;;
    --profile)       AWS_PROFILE_ARG="${2:-}"; shift 2 ;;
    --region)        REGION="${2:-}"; shift 2 ;;
    --chart-version) CHART_VERSION="${2:-}"; shift 2 ;;
    --cluster-name)  CLUSTER_NAME="${2:-}"; shift 2 ;;
    --role-arn)      ROLE_ARN="${2:-}"; shift 2 ;;
    --values)        VALUES_FILE="${2:-}"; shift 2 ;;
    --dry-run)       DRY_RUN="true"; shift ;;
    --yes|-y)        ASSUME_YES="true"; shift ;;
    -h|--help)       usage 0 ;;
    *)               echo "Error: unknown argument '$1'" >&2; usage ;;
  esac
done

[[ -n "${ENVIRONMENT}" ]] || { echo "Error: --env is required" >&2; usage; }
[[ "${ENVIRONMENT}" == "dev" || "${ENVIRONMENT}" == "prod" ]] \
  || die "--env must be 'dev' or 'prod' (got '${ENVIRONMENT}')"
[[ -f "${VALUES_FILE}" ]] || die "values file not found: ${VALUES_FILE}"
[[ -f "${CLUSTER_SECRET_STORE_FILE}" ]] || die "ClusterSecretStore manifest not found: ${CLUSTER_SECRET_STORE_FILE}"

if [[ -n "${AWS_PROFILE_ARG}" ]]; then
  export AWS_PROFILE="${AWS_PROFILE_ARG}"
fi
export AWS_REGION="${REGION}"
export AWS_DEFAULT_REGION="${REGION}"

# --- Preflight ------------------------------------------------------------

for tool in aws kubectl helm; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not on PATH"
done

TF_DIR="${REPO_ROOT}/terraform/environments/${ENVIRONMENT}"

tf_output() {
  local name="$1"
  terraform -chdir="${TF_DIR}" output -raw "${name}" 2>/dev/null || true
}

needs_terraform="false"
[[ -z "${CLUSTER_NAME}" || -z "${ROLE_ARN}" ]] && needs_terraform="true"

if [[ "${needs_terraform}" == "true" ]]; then
  command -v terraform >/dev/null 2>&1 \
    || die "terraform is required to resolve cluster values (or pass --cluster-name and --role-arn)"
  [[ -d "${TF_DIR}/.terraform" ]] \
    || die "${TF_DIR} is not initialized — run: terraform -chdir=${TF_DIR} init"

  [[ -n "${CLUSTER_NAME}" ]] || CLUSTER_NAME="$(tf_output cluster_name)"
  [[ -n "${ROLE_ARN}" ]]     || ROLE_ARN="$(tf_output eso_role_arn)"
fi

[[ -n "${CLUSTER_NAME}" ]] || die "could not resolve the cluster name — pass --cluster-name"
[[ -n "${ROLE_ARN}" ]]     || die "could not resolve the IRSA role ARN — pass --role-arn (is the eks module applied?)"

ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)" \
  || die "AWS credentials are not usable — check your profile / SSO session"
CALLER_ARN="$(aws sts get-caller-identity --query 'Arn' --output text)"

cat <<SUMMARY
============================================
  External Secrets Operator install
============================================
  Environment    : ${ENVIRONMENT}
  AWS account    : ${ACCOUNT_ID}
  AWS identity   : ${CALLER_ARN}
  AWS profile    : ${AWS_PROFILE:-<default resolution>}
  Region         : ${REGION}
  Cluster        : ${CLUSTER_NAME}
  IRSA role      : ${ROLE_ARN}
  Chart          : ${CHART_REPO_NAME}/${RELEASE_NAME} ${CHART_VERSION}
  Namespace      : ${NAMESPACE}
  Values         : ${VALUES_FILE}
  Dry run        : ${DRY_RUN}
============================================
SUMMARY

if [[ "${ASSUME_YES}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Proceed? [y/N] " reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

# --- kubeconfig -----------------------------------------------------------

echo "==> Updating kubeconfig for ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"
kubectl cluster-info >/dev/null || die "cannot reach the cluster API server"

# --- Namespace --------------------------------------------------------------

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "==> [dry-run] would ensure namespace ${NAMESPACE} exists"
else
  echo "==> Ensuring namespace ${NAMESPACE} exists"
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
fi

# --- Helm repo --------------------------------------------------------------

echo "==> Adding Helm repo ${CHART_REPO_NAME} (${CHART_REPO_URL})"
helm repo add "${CHART_REPO_NAME}" "${CHART_REPO_URL}" --force-update
helm repo update "${CHART_REPO_NAME}"

# --- Render + apply (CRDs + controller) -------------------------------------
# `helm template` renders CRDs and controller manifests together
# (installCRDs: true in values.yaml); `kubectl apply` performs the actual
# install, per PETPLAT-34's acceptance criteria.

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

MANIFEST_FILE="${WORK_DIR}/external-secrets.yaml"

echo "==> Rendering ${RELEASE_NAME} ${CHART_VERSION}"
helm template "${RELEASE_NAME}" "${CHART_REPO_NAME}/${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}" \
  > "${MANIFEST_FILE}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "==> [dry-run] would apply rendered manifest (CRDs + controller) from ${MANIFEST_FILE}"
  kubectl apply --server-side --force-conflicts --dry-run=server -f "${MANIFEST_FILE}"
  echo "==> [dry-run] would apply ClusterSecretStore from ${CLUSTER_SECRET_STORE_FILE}"
  kubectl apply --dry-run=server -f "${CLUSTER_SECRET_STORE_FILE}"
  echo "Dry run complete — nothing was installed."
  exit 0
fi

echo "==> Applying rendered manifest (CRDs + controller)"
kubectl apply --server-side --force-conflicts -f "${MANIFEST_FILE}"

# --- Verify -------------------------------------------------------------

echo "==> Waiting for the controller rollout"
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE_NAME}" --timeout=5m
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE_NAME}-webhook" --timeout=5m
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE_NAME}-cert-controller" --timeout=5m

echo "==> Verifying the service account carries the IRSA annotation"
SA_ROLE="$(kubectl -n "${NAMESPACE}" get serviceaccount "external-secrets-sa" \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
[[ "${SA_ROLE}" == "${ROLE_ARN}" ]] \
  || die "service account role annotation is '${SA_ROLE}', expected '${ROLE_ARN}'"

# --- ClusterSecretStore ---------------------------------------------------

echo "==> Applying ClusterSecretStore"
kubectl apply -f "${CLUSTER_SECRET_STORE_FILE}"

echo "==> Waiting for the ClusterSecretStore to be ready"
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=2m

kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE_NAME}"

cat <<NEXT

External Secrets Operator ${CHART_VERSION} is running in ${NAMESPACE} on ${CLUSTER_NAME}.
ClusterSecretStore "aws-secrets-manager" is Ready.

Next steps — sync the application secrets (also serves as the install test):
  ENV=${ENVIRONMENT}
  export ENVIRONMENT="\${ENV}"
  export PETCLINIC_NAMESPACE="petclinic-\${ENV}"

  envsubst < k8s/base/external-secrets/rds-credentials.yaml | kubectl apply -f -
  envsubst < k8s/base/external-secrets/openai-api-key.yaml | kubectl apply -f -

  kubectl get externalsecret -n petclinic-\${ENV}
  kubectl get secret rds-credentials openai-api-key -n petclinic-\${ENV}

See k8s/base/external-secrets/README.md for details, including how to add a new secret.

Controller logs:
  kubectl -n ${NAMESPACE} logs -l app.kubernetes.io/name=${RELEASE_NAME} -f
NEXT
