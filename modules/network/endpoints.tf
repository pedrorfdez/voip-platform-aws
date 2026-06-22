# Gateway endpoint for S3 is always created: ECR stores image layers in S3, so without
# this endpoint image pulls from Fargate would go through the NAT Gateway. It is free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [for rt in aws_route_table.private : rt.id]

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-s3" })
}

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name_prefix = "${var.name_prefix}-vpce-"
  description = "Allows HTTPS from within the VPC to Interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from within the VPC to Interface VPC endpoints"

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-https-in" })
}

resource "aws_vpc_security_group_egress_rule" "endpoints_all_out" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress to AWS services via VPC endpoints"

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-egress-all" })
}

# Interface endpoints required to run and operate Fargate without internet access:
#   ecr.api / ecr.dkr : pull container images from ECR
#   logs              : send logs to CloudWatch
#   ssm / ssmmessages : operational access via SSM / ECS Exec (no SSH)
#   secretsmanager    : inject database credentials into the container
#
# Only created when enable_interface_endpoints = true.
# With false, traffic to these services goes via the NAT Gateway (functional
# but has per-GB cost and is less secure).
locals {
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "ssm",
    "ssmmessages",
    "secretsmanager",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(local.interface_endpoints) : toset([])

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [for s in aws_subnet.private : s.id]
  # When count = 0 the SG does not exist; this for expression returns an empty list without error.
  security_group_ids  = [for sg in aws_security_group.endpoints : sg.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}
