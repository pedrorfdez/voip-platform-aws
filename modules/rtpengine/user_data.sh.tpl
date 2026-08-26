#!/bin/bash
set -e
exec > /var/log/rtpengine-setup.log 2>&1

echo "=== rtpengine setup started ==="

# --- Fetch private IP via IMDSv2 ---
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/local-ipv4")
echo "Private IP: $PRIVATE_IP"
echo "EIP (from Terraform): ${eip}"

# --- Install SSM agent FIRST ---
# This ensures we can always SSM into the instance to debug failures below.
cd /tmp
wget -q "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb"
dpkg -i amazon-ssm-agent.deb
rm amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
echo "SSM agent running: $(systemctl is-active amazon-ssm-agent)"

# --- Add non-free repositories ---
# Debian 12 cloud images ship a minimal sources.list. rtpengine lives in the
# standard 'main' repo but some dependencies may require 'contrib non-free'.
# Adding it unconditionally is safe and ensures apt-get can resolve everything.
cat > /etc/apt/sources.list.d/non-free.list <<'EOF'
deb http://deb.debian.org/debian bookworm contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security contrib non-free
EOF

# --- Install rtpengine ---
apt-get update -y
apt-get install -y rtpengine

# --- Write rtpengine config ---
# interface = PRIVATE_IP!EIP tells rtpengine:
#   "bind RTP sockets on the private IP, but advertise the EIP in rewritten SDPs"
# This is what makes NAT traversal work: softphones send RTP to the EIP,
# which AWS routes to the instance's private IP.
mkdir -p /etc/rtpengine
cat > /etc/rtpengine/rtpengine.conf <<EOF
[rtpengine]
interface = $PRIVATE_IP!${eip}
listen-ng = 0.0.0.0:2223
port-min = ${port_min}
port-max = ${port_max}
log-level = 6
log-facility = local0
foreground = false
pidfile = /run/rtpengine/rtpengine.pid
EOF

echo "Config written:"
cat /etc/rtpengine/rtpengine.conf

# --- Start rtpengine ---
systemctl enable rtpengine
systemctl start rtpengine
echo "rtpengine running: $(systemctl is-active rtpengine)"

echo "=== rtpengine setup complete ==="
