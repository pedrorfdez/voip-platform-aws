environment = "nonprod"
aws_region  = "eu-west-1"

# --- Network ---
# Different CIDR from prod (10.0.x.x) to avoid overlap if VPC Peering or
# Transit Gateway is added between environments in the future.
availability_zones   = ["eu-west-1a", "eu-west-1b"]
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

single_nat_gateway         = true  # one shared NAT: ~$32/mo vs ~$64/mo with one per AZ
enable_interface_endpoints = false # no Interface endpoints: traffic goes via NAT, saves ~$87/mo

# --- SIP ---
# Replace with your actual home/mobile public IP before testing.
# Find it at: https://checkip.amazonaws.com
operator_cidrs  = ["0.0.0.0/0"]
certificate_arn = ""

# --- Container ---
# Fill in after `terraform apply` using: terraform output ecr_repository_url
container_image = "236285729160.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip-nonprod-sip:9a5a4e0"

# --- ECS ---
ecs_task_cpu    = 256 # 0.25 vCPU — Fargate minimum; enough for testing
ecs_task_memory = 512 # 512 MB — minimum for cpu=256

ecs_desired_count = 1 # 1 TCP task + 1 UDP task = 2 total tasks in nonprod
ecs_min_capacity  = 1
ecs_max_capacity  = 3

ecs_cpu_scale_target    = 80  # higher threshold: less aggressive scaling in nonprod
ecs_min_healthy_percent = 0   # allows stopping the old task before starting the new one
ecs_max_percent         = 100 # avoids launching extra tasks during deployment (cost saving)

ecs_log_retention_days = 7

# --- RDS ---
rds_instance_class = "db.t3.micro" # minimum instance; does not support Performance Insights
rds_multi_az       = false         # no standby; if the AZ fails the DB is unavailable

rds_backup_retention_days        = 1     # 1 day: enough to recover from test errors
rds_deletion_protection          = false # allows destroying the instance in nonprod without extra steps
rds_skip_final_snapshot          = true  # no snapshot on destroy (test data, not critical)
rds_performance_insights_enabled = false # not available on db.t3.micro
rds_max_allocated_storage        = 0     # storage autoscaling disabled in nonprod
rds_log_retention_days           = 7

# --- NLB ---
nlb_deletion_protection = false # allows terraform destroy in nonprod without extra steps
nlb_cross_zone_lb       = true  # 1 task can land in either AZ; cross-zone ensures it's always reachable

# --- Monitoring ---
alarm_actions             = [] # no notifications in nonprod; alarms visible in CloudWatch console
rds_free_storage_alarm_gb = 2
