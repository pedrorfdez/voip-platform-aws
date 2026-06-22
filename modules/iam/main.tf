data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# aws:SourceAccount prevents confused deputy: stops tasks from other accounts
# assuming these roles via the shared ecs-tasks.amazonaws.com service principal.
data "aws_iam_policy_document" "ecs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name_prefix        = "${var.name_prefix}-ecs-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  description        = "ECS agent role: ECR pull, CloudWatch Logs, Secrets Manager"

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-execution-role" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  secret_resources = length(var.secret_arns) > 0 ? var.secret_arns : ["*"]
}

data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    sid       = "ReadSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_resources
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "secrets-manager-read"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

resource "aws_iam_role" "task" {
  name_prefix        = "${var.name_prefix}-ecs-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  description        = "SIP container role: ECS Exec and CloudWatch Logs"

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-task-role" })

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid    = "ECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"] # SSM does not support ARN-level restriction for ssmmessages actions.
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # CreateLogGroup intentionally omitted: the log group is created by Terraform in the ecs module.
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}:*",
    ]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "ecs-exec-and-logs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
