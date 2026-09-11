locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # RDS engine_version "8.0" maps to parameter group family "mysql8.0".
  parameter_group_family = "mysql8.0"
}

# ---------------------------------------------------------------------------
# Master password (PETPLAT-23) — generated, never hardcoded. override_special
# excludes '/', '@', '"', and space, which RDS rejects in master passwords.
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>?"
}

# ---------------------------------------------------------------------------
# Secrets Manager (PETPLAT-23) — single JSON secret with username + password.
# RDS credentials only; all other application secrets live in the `secrets`
# module (PETPLAT-33).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "petclinic/${var.environment}/rds-credentials"
  description = "RDS master credentials for the ${var.environment} petclinic database"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}

# ---------------------------------------------------------------------------
# DB subnet group + parameter group (PETPLAT-22)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.name_prefix}-mysql8"
  family = local.parameter_group_family

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# RDS MySQL instance (PETPLAT-22) — single shared `petclinic` database for
# customers, visits, and vets services. Not publicly accessible: even though
# subnets are public (see ADR-0001), the RDS SG is the enforcement boundary
# and the instance itself has no need for a public IP.
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql"
  })

  # AWS auto-applies minor-version upgrades out-of-band (RDS default behavior),
  # which would otherwise show as perpetual drift against var.engine_version
  # ("8.0") on every plan.
  lifecycle {
    ignore_changes = [engine_version]

    precondition {
      condition     = var.max_allocated_storage >= var.allocated_storage
      error_message = "max_allocated_storage must be greater than or equal to allocated_storage."
    }
  }
}
