locals {
  name_prefix = "ringr-sip-${var.environment}"

  common_tags = {
    Project     = "ringr-sip"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix                = local.name_prefix
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  public_subnet_cidrs        = var.public_subnet_cidrs
  private_subnet_cidrs       = var.private_subnet_cidrs
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  aws_region                 = var.aws_region
  tags                       = {}
}

module "security_groups" {
  source = "../../modules/security_groups"

  name_prefix    = local.name_prefix
  vpc_id         = module.network.vpc_id
  operator_cidrs = var.operator_cidrs
  tags           = {}
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix
  secret_arns = [module.rds.secret_arn]
  tags        = {}
}

module "nlb" {
  source = "../../modules/nlb"

  name_prefix                = local.name_prefix
  vpc_id                     = module.network.vpc_id
  public_subnets_by_az       = module.network.public_subnets_by_az
  nlb_sg_id                  = module.security_groups.nlb_sg_id
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = var.nlb_deletion_protection
  tags                       = {}
}

module "rds" {
  source = "../../modules/rds"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id

  instance_class               = var.rds_instance_class
  multi_az                     = var.rds_multi_az
  backup_retention_days        = var.rds_backup_retention_days
  deletion_protection          = var.rds_deletion_protection
  skip_final_snapshot          = var.rds_skip_final_snapshot
  performance_insights_enabled = var.rds_performance_insights_enabled
  max_allocated_storage        = var.rds_max_allocated_storage
  backup_window                = var.rds_backup_window
  maintenance_window           = var.rds_maintenance_window
  log_retention_days           = var.rds_log_retention_days
  tags                         = {}
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = local.name_prefix

  nlb_arn_suffix        = module.nlb.nlb_arn_suffix
  tg_sip_udp_arn_suffix = module.nlb.tg_sip_udp_arn_suffix
  tg_sip_tcp_arn_suffix = module.nlb.tg_sip_tcp_arn_suffix
  tg_sip_tls_arn_suffix = module.nlb.tg_sip_tls_arn_suffix

  ecs_cluster_name     = module.ecs.cluster_name
  ecs_service_tcp_name = module.ecs.service_tcp_name
  ecs_service_udp_name = module.ecs.service_udp_name

  rds_identifier            = module.rds.db_identifier
  rds_free_storage_alarm_gb = var.rds_free_storage_alarm_gb

  alarm_actions = var.alarm_actions
  tags          = {}
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix             = local.name_prefix
  private_subnet_ids      = module.network.private_subnet_ids
  sip_sg_id               = module.security_groups.sip_sg_id
  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn
  tg_sip_tcp_arn          = module.nlb.tg_sip_tcp_arn
  tg_sip_tls_arn          = module.nlb.tg_sip_tls_arn
  tg_sip_udp_arn          = module.nlb.tg_sip_udp_arn

  container_image = var.container_image

  container_environment = [
    { name = "DB_HOST", value = module.rds.db_address },
    { name = "DB_PORT", value = tostring(module.rds.db_port) },
    { name = "DB_NAME", value = module.rds.db_name },
  ]

  container_secrets = [
    { name = "DB_PASSWORD", valueFrom = "${module.rds.secret_arn}:password::" },
  ]

  task_cpu                       = var.ecs_task_cpu
  task_memory                    = var.ecs_task_memory
  desired_count                  = var.ecs_desired_count
  min_capacity                   = var.ecs_min_capacity
  max_capacity                   = var.ecs_max_capacity
  cpu_scale_target               = var.ecs_cpu_scale_target
  deployment_min_healthy_percent = var.ecs_min_healthy_percent
  deployment_max_percent         = var.ecs_max_percent
  log_retention_days             = var.ecs_log_retention_days
  tags                           = {}
}
