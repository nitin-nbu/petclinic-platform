#!/usr/bin/env bash
set -euo pipefail

#
# ecr-login.sh — Authenticate Docker to the private ECR registry
#
# Fetches a short-lived ECR auth token via the AWS CLI and pipes it into
# `docker login`. Works on macOS and Linux with any credential source the
# AWS CLI already resolves (profile, env vars, SSO, OIDC in CI).
#
# Usage:
#   ./scripts/ecr-login.sh [--region eu-central-1]
#
# Examples:
#   AWS_PROFILE=dev ./scripts/ecr-login.sh
#   ./scripts/ecr-login.sh --region eu-central-1
#

REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Options:"
  echo "  --region   AWS region the ECR registry lives in (default: eu-central-1)"
  echo ""
  echo "Examples:"
  echo "  $0                        # login to eu-central-1"
  echo "  $0 --region eu-central-1  # explicit region"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "============================================"
echo "  ECR Login"
echo "  Registry: ${REGISTRY}"
echo "============================================"

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

echo "Logged in to ${REGISTRY}"
