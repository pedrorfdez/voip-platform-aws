resource "aws_eip" "nlb" {
  #checkov:skip=CKV2_AWS_19:False positive — EIPs are attached to the NLB via subnet_mapping, not to EC2 instances
  for_each = var.public_subnets_by_az

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nlb-eip-${each.key}" })
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_152:Cross-zone LB intentionally disabled; SIP is stateful and requires AZ affinity
  #checkov:skip=CKV_AWS_150:Deletion protection configurable via var.enable_deletion_protection; enabled in prod
  #checkov:skip=CKV_AWS_91:TODO — NLB access logs to S3 not yet implemented
  # AWS provider enforces a hard 6-char limit on name_prefix for LBs (6 + 26-char suffix = 32 = AWS max).
  name               = "${substr(var.name_prefix, 0, 28)}-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [var.nlb_sg_id]

  enable_deletion_protection = var.enable_deletion_protection

  dynamic "subnet_mapping" {
    for_each = aws_eip.nlb
    content {
      subnet_id     = var.public_subnets_by_az[subnet_mapping.key]
      allocation_id = subnet_mapping.value.id
    }
  }

  # Disabled so a SIP session that enters via AZ-a is never rerouted to AZ-b mid-call.
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb" })
}

resource "aws_lb_target_group" "sip_tcp" {
  # TCP_UDP on port 5060 handles both TCP and UDP SIP traffic with a single listener.
  # AWS NLBs do not allow separate TCP and UDP listeners on the same port.
  name                 = "${substr(var.name_prefix, 0, 28)}-tcp"
  port                 = 5060
  protocol             = "TCP_UDP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  # TCP_UDP requires preserve_client_ip = true (AWS default; cannot be disabled).
  # The Fargate SIP SG allows ingress from operator_cidrs so the container
  # accepts packets that arrive with the original client IP as source.

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.health_check_port
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_threshold
    interval            = var.health_check_interval
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-sip-tcp" })
}

resource "aws_lb_target_group" "sip_tls" {
  name                 = "${substr(var.name_prefix, 0, 28)}-tls"
  port                 = 5061
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay
  preserve_client_ip   = "false" # same reasoning as sip_tcp

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "5060"
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_threshold
    interval            = var.health_check_interval
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-sip-tls" })
}

resource "aws_lb_listener" "sip_tcp" {
  load_balancer_arn = aws_lb.this.arn
  port              = 5060
  protocol          = "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sip_tcp.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-listener-sip-tcp" })
}

resource "aws_lb_listener" "sip_tls" {
  #checkov:skip=CKV_AWS_103:False positive — ssl_policy ELBSecurityPolicy-TLS13-1-2-2021-06 is set when certificate_arn is provided; checkov cannot evaluate the conditional
  load_balancer_arn = aws_lb.this.arn
  port              = 5061

  protocol        = var.certificate_arn != "" ? "TLS" : "TCP"
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : null
  # Only applies when protocol is TLS.
  ssl_policy = var.certificate_arn != "" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sip_tls.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-listener-sip-tls" })
}
