output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "task_definition_tcp_arn" {
  description = "ARN of the active TCP/TLS task definition revision."
  value       = aws_ecs_task_definition.sip_tcp.arn
}

output "task_definition_udp_arn" {
  description = "ARN of the active UDP task definition revision."
  value       = aws_ecs_task_definition.sip_udp.arn
}

output "service_tcp_name" {
  description = "Name of the ECS TCP/TLS service."
  value       = aws_ecs_service.sip_tcp.name
}

output "service_udp_name" {
  description = "Name of the ECS UDP service."
  value       = aws_ecs_service.sip_udp.name
}

output "log_group_name" {
  description = "CloudWatch log group name where the container writes its logs."
  value       = aws_cloudwatch_log_group.sip.name
}
