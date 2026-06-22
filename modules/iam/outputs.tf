output "task_execution_role_arn" {
  description = "ARN of the task execution role. Pass to the ECS task definition."
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of the task execution role."
  value       = aws_iam_role.task_execution.name
}

output "task_role_arn" {
  description = "ARN of the task role. Pass to the ECS task definition."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role."
  value       = aws_iam_role.task.name
}
