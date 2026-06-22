output "nlb_arn" {
  description = "NLB ARN."
  value       = aws_lb.this.arn
}

output "nlb_arn_suffix" {
  description = "NLB ARN suffix (net/<name>/<id>). Used as a CloudWatch alarm dimension."
  value       = aws_lb.this.arn_suffix
}

output "tg_sip_udp_arn_suffix" {
  description = "UDP target group ARN suffix. Used as a CloudWatch alarm dimension."
  value       = aws_lb_target_group.sip_udp.arn_suffix
}

output "tg_sip_tcp_arn_suffix" {
  description = "TCP target group ARN suffix. Used as a CloudWatch alarm dimension."
  value       = aws_lb_target_group.sip_tcp.arn_suffix
}

output "tg_sip_tls_arn_suffix" {
  description = "TLS target group ARN suffix. Used as a CloudWatch alarm dimension."
  value       = aws_lb_target_group.sip_tls.arn_suffix
}

output "nlb_dns_name" {
  description = "NLB DNS name. Use for DNS records or testing."
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "NLB hosted zone ID. Required for Route 53 alias records."
  value       = aws_lb.this.zone_id
}

output "tg_sip_udp_arn" {
  description = "UDP 5060 target group ARN. Passed by the ecs module to register tasks."
  value       = aws_lb_target_group.sip_udp.arn
}

output "tg_sip_tcp_arn" {
  description = "TCP 5060 target group ARN."
  value       = aws_lb_target_group.sip_tcp.arn
}

output "tg_sip_tls_arn" {
  description = "TCP/TLS 5061 target group ARN."
  value       = aws_lb_target_group.sip_tls.arn
}

output "elastic_ip_addresses" {
  description = "List of static public IPs of the NLB (one per AZ) to share with SIP operators."
  value       = [for eip in aws_eip.nlb : eip.public_ip]
}

output "elastic_ips_by_az" {
  description = "Map of { az => public_ip } for the NLB Elastic IPs."
  value       = { for az, eip in aws_eip.nlb : az => eip.public_ip }
}
