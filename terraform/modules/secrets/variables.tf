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

variable "openai_api_key" {
  description = "OpenAI API key for the genai-service, stored in Secrets Manager as petclinic/{env}/openai-api-key. Never hardcode — pass via a gitignored terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
