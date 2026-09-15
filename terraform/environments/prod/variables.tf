variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

# ---------------------------------------------------------------------------
# DNS & Ingress (E-6)
# ---------------------------------------------------------------------------

variable "domain_name" {
  description = "Apex domain to create a Route 53 hosted zone and ACM certificate for. Empty string disables the DNS module entirely."
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "DNS name of the Ingress-created ALB to alias the app record to (null until the Ingress is deployed)"
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "Route 53 hosted zone ID of the Ingress-created ALB (required when alb_dns_name is set)"
  type        = string
  default     = null
}

variable "alb_discovery_tags" {
  description = "Tags to look the Ingress-created ALB up by instead of passing alb_dns_name. Only set once the ALB exists — the lookup fails the plan otherwise."
  type        = map(string)
  default     = {}
}

variable "wait_for_certificate_validation" {
  description = "Block apply until the ACM certificate is ISSUED (requires registrar delegation of the hosted zone's name servers)"
  type        = bool
  default     = false
}
