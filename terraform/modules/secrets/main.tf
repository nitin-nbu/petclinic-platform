locals {
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# Non-RDS application secrets (PETPLAT-33). RDS credentials are owned by the
# rds module (PETPLAT-23) and are never duplicated here.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "openai_api_key" {
  name        = "petclinic/${var.environment}/openai-api-key"
  description = "OpenAI API key for the genai-service in ${var.environment}"

  # dev: force-delete on destroy so a same-day recreate (e.g. tearing the
  # environment down overnight for cost) never collides with a pending
  # 30-day soft-delete on this secret name. prod keeps the default recovery
  # window as a safety net against accidental deletion.
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}
