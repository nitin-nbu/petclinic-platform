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

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (public subnets — see ADR-0001)"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID (allows 3306 from EKS nodes only — see VPC module)"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database created on the instance"
  type        = string
  default     = "petclinic"
}

variable "master_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "petclinic"

  validation {
    condition     = !contains(["admin", "root", "rdsadmin", "master"], lower(var.master_username))
    error_message = "master_username must not be an AWS/MySQL-reserved username (admin, root, rdsadmin, master)."
  }
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"

  validation {
    condition     = can(regex("^8\\.[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a MySQL 8.x version (e.g. \"8.0\" or \"8.0.35\") to match the module's mysql8.0 parameter group family."
  }
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

# Defaults intentionally equal to allocated_storage (20 GB) — matches the
# technical spec's free-tier sizing exactly. Storage autoscaling only takes
# effect once this is raised above allocated_storage.
variable "max_allocated_storage" {
  description = "Max autoscale storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Whether to deploy a Multi-AZ standby instance"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days (AWS RDS limits; 0 disables automated backups)."
  }
}

variable "skip_final_snapshot" {
  description = "Skip taking a final snapshot when the instance is deleted"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection on the RDS instance"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
