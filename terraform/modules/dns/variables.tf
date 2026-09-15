variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "domain_name" {
  description = "Apex domain for the Route 53 hosted zone (e.g. \"example.com\") — the zone this module creates and issues the wildcard certificate for"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase apex domain such as \"example.com\" (no scheme, no trailing dot, no wildcard)."
  }
}

variable "record_name" {
  description = "Subdomain label for this environment's ALB alias record — the record created is \"{record_name}.{domain_name}\" (spec: \"petclinic-dev\" for dev, \"petclinic\" for prod)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.record_name))
    error_message = "record_name must be a single lowercase DNS label (letters, digits, hyphens; no dots)."
  }
}

# ---------------------------------------------------------------------------
# ALB alias target (PETPLAT-31)
#
# The ALB is created by the AWS Load Balancer Controller in response to the
# Ingress (PETPLAT-30), not by Terraform — so it does not exist on the first
# apply. Two ways to point the alias record at it, both no-ops until the ALB
# exists (the record is simply not created):
#
#   1. Explicit: pass alb_dns_name + alb_zone_id (e.g. from
#      `kubectl get ingress -o jsonpath='{..loadBalancer.ingress[0].hostname}'`).
#   2. Discovery: pass alb_discovery_tags and Terraform looks the ALB up by
#      the tags the controller stamps on it. Note this reads at plan time and
#      FAILS the plan if no ALB matches, so only set it once the Ingress is up.
# ---------------------------------------------------------------------------

variable "alb_dns_name" {
  description = "DNS name of the ALB to alias to (null = no alias record, or use alb_discovery_tags)"
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (required when alb_dns_name is set)"
  type        = string
  default     = null
}

variable "alb_discovery_tags" {
  description = "Tags identifying the controller-created ALB to look up instead of passing alb_dns_name (empty map = no lookup)"
  type        = map(string)
  default     = {}
}

variable "wait_for_certificate_validation" {
  description = "Block apply until ACM reports the certificate ISSUED. Requires the hosted zone's name servers to be delegated at the domain registrar first — leave false on the initial apply, then set true once delegation is in place."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
