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

resource "aws_vpc_security_group_ingress_rule" "sip_tcp_from_nlb" {
  for_each = { "5060" = 5060, "5061" = 5061 }

  security_group_id            = aws_security_group.sip.id
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
  description                  = "SIP TCP ${each.key} from the NLB"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-tcp-${each.key}-from-nlb" })
}

# NLBs always preserve source IP for UDP — the container sees the operator's IP, not the
# NLB's. An SG reference to the NLB SG would never match; operator CIDRs are required.
resource "aws_vpc_security_group_ingress_rule" "sip_udp_from_operator" {
  for_each = toset(var.operator_cidrs)

  security_group_id = aws_security_group.sip.id
  cidr_ipv4         = each.value
  from_port         = 5060
  to_port           = 5060
  ip_protocol       = "udp"
  description       = "SIP UDP 5060 from operator ${each.value} (NLB preserves client IP for UDP)"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-udp-${each.value}" })
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
  description                  = "PLACEHOLDER: all traffic from SIP — restrict by port before going to production"

  tags = merge(var.tags, { Name = "${var.name_prefix}-internal-from-sip" })
}

resource "aws_vpc_security_group_egress_rule" "internal_all_out" {
  security_group_id = aws_security_group.internal.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Unrestricted egress for internal services"

  tags = merge(var.tags, { Name = "${var.name_prefix}-internal-egress-all" })
}
