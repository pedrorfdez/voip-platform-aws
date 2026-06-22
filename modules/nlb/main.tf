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

resource "aws_lb_target_group" "sip_udp" {
  # Same 6-char name_prefix limit applies to target groups.
  name                 = "${substr(var.name_prefix, 0, 28)}-udp"
  port                 = 5060
  protocol             = "UDP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.udp_health_check_port
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_threshold
    interval            = var.health_check_interval
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-sip-udp" })
}

resource "aws_lb_target_group" "sip_tcp" {
  name                 = "${substr(var.name_prefix, 0, 28)}-tcp"
  port                 = 5060
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  # false: the NLB rewrites source IP to its own private IP before forwarding.
  # The container sees the NLB's IP, which is covered by the NLB SG reference in
  # the SIP SG ingress rule. With true, the container would see the operator's IP
  # and the SG reference would never match.
  preserve_client_ip = "false"

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
    port                = var.health_check_port
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_threshold
    interval            = var.health_check_interval
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-sip-tls" })
}

resource "aws_lb_listener" "sip_udp" {
  load_balancer_arn = aws_lb.this.arn
  port              = 5060
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sip_udp.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-listener-sip-udp" })
}

resource "aws_lb_listener" "sip_tcp" {
  load_balancer_arn = aws_lb.this.arn
  port              = 5060
  protocol          = "TCP"

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
