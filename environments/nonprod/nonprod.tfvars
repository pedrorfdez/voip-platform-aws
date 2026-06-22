###############################################################################
# nonprod.tfvars — valores de staging/desarrollo
# Uso: terraform apply -var-file="nonprod.tfvars"
#
# Objetivo: misma arquitectura que prod, mínimo coste.
# Diferencias clave: un solo NAT, sin Interface endpoints, RDS sin Multi-AZ,
# una tarea por servicio y despliegue con posible downtime breve.
###############################################################################

environment = "nonprod"
aws_region  = "eu-west-1"

# --- Red ---
# CIDR distinto al de prod (10.0.x.x) para evitar solapamiento si en el futuro
# se añade VPC Peering o Transit Gateway entre entornos.
availability_zones   = ["eu-west-1a", "eu-west-1b"]
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

single_nat_gateway         = true  # ahorro: ~$32/mes vs ~$64/mes con NAT por AZ
enable_interface_endpoints = false # ahorro: ~$87/mes en Interface endpoints; tráfico sale por NAT

# --- SIP ---
# PLACEHOLDER: sustituir por los rangos CIDR de prueba o los mismos que prod.
operator_cidrs  = ["203.0.113.0/24"]
certificate_arn = ""

# --- Contenedor ---
# PLACEHOLDER: sustituir por la URI real de ECR.
container_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip:latest"

# --- ECS ---
ecs_task_cpu    = 256 # 0.25 vCPU — mínimo Fargate; suficiente para pruebas
ecs_task_memory = 512 # 512 MB — mínimo para cpu=256

ecs_desired_count = 1 # 1 tarea TCP + 1 tarea UDP = 2 tareas totales en nonprod
ecs_min_capacity  = 1
ecs_max_capacity  = 3

ecs_cpu_scale_target    = 80  # umbral más alto: no escalar tan agresivamente en nonprod
ecs_min_healthy_percent = 0   # permite parar la tarea vieja antes de lanzar la nueva
ecs_max_percent         = 100 # evita lanzar tareas extra durante el despliegue (ahorro)

ecs_log_retention_days = 7 # retención más corta para reducir coste de almacenamiento en CW

# --- RDS ---
rds_instance_class = "db.t3.micro" # instancia mínima; no soporta Performance Insights
rds_multi_az       = false         # sin standby; si la AZ falla, la BD no está disponible

rds_backup_retention_days        = 1     # 1 día de retención: suficiente para recuperarse de errores de prueba
rds_deletion_protection          = false # permite destruir la instancia en nonprod sin pasos extra
rds_skip_final_snapshot          = true  # no guarda snapshot al destruir (datos de prueba, no críticos)
rds_performance_insights_enabled = false # no disponible en db.t3.micro
rds_max_allocated_storage        = 0     # storage autoscaling desactivado en nonprod (datos de prueba)
rds_log_retention_days           = 7     # misma retención que los logs ECS en nonprod

# --- NLB ---
nlb_deletion_protection = false # permite terraform destroy en nonprod sin pasos extra

# --- Monitoring ---
alarm_actions             = [] # sin notificaciones en nonprod; alarmas visibles en consola CW
rds_free_storage_alarm_gb = 2  # umbral más bajo en nonprod (disco más pequeño)
