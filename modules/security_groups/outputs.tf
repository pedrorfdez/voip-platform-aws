output "nlb_sg_id" {
  description = "Security Group ID of the NLB."
  value       = aws_security_group.nlb.id
}

output "sip_sg_id" {
  description = "Security Group ID of the SIP component (Fargate tasks)."
  value       = aws_security_group.sip.id
}

output "rds_sg_id" {
  description = "Security Group ID of the RDS instance."
  value       = aws_security_group.rds.id
}

output "internal_sg_id" {
  description = "Security Group ID for internal services."
  value       = aws_security_group.internal.id
}
