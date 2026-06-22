output "db_address" {
  description = "RDS instance hostname (no port). Pass as DB_HOST to the ECS container."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "PostgreSQL port (5432)."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name."
  value       = aws_db_instance.this.db_name
}

output "secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret that holds the connection credentials.
    Two uses:
    1. Pass to module.iam (secret_arns) so the task execution role can read it.
    2. Pass to module.ecs (container_secrets) as valueFrom to inject individual
       fields, e.g. "$${secret_arn}:password::" injects only the password.
  EOT
  value       = aws_secretsmanager_secret.db.arn
}

output "db_identifier" {
  description = "RDS instance identifier. Used in AWS console URLs and CloudWatch alarm dimensions."
  value       = aws_db_instance.this.identifier
}
