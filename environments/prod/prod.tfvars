###############################################################################
# prod.tfvars — valores de producción
# Uso: terraform apply -var-file="prod.tfvars"
###############################################################################

environment = "prod"
aws_region  = "eu-west-1"

# --- Red ---
availability_zones   = ["eu-west-1a", "eu-west-1b"]
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

single_nat_gateway         = false # un NAT por AZ: si una AZ falla, la otra sigue funcionando
enable_interface_endpoints = true  # tráfico a ECR/SSM/Secrets por red interna de AWS

# --- SIP ---
# PLACEHOLDER: sustituir por los rangos CIDR reales de los operadores/trunks SIP.
# Ejemplo: ["203.0.113.0/24", "198.51.100.16/28"]
operator_cidrs = ["203.0.113.0/24"]

# PLACEHOLDER: ARN del certificado ACM para TLS en el puerto 5061.
# Si se deja vacío, el listener 5061 usa TCP puro (el contenedor termina TLS).
certificate_arn = ""

# --- Contenedor ---
# PLACEHOLDER: sustituir por la URI real de ECR tras construir y publicar la imagen.
# Ejemplo: "123456789012.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip:1.0.0"
container_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip:latest"

# --- ECS ---
ecs_task_cpu    = 512  # 0.5 vCPU
ecs_task_memory = 1024 # 1 GB

ecs_desired_count = 2 # 2 tareas TCP + 2 tareas UDP = 4 tareas totales en prod
ecs_min_capacity  = 2
ecs_max_capacity  = 10

ecs_cpu_scale_target    = 70  # escala hacia arriba cuando el CPU medio supera el 70%
ecs_min_healthy_percent = 100 # nunca reduce capacidad durante despliegues (zero-downtime)
ecs_max_percent         = 200 # puede lanzar el doble de tareas durante el rolling update

ecs_log_retention_days = 30

# --- RDS ---
rds_instance_class = "db.t3.medium"
rds_multi_az       = true # standby en segunda AZ, failover automático < 60s

rds_backup_retention_days        = 7
rds_deletion_protection          = true  # protege contra borrado accidental en prod
rds_skip_final_snapshot          = false # guarda un snapshot antes de destruir
rds_performance_insights_enabled = false # db.t3.medium soporta PI; activar cuando se necesite
rds_max_allocated_storage        = 100   # storage autoscaling: crece hasta 100 GB automáticamente
rds_log_retention_days           = 30

# --- NLB ---
nlb_deletion_protection = true # impide terraform destroy accidental en prod

# --- Monitoring ---
# alarm_actions = ["arn:aws:sns:eu-west-1:ACCOUNT_ID:ringr-sip-alerts"]
# Descomentar y sustituir ACCOUNT_ID por el ID de la cuenta AWS una vez creado el topic SNS.
alarm_actions             = []
rds_free_storage_alarm_gb = 5
