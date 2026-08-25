# --- IAM: SSM access only, no SSH keys needed ---

resource "aws_iam_role" "rtpengine" {
  name_prefix = "${var.name_prefix}-rtpengine-"
  description = "Allows the rtpengine EC2 instance to register with SSM (no SSH required)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-role" })
}

resource "aws_iam_role_policy_attachment" "rtpengine_ssm" {
  role       = aws_iam_role.rtpengine.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "rtpengine" {
  name_prefix = "${var.name_prefix}-rtpengine-"
  role        = aws_iam_role.rtpengine.name

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-profile" })
}

# --- AMI: latest Debian 12 (Bookworm) ---
# Debian's official AWS account ID is 136693071363.
# Using a data source avoids hardcoding AMI IDs that differ per region and change with updates.
data "aws_ami" "debian_12" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- EIP: allocated before the instance so its value is known at apply time ---
# This lets us inject the EIP into the user_data template at launch.
# The instance itself has no public IP — AWS routes EIP traffic directly to
# the private IP via 1:1 NAT at the network edge, bypassing the routing table.
resource "aws_eip" "rtpengine" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rtpengine-eip" })
}

# --- EC2 instance ---
resource "aws_instance" "rtpengine" {
  ami                    = data.aws_ami.debian_12.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.rtpengine_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.rtpengine.name

  # Inject EIP and port range into the setup script at launch.
  # PRIVATE_IP is fetched from instance metadata inside the script —
  # it is not known to Terraform until after the instance starts.
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    eip      = aws_eip.rtpengine.public_ip
    port_min = var.rtp_port_min
    port_max = var.rtp_port_max
  })

  # Replace the instance (not update in-place) if user_data changes,
  # so the config is always re-applied from scratch.
  user_data_replace_on_change = true

  # Disable detailed monitoring to reduce cost in nonprod.
  # Enable in production for 1-minute metric granularity.
  monitoring = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-rtpengine" })
}

# --- EIP association: attach the pre-allocated EIP to the instance ---
resource "aws_eip_association" "rtpengine" {
  instance_id   = aws_instance.rtpengine.id
  allocation_id = aws_eip.rtpengine.allocation_id
}
