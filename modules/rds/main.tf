resource "aws_cloudwatch_log_group" "rds_postgresql" {
  #checkov:skip=CKV_AWS_158:AWS-managed encryption sufficient; CMK out of scope
  #checkov:skip=CKV_AWS_338:Retention is intentionally environment-specific (7d nonprod, 30d prod)
  name              = "/aws/rds/instance/${var.name_prefix}-rds/postgresql"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-logs-postgresql" })
}

resource "aws_cloudwatch_log_group" "rds_upgrade" {
  #checkov:skip=CKV_AWS_158:AWS-managed encryption sufficient; CMK out of scope
  #checkov:skip=CKV_AWS_338:Retention is intentionally environment-specific (7d nonprod, 30d prod)
  name              = "/aws/rds/instance/${var.name_prefix}-rds/upgrade"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-logs-upgrade" })
}

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name_prefix}-rds-"
  subnet_ids  = var.private_subnet_ids
  description = "Private subnets for RDS ${var.name_prefix}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-subnet-group" })
}

# override_special: excludes characters that require escaping in connection strings
# (@, /, \, ") and cause parsing failures in connection URLs.
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Without a unique suffix a second `terraform destroy` fails because AWS rejects
# a snapshot name that already exists from the previous destroy cycle.
resource "random_id" "snapshot_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db" {
  #checkov:skip=CKV_AWS_149:AWS-managed encryption sufficient; CMK out of scope
  #checkov:skip=CKV2_AWS_57:TODO — automatic rotation requires a Lambda rotator function
  name_prefix             = "${var.name_prefix}-rds-"
  description             = "RDS PostgreSQL credentials for ${var.name_prefix}"
  recovery_window_in_days = 7

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-secret" })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-rds"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az            = var.multi_az
  publicly_accessible = false

  auto_minor_version_upgrade           = true
  copy_tags_to_snapshot                = true
  iam_database_authentication_enabled  = true

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled = var.performance_insights_enabled #checkov:skip=CKV_AWS_354:AWS-managed encryption sufficient; CMK out of scope

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.name_prefix}-rds-final-${random_id.snapshot_suffix.hex}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds" })

  # Log groups must exist before RDS starts exporting; otherwise RDS auto-creates them
  # with infinite retention outside Terraform state.
  depends_on = [aws_cloudwatch_log_group.rds_postgresql, aws_cloudwatch_log_group.rds_upgrade]

  lifecycle {
    # If the password is rotated externally (Secrets Manager rotation), Terraform
    # must not revert it to the original value on the next apply.
    ignore_changes = [password]
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  })
}
