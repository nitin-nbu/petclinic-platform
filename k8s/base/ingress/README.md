# API Gateway Ingress

`ingress.yaml` is the single public entry point for the platform. The AWS Load
Balancer Controller turns it into an internet-facing ALB that forwards `/` to
`api-gateway:8080`; all further routing is the API Gateway's job.

## Prerequisites

1. AWS Load Balancer Controller installed — `./scripts/install-lb_controller.sh --env dev`
2. DNS module applied with a `domain_name` set — provides the ACM certificate
3. `petclinic-{env}` namespace exists — `k8s/base/namespaces.yaml`
4. `api-gateway` Service deployed in that namespace

## Applying

The manifest carries four placeholders (environment-specific values sourced
from Terraform outputs). Render with `envsubst`:

```bash
ENV=dev
TF_DIR="terraform/environments/${ENV}"

export ENVIRONMENT="${ENV}"
export PETCLINIC_NAMESPACE="petclinic-${ENV}"
export ACM_CERTIFICATE_ARN="$(AWS_PROFILE=dev terraform -chdir="${TF_DIR}" output -raw certificate_arn)"
export PETCLINIC_HOST="$(AWS_PROFILE=dev terraform -chdir="${TF_DIR}" output -raw app_fqdn)"

envsubst < k8s/base/ingress/ingress.yaml | kubectl apply -f -
```

Check the rendered output before applying with
`envsubst < k8s/base/ingress/ingress.yaml | kubectl apply --dry-run=server -f -`.

## Pointing DNS at the ALB

The ALB only exists after the Ingress is reconciled, so the Route 53 alias
record is a second Terraform apply. Read the ALB back and feed it to the DNS
module:

```bash
ALB_HOST=$(kubectl get ingress petclinic-api-gateway -n "petclinic-${ENV}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_ZONE=$(AWS_PROFILE=dev aws elbv2 describe-load-balancers \
  --names "petclinic-${ENV}-alb" --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)

AWS_PROFILE=dev terraform -chdir="${TF_DIR}" plan -out plan.out \
  -var "alb_dns_name=${ALB_HOST}" -var "alb_zone_id=${ALB_ZONE}"
AWS_PROFILE=dev terraform -chdir="${TF_DIR}" apply plan.out
```

Alternatively set `alb_discovery_tags` (e.g.
`{ "elbv2.k8s.aws/cluster" = "petclinic-dev" }`) and Terraform looks the ALB up
itself — but that lookup fails the plan while no matching ALB exists, so only
enable it after the Ingress is up.

## Verifying

```bash
kubectl describe ingress petclinic-api-gateway -n "petclinic-${ENV}"
curl -sSI "http://$(terraform -chdir="${TF_DIR}" output -raw app_fqdn)"   # expect 301 -> https
curl -sS  "$(terraform -chdir="${TF_DIR}" output -raw app_url)/actuator/health"
```

Target health lives in the ALB target group; `aws elbv2 describe-target-health`
is the fastest way to see why a pod is out of rotation.
