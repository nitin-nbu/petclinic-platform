output "endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port (3306)"
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.this.id
}

output "secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}
