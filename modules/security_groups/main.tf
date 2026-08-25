resource "aws_security_group" "nlb" {
  #checkov:skip=CKV2_AWS_5:False positive — SG is attached to the NLB via the nlb module; checkov cannot see cross-module references
  name_prefix = "${var.name_prefix}-nlb-"
  description = "NLB: accepts SIP (UDP/TCP 5060, TLS 5061) from authorized operators only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-nlb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "sip" {
  #checkov:skip=CKV2_AWS_5:False positive — SG is attached to ECS Fargate tasks via the ecs module; checkov cannot see cross-module references
  name_prefix = "${var.name_prefix}-sip-"
  description = "SIP Fargate tasks: accepts SIP traffic from the NLB only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-sip" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  #checkov:skip=CKV2_AWS_5:False positive — SG is attached to the RDS instance via the rds module; checkov cannot see cross-module references
  name_prefix = "${var.name_prefix}-rds-"
  description = "RDS: accepts port 5432 from the SIP component and internal services only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "internal" {
  #checkov:skip=CKV2_AWS_5:False positive — SG is a placeholder for future internal services; attachment happens outside this module
  name_prefix = "${var.name_prefix}-internal-"
  description = "Internal services: accepts traffic from the SIP component"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-internal" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  nlb_ingress_rules = {
    for pair in setproduct(
      var.operator_cidrs,
      [
        { port = 5060, protocol = "udp", label = "sip-udp" },
        { port = 5060, protocol = "tcp", label = "sip-tcp" },
        { port = 5061, protocol = "tcp", label = "sip-tls" },
      ]
    ) :
    "${pair[0]}-${pair[1].label}" => {
      cidr     = pair[0]
      port     = pair[1].port
      protocol = pair[1].protocol
      label    = pair[1].label
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb" {
  for_each = local.nlb_ingress_rules

  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = each.value.protocol
  description       = "SIP ${each.value.label} from operator ${each.value.cidr}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_sip" {
  security_group_id            = aws_security_group.nlb.id
  referenced_security_group_id = aws_security_group.sip.id
  ip_protocol                  = "-1"
  description                  = "Forward SIP traffic to containers"

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-to-sip" })
}

# TCP_UDP target groups require preserve_client_ip = true (AWS does not allow disabling it).
# NLB health checks still originate from the NLB security group, so the NLB SG reference
# covers health check traffic. Actual SIP traffic arrives with the original client IP,
# so operator CIDRs must be explicitly allowed on all SIP ports.
resource "aws_vpc_security_group_ingress_rule" "sip_tcp_from_nlb" {
  for_each = { "5060" = 5060, "5061" = 5061 }

  security_group_id            = aws_security_group.sip.id
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
  description                  = "SIP TCP ${each.key} health checks from the NLB"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-tcp-${each.key}-from-nlb" })
}

locals {
  sip_operator_rules = {
    for pair in setproduct(
      var.operator_cidrs,
      [
        { port = 5060, protocol = "udp", label = "udp-5060" },
        { port = 5060, protocol = "tcp", label = "tcp-5060" },
        { port = 5061, protocol = "tcp", label = "tcp-5061" },
      ]
    ) :
    "${pair[0]}-${pair[1].label}" => {
      cidr     = pair[0]
      port     = pair[1].port
      protocol = pair[1].protocol
      label    = pair[1].label
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "sip_from_operator" {
  for_each = local.sip_operator_rules

  security_group_id = aws_security_group.sip.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = each.value.protocol
  description       = "SIP ${each.value.label} from operator ${each.value.cidr}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "sip_all_out" {
  security_group_id = aws_security_group.sip.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Unrestricted egress: RDS, internal services, VPC endpoints"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-egress-all" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_sip" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.sip.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from the SIP component"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-from-sip" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_internal" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.internal.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from internal services"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-from-internal" })
}

# TODO: ip_protocol = "-1" is a placeholder. Replace with specific port/protocol rules
# once internal service interfaces are defined. Do not go to production in this state.
resource "aws_vpc_security_group_ingress_rule" "internal_from_sip" {
  security_group_id            = aws_security_group.internal.id
  referenced_security_group_id = aws_security_group.sip.id
  ip_protocol                  = "-1"
  description                  = "PLACEHOLDER: all traffic from SIP - restrict by port before going to production"

  tags = merge(var.tags, { Name = "${var.name_prefix}-internal-from-sip" })
}

resource "aws_vpc_security_group_egress_rule" "internal_all_out" {
  security_group_id = aws_security_group.internal.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Unrestricted egress for internal services"

  tags = merge(var.tags, { Name = "${var.name_prefix}-internal-egress-all" })
}

# ---------------------------------------------------------------------------
# rtpengine — media relay for RTP audio (EC2 + EIP, not Fargate)
# ---------------------------------------------------------------------------

resource "aws_security_group" "rtpengine" {
  #checkov:skip=CKV2_AWS_5:False positive — SG is attached to the rtpengine EC2 instance via the rtpengine module; checkov cannot see cross-module references
  name_prefix = "${var.name_prefix}-rtpengine-"
  description = "rtpengine media relay: RTP from clients and ng control from Kamailio"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-rtpengine" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  rtp_operator_rules = {
    for cidr in var.operator_cidrs :
    cidr => { cidr = cidr }
  }
}

# Inbound RTP from softphones/carriers (UDP 10000-20000).
# Each active call uses one port pair; this range supports up to 5000 concurrent calls.
resource "aws_vpc_security_group_ingress_rule" "rtpengine_rtp_from_operator" {
  for_each = local.rtp_operator_rules

  security_group_id = aws_security_group.rtpengine.id
  cidr_ipv4         = each.value.cidr
  from_port         = 10000
  to_port           = 20000
  ip_protocol       = "udp"
  description       = "RTP media from operator ${each.value.cidr}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-rtp-${each.key}" })
}

# Inbound ng control from Kamailio Fargate tasks (UDP 2223).
# Kamailio sends offer/answer commands here to allocate ports and rewrite SDPs.
# Referencing the SIP SG (not a CIDR) means this auto-adapts as tasks scale.
resource "aws_vpc_security_group_ingress_rule" "rtpengine_ng_from_sip" {
  security_group_id            = aws_security_group.rtpengine.id
  referenced_security_group_id = aws_security_group.sip.id
  from_port                    = 2223
  to_port                      = 2223
  ip_protocol                  = "udp"
  description                  = "rtpengine ng control (UDP 2223) from Kamailio"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-ng-from-sip" })
}

# Outbound: send RTP back to clients and reach SSM / NAT for management traffic.
resource "aws_vpc_security_group_egress_rule" "rtpengine_all_out" {
  security_group_id = aws_security_group.rtpengine.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Unrestricted egress: RTP to clients, SSM, internet via NAT"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-egress-all" })
}
