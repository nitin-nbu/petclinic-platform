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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "exactly 2 public subnet CIDRs are required (one per AZ)."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "exactly 2 availability zones are required."
  }
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention period (days) for VPC flow logs"
  type        = number
  default     = 14
}
