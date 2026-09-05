#!/usr/bin/env bash
set -euo pipefail

#
# build-push-ecr.sh — Build all 8 Spring Petclinic services and push ARM64
# images to ECR (PETPLAT-85).
#
# Does NOT use `./mvnw -P buildDocker` (that profile builds an x86 image via
# Spring Boot's buildpacks, wrong architecture for our Graviton/t4g nodes).
# Instead:
#   1. `./mvnw clean package -DskipTests` builds all 8 JARs.
#   2. `docker buildx build --platform linux/arm64 --push` builds and pushes
#      a native ARM64 image per service straight to ECR, using the shared
#      docker/Dockerfile from the application repo.
#
# Ports come from the Service Inventory table in docs/technical-spec.md, NOT
# from each module's pom.xml `docker.image.exposed.port` property — that
# property is wrong (copy-paste leftovers) for api-gateway, visits-service,
# vets-service, and genai-service.
#
# Usage:
#   ./scripts/build-push-ecr.sh [--env dev] [--tag v1.0.0] [--region eu-central-1] [--app-repo <path>]
#
# Examples:
#   AWS_PROFILE=dev ./scripts/build-push-ecr.sh
#   AWS_PROFILE=dev ./scripts/build-push-ecr.sh --env dev --tag v1.0.0
#   AWS_PROFILE=dev ./scripts/build-push-ecr.sh --tag "$(git -C ../spring-petclinic-microservices rev-parse --short=7 HEAD)"
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENVIRONMENT="dev"
TAG="v1.0.0"
REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
APP_REPO="${PLATFORM_ROOT}/../spring-petclinic-microservices"

usage() {
  echo "Usage: $0 [--env dev|prod] [--tag <tag>] [--region <aws-region>] [--app-repo <path>]"
  echo ""
  echo "Options:"
  echo "  --env        Target environment / ECR namespace (default: dev)"
  echo "  --tag        Image tag to push, e.g. v1.0.0 or a commit SHA (default: v1.0.0)"
  echo "  --region     AWS region the ECR registry lives in (default: eu-central-1)"
  echo "  --app-repo   Path to the spring-petclinic-microservices checkout"
  echo "               (default: ../spring-petclinic-microservices, sibling of this repo)"
  echo ""
  echo "Examples:"
  echo "  AWS_PROFILE=dev $0"
  echo "  AWS_PROFILE=dev $0 --env dev --tag v1.0.0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --app-repo)
      APP_REPO="$2"
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

if [[ "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ]]; then
  echo "Error: --env must be 'dev' or 'prod'"
  usage
fi

if [[ ! -d "${APP_REPO}" ]]; then
  echo "Error: application repo not found at ${APP_REPO}"
  echo "       pass --app-repo <path> to point at your spring-petclinic-microservices checkout"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# module dir : exposed port — per docs/technical-spec.md Service Inventory,
# NOT per pom.xml's docker.image.exposed.port (wrong for several services).
SERVICES=(
  "config-server:spring-petclinic-config-server:8888"
  "discovery-server:spring-petclinic-discovery-server:8761"
  "api-gateway:spring-petclinic-api-gateway:8080"
  "customers-service:spring-petclinic-customers-service:8081"
  "visits-service:spring-petclinic-visits-service:8082"
  "vets-service:spring-petclinic-vets-service:8083"
  "genai-service:spring-petclinic-genai-service:8084"
  "admin-server:spring-petclinic-admin-server:9090"
)

echo "============================================"
echo "  Build & Push Spring Petclinic images to ECR"
echo "  App repo:   ${APP_REPO}"
echo "  Registry:   ${REGISTRY}"
echo "  Env:        ${ENVIRONMENT}"
echo "  Tag:        ${TAG}"
echo "  Platform:   linux/arm64"
echo "============================================"
echo ""

echo "[1/3] Building all JARs with Maven..."
(cd "${APP_REPO}" && ./mvnw -q clean package -DskipTests)
echo "  -> Maven build complete."
echo ""

echo "[2/3] Logging in to ECR..."
"${SCRIPT_DIR}/ecr-login.sh" --region "${REGION}"
echo ""

echo "[3/3] Building and pushing ARM64 images..."
BUILDER_NAME="petclinic-ecr-builder"
if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container >/dev/null
fi
docker buildx use "${BUILDER_NAME}"

for entry in "${SERVICES[@]}"; do
  IFS=":" read -r SERVICE_NAME MODULE_DIR EXPOSED_PORT <<< "${entry}"

  JAR_PATH=$(find "${APP_REPO}/${MODULE_DIR}/target" -maxdepth 1 -name "*.jar" \
    ! -name "*sources*" ! -name "*javadoc*" | head -1)

  if [[ -z "${JAR_PATH}" ]]; then
    echo "Error: no built JAR found for ${SERVICE_NAME} under ${MODULE_DIR}/target/"
    echo "       did the Maven build succeed?"
    exit 1
  fi

  ARTIFACT_NAME="${MODULE_DIR}/target/$(basename "${JAR_PATH}" .jar)"
  IMAGE_URI="${REGISTRY}/petclinic-${ENVIRONMENT}/${SERVICE_NAME}:${TAG}"

  echo "  -> ${SERVICE_NAME}: building and pushing ${IMAGE_URI}"
  docker buildx build \
    --platform linux/arm64 \
    --file "${APP_REPO}/docker/Dockerfile" \
    --build-arg "ARTIFACT_NAME=${ARTIFACT_NAME}" \
    --build-arg "EXPOSED_PORT=${EXPOSED_PORT}" \
    --tag "${IMAGE_URI}" \
    --push \
    "${APP_REPO}"
done

echo ""
echo "============================================"
echo "  All 8 images pushed to ${REGISTRY}/petclinic-${ENVIRONMENT}/*:${TAG}"
echo ""
echo "  Verify:"
echo "    aws ecr describe-images --repository-name petclinic-${ENVIRONMENT}/customers-service --region ${REGION}"
echo "============================================"
