output "ecr_repository_url" {
  description = "ECR repository URL. Use as container_image base in nonprod.tfvars: <url>:<tag>."
  value       = module.ecr.repository_url
}

output "nlb_dns_name" {
  description = "NLB DNS name."
  value       = module.nlb.nlb_dns_name
}

output "elastic_ip_addresses" {
  description = "Static public IPs of the NLB (one per AZ). Share with SIP operators for their allowlists."
  value       = module.nlb.elastic_ip_addresses
}

output "elastic_ips_by_az" {
  description = "Map of { az => ip } for the NLB Elastic IPs."
  value       = module.nlb.elastic_ips_by_az
}

output "ecs_cluster_name" {
  description = "ECS cluster name. Required for aws ecs execute-command."
  value       = module.ecs.cluster_name
}

output "service_tcp_name" {
  description = "Name of the ECS TCP/TLS service."
  value       = module.ecs.service_tcp_name
}


output "log_group_name" {
  description = "CloudWatch log group where the SIP container writes its logs."
  value       = module.ecs.log_group_name
}

output "rds_identifier" {
  description = "RDS instance identifier (for AWS console and alarms)."
  value       = module.rds.db_identifier
}

output "rds_address" {
  description = "Private RDS hostname (accessible only from within the VPC)."
  value       = module.rds.db_address
  sensitive   = true
}
