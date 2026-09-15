#!/usr/bin/env bash
set -euo pipefail

#
# install-lb_controller.sh — Install the AWS Load Balancer Controller on EKS
#                            (PETPLAT-29)
#
# The controller watches Ingress resources and provisions ALBs for them. It is
# a cluster add-on rather than infrastructure, so it is installed with Helm
# here; its IAM policy and IRSA role live in Terraform (modules/eks) next to
# the OIDC provider they depend on.
#
# What this does:
#   1. Resolves clusterName / vpcId / IRSA role ARN from the environment's
#      Terraform outputs (override with flags to skip Terraform entirely).
#   2. Updates kubeconfig for the cluster.
#   3. Adds the eks-charts Helm repo.
#   4. Applies the chart's CRDs (IngressClassParams, TargetGroupBinding, ...).
#      Helm installs CRDs on first install but never upgrades them, so they are
#      applied explicitly from the pinned chart version on every run.
#   5. helm upgrade --install into kube-system with the IRSA-annotated service
#      account.
#   6. Verifies the deployment rolled out and the "alb" IngressClass exists.
#
# Usage:
#   ./scripts/install-lb_controller.sh --env dev [options]
#
# Options:
#   --env <dev|prod>       Target environment (required)
#   --profile <name>       AWS profile to use (default: whatever the AWS CLI resolves)
#   --region <region>      AWS region (default: eu-central-1)
#   --chart-version <ver>  aws-load-balancer-controller chart version (default: 3.5.0)
#   --cluster-name <name>  Skip the Terraform lookup for the cluster name
#   --vpc-id <id>          Skip the Terraform lookup for the VPC ID
#   --role-arn <arn>       Skip the Terraform lookup for the IRSA role ARN
#   --values <file>        Helm values file (default: k8s/addons/aws-load-balancer-controller/values.yaml)
#   --dry-run              Render the release without installing anything (still
#                          requires a reachable cluster: server-side validation)
#   --yes                  Do not prompt for confirmation of the target account/cluster
#   -h, --help             Show this help
#
# Examples:
#   ./scripts/install-lb_controller.sh --env dev --profile dev
#   ./scripts/install-lb_controller.sh --env prod --profile prod --dry-run
#

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENVIRONMENT=""
AWS_PROFILE_ARG=""
REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
# Chart 3.5.0 ships controller v3.5.0. The IAM policy vendored at
# terraform/modules/eks/policies/aws-load-balancer-controller.json is the
# upstream policy for that same version — re-vendor it when bumping this.
CHART_VERSION="3.5.0"
CHART_REPO_NAME="eks"
CHART_REPO_URL="https://aws.github.io/eks-charts"
RELEASE_NAME="aws-load-balancer-controller"
NAMESPACE="kube-system"
CLUSTER_NAME=""
VPC_ID=""
ROLE_ARN=""
VALUES_FILE="${REPO_ROOT}/k8s/addons/aws-load-balancer-controller/values.yaml"
DRY_RUN="false"
ASSUME_YES="false"

usage() {
  cat <<'USAGE'
install-lb_controller.sh — Install the AWS Load Balancer Controller on EKS

Usage:
  ./scripts/install-lb_controller.sh --env dev [options]

Options:
  --env <dev|prod>       Target environment (required)
  --profile <name>       AWS profile to use (default: whatever the AWS CLI resolves)
  --region <region>      AWS region (default: eu-central-1)
  --chart-version <ver>  aws-load-balancer-controller chart version (default: 3.5.0)
  --cluster-name <name>  Skip the Terraform lookup for the cluster name
  --vpc-id <id>          Skip the Terraform lookup for the VPC ID
  --role-arn <arn>       Skip the Terraform lookup for the IRSA role ARN
  --values <file>        Helm values file
                         (default: k8s/addons/aws-load-balancer-controller/values.yaml)
  --dry-run              Render the release without installing anything. Still
                         needs a reachable cluster — CRDs and the chart are
                         validated server-side.
  --yes, -y              Do not prompt to confirm the target account/cluster
  -h, --help             Show this help

Examples:
  ./scripts/install-lb_controller.sh --env dev --profile dev
  ./scripts/install-lb_controller.sh --env prod --profile prod --dry-run
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
    --vpc-id)        VPC_ID="${2:-}"; shift 2 ;;
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
[[ -z "${CLUSTER_NAME}" || -z "${VPC_ID}" || -z "${ROLE_ARN}" ]] && needs_terraform="true"

if [[ "${needs_terraform}" == "true" ]]; then
  command -v terraform >/dev/null 2>&1 \
    || die "terraform is required to resolve cluster values (or pass --cluster-name, --vpc-id and --role-arn)"
  [[ -d "${TF_DIR}/.terraform" ]] \
    || die "${TF_DIR} is not initialized — run: terraform -chdir=${TF_DIR} init"

  [[ -n "${CLUSTER_NAME}" ]] || CLUSTER_NAME="$(tf_output cluster_name)"
  [[ -n "${VPC_ID}" ]]       || VPC_ID="$(tf_output vpc_id)"
  [[ -n "${ROLE_ARN}" ]]     || ROLE_ARN="$(tf_output lb_controller_role_arn)"
fi

[[ -n "${CLUSTER_NAME}" ]] || die "could not resolve the cluster name — pass --cluster-name"
[[ -n "${VPC_ID}" ]]       || die "could not resolve the VPC ID — pass --vpc-id"
[[ -n "${ROLE_ARN}" ]]     || die "could not resolve the IRSA role ARN — pass --role-arn (is the eks module applied?)"

ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)" \
  || die "AWS credentials are not usable — check your profile / SSO session"
CALLER_ARN="$(aws sts get-caller-identity --query 'Arn' --output text)"

cat <<SUMMARY
============================================
  AWS Load Balancer Controller install
============================================
  Environment    : ${ENVIRONMENT}
  AWS account    : ${ACCOUNT_ID}
  AWS identity   : ${CALLER_ARN}
  AWS profile    : ${AWS_PROFILE:-<default resolution>}
  Region         : ${REGION}
  Cluster        : ${CLUSTER_NAME}
  VPC            : ${VPC_ID}
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

# --- Helm repo ------------------------------------------------------------

echo "==> Adding Helm repo ${CHART_REPO_NAME} (${CHART_REPO_URL})"
helm repo add "${CHART_REPO_NAME}" "${CHART_REPO_URL}" --force-update
helm repo update "${CHART_REPO_NAME}"

# --- CRDs -----------------------------------------------------------------
# Pulled from the pinned chart so the CRDs always match the controller version
# being installed. Helm skips CRDs on `upgrade`, so this must happen here.

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

echo "==> Fetching chart ${RELEASE_NAME} ${CHART_VERSION} to extract CRDs"
helm pull "${CHART_REPO_NAME}/${RELEASE_NAME}" \
  --version "${CHART_VERSION}" \
  --untar --untardir "${WORK_DIR}"

CRD_FILE="${WORK_DIR}/${RELEASE_NAME}/crds/crds.yaml"
[[ -f "${CRD_FILE}" ]] || die "CRDs not found in chart ${CHART_VERSION} at crds/crds.yaml"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "==> [dry-run] would apply CRDs from ${CRD_FILE}"
  kubectl apply --server-side --force-conflicts --dry-run=server -f "${CRD_FILE}"
else
  echo "==> Applying CRDs (IngressClassParams, TargetGroupBinding, ...)"
  kubectl apply --server-side --force-conflicts -f "${CRD_FILE}"
fi

# --- Install / upgrade ----------------------------------------------------

HELM_ARGS=(
  upgrade --install "${RELEASE_NAME}" "${CHART_REPO_NAME}/${RELEASE_NAME}"
  --namespace "${NAMESPACE}"
  --version "${CHART_VERSION}"
  --values "${VALUES_FILE}"
  --set "clusterName=${CLUSTER_NAME}"
  --set "region=${REGION}"
  --set "vpcId=${VPC_ID}"
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}"
  --set "defaultTags.Environment=${ENVIRONMENT}"
  # CRDs are managed above, not by Helm.
  --skip-crds
)

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "==> [dry-run] rendering release"
  helm "${HELM_ARGS[@]}" --dry-run
  echo "Dry run complete — nothing was installed."
  exit 0
fi

echo "==> Installing ${RELEASE_NAME} ${CHART_VERSION}"
helm "${HELM_ARGS[@]}" --wait --timeout 10m

# --- Verify ---------------------------------------------------------------

echo "==> Waiting for the controller rollout"
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE_NAME}" --timeout=5m

echo "==> Verifying the service account carries the IRSA annotation"
SA_ROLE="$(kubectl -n "${NAMESPACE}" get serviceaccount "${RELEASE_NAME}" \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
[[ "${SA_ROLE}" == "${ROLE_ARN}" ]] \
  || die "service account role annotation is '${SA_ROLE}', expected '${ROLE_ARN}'"

echo "==> Verifying the 'alb' IngressClass exists"
kubectl get ingressclass alb >/dev/null \
  || die "IngressClass 'alb' was not created — check createIngressClassResource in ${VALUES_FILE}"

kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/name=${RELEASE_NAME}"

cat <<NEXT

AWS Load Balancer Controller ${CHART_VERSION} is running in ${NAMESPACE} on ${CLUSTER_NAME}.

Next steps:
  1. Apply the Ingress (renders the environment-specific values):
       see k8s/base/ingress/README.md
  2. Watch the ALB get provisioned:
       kubectl get ingress -n petclinic-${ENVIRONMENT} -w
  3. Point Route 53 at the ALB (second Terraform apply):
       see k8s/base/ingress/README.md -> "Pointing DNS at the ALB"

Controller logs:
  kubectl -n ${NAMESPACE} logs -l app.kubernetes.io/name=${RELEASE_NAME} -f
NEXT
