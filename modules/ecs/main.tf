data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "sip" {
  #checkov:skip=CKV_AWS_158:AWS-managed encryption sufficient; CMK out of scope
  #checkov:skip=CKV_AWS_338:Retention is intentionally environment-specific (7d nonprod, 30d prod)
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-logs" })
}

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_224:AWS-managed encryption sufficient; CMK out of scope
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-cluster" })
}

locals {
  sip_container_base = {
    name      = "sip"
    image     = var.container_image
    essential = true

    stopTimeout = var.container_stop_timeout

    environment = var.container_environment
    secrets     = var.container_secrets

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.sip.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "sip"
      }
    }
  }
}

resource "aws_ecs_task_definition" "sip_tcp" {
  family                   = "${var.name_prefix}-sip-tcp"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([merge(local.sip_container_base, {
    portMappings = [
      { containerPort = 5060, protocol = "tcp" },
      { containerPort = 5061, protocol = "tcp" },
    ]
  })])

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-tcp-task" })
}


resource "aws_ecs_service" "sip_tcp" {
  name                              = "${var.name_prefix}-sip-tcp"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.sip_tcp.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.deployment_min_healthy_percent
  deployment_maximum_percent         = var.deployment_max_percent

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sip_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.tg_sip_tcp_arn
    container_name   = "sip"
    container_port   = 5060
  }

  load_balancer {
    target_group_arn = var.tg_sip_tls_arn
    container_name   = "sip"
    container_port   = 5061
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-sip-tcp" })

  lifecycle {
    # Auto scaling manages desired_count at runtime; without this Terraform would
    # reset it to the variable value on every apply.
    ignore_changes = [desired_count]
  }
}


resource "aws_appautoscaling_target" "sip_tcp" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.sip_tcp.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "sip_tcp_cpu" {
  name               = "${var.name_prefix}-sip-tcp-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sip_tcp.resource_id
  scalable_dimension = aws_appautoscaling_target.sip_tcp.scalable_dimension
  service_namespace  = aws_appautoscaling_target.sip_tcp.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_scale_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

