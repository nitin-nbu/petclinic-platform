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

variable "service_names" {
  description = "Microservice names to create one ECR repository each for"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for all repositories (MUTABLE for dev, IMMUTABLE for prod)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either \"MUTABLE\" or \"IMMUTABLE\"."
  }
}

variable "untagged_expire_days" {
  description = "Days after which untagged images are expired by the lifecycle policy"
  type        = number
  default     = 7
}

variable "tagged_image_count" {
  description = "Number of tagged images to retain per repository before older ones are expired"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
