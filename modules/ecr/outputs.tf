output "repository_url" {
  description = "Full ECR repository URL. Use as the base for container_image: <repository_url>:<tag>."
  value       = aws_ecr_repository.sip.repository_url
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.sip.name
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.sip.arn
}
