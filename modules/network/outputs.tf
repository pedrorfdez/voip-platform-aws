output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (used by the NLB)."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (used by Fargate, RDS, and internal services)."
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnets_by_az" {
  description = "Map of { az => subnet_id } for public subnets."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnets_by_az" {
  description = "Map of { az => subnet_id } for private subnets."
  value       = { for az, s in aws_subnet.private : az => s.id }
}
