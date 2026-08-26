output "private_ip" {
  description = "Private IP of the rtpengine instance. Used by Kamailio as RTPENGINE_HOST to reach the ng control socket on UDP 2223."
  value       = aws_instance.rtpengine.private_ip
}

output "public_ip" {
  description = "Elastic IP (EIP) of the rtpengine instance. Softphones send RTP to this address. Informational — not used by other modules."
  value       = aws_eip.rtpengine.public_ip
}

output "instance_id" {
  description = "EC2 instance ID. Use with 'aws ssm start-session --target <id>' to get a shell without SSH."
  value       = aws_instance.rtpengine.id
}
