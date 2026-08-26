#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time provisioning of the Terraform remote state backend
#
# Creates the S3 bucket (versioned, encrypted, public access blocked) and the
# DynamoDB lock table used by every environment's backend.tf. Run once per AWS
# account, before the first `terraform init`. Safe to re-run (idempotent).
#
# Usage:
#   ./scripts/bootstrap-state.sh [--region eu-central-1]
#
# Bucket name: petclinic-terraform-state-{account-id}
# Table name:  petclinic-terraform-locks
#

REGION="eu-central-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Options:"
  echo "  --region   AWS region to provision the backend in (default: eu-central-1)"
  echo ""
  echo "Examples:"
  echo "  $0                        # provision in eu-central-1"
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
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "============================================"
echo "  Terraform State Backend Bootstrap"
echo "  Region:  ${REGION}"
echo "  Account: ${ACCOUNT_ID}"
echo "============================================"
echo ""

# --- S3 bucket for state ---
echo "--- S3 bucket: ${BUCKET_NAME} ---"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "  Bucket already exists — skipping creation"
else
  echo "  Creating bucket..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  echo "  Bucket created"
fi

echo "  Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled \
  --region "${REGION}"

echo "  Enabling default encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo "  Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "  S3 bucket ready: ${BUCKET_NAME}"
echo ""

# --- DynamoDB table for locking ---
echo "--- DynamoDB table: ${TABLE_NAME} ---"

TABLE_STATUS=$(aws dynamodb describe-table \
  --table-name "${TABLE_NAME}" \
  --region "${REGION}" \
  --query 'Table.TableStatus' \
  --output text 2>/dev/null || echo "NOT FOUND")

if [[ "${TABLE_STATUS}" != "NOT FOUND" ]]; then
  echo "  Table already exists (status: ${TABLE_STATUS}) — skipping creation"
else
  echo "  Creating table..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=petclinic Key=ManagedBy,Value=bootstrap-script \
    > /dev/null

  echo "  Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "  Table created"
fi

echo ""
echo "============================================"
echo "  Bootstrap complete"
echo "============================================"
echo "  S3 bucket:      ${BUCKET_NAME}"
echo "  DynamoDB table: ${TABLE_NAME}"
echo "  Region:         ${REGION}"
echo ""
echo "  backend.tf files in terraform/environments/{dev,prod}/ already"
echo "  reference this bucket and table (see PETPLAT-3 / PETPLAT-4)."
echo "============================================"
