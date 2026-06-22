# Módulo: network

Crea la base de red de la plataforma SIP: VPC, subredes públicas/privadas en
múltiples AZ, Internet Gateway, NAT Gateway(s), tablas de ruta y VPC Endpoints.

> Construido con recursos del provider `hashicorp/aws` directamente (no con el
> módulo de comunidad `terraform-aws-modules/vpc`) para hacer explícitas las
> decisiones de red. En producción podría sustituirse por el módulo oficial.

## Qué crea

- **VPC** con DNS habilitado (necesario para los Interface endpoints).
- **Subredes públicas** (una por AZ): alojan el NLB y los NAT Gateway.
- **Subredes privadas** (una por AZ): alojan ECS Fargate, RDS y servicios internos.
- **Internet Gateway** + ruta por defecto para las subredes públicas.
- **NAT Gateway**: uno por AZ (HA) o uno único compartido (ahorro), según flag.
- **Tablas de ruta privadas una por AZ**, cada una saliendo por el NAT de su zona.
- **VPC Endpoints**: S3 (Gateway, gratis) + ECR, CloudWatch Logs, SSM y Secrets
  Manager (Interface), para operar Fargate sin salir a Internet.

## Decisiones clave

- **`for_each` indexado por AZ** (no por índice numérico) para que reordenar la
  lista de AZs no destruya/recree subredes en el state.
- **`single_nat_gateway`**: materializa el ahorro de costes en entornos no
  productivos sin cambiar la arquitectura (false en prod, true en nonprod).
- **Tabla de ruta privada por AZ**: evita que un fallo de AZ deje sin salida al
  resto cuando hay un NAT por zona.

## Variables principales

| Variable | Descripción | Ejemplo |
|---|---|---|
| `name_prefix` | Prefijo de nombres/tags | `ringr-sip-prod` |
| `vpc_cidr` | CIDR de la VPC | `10.0.0.0/16` |
| `availability_zones` | AZs (mínimo 2) | `["eu-west-1a","eu-west-1b"]` |
| `public_subnet_cidrs` | CIDRs públicos (orden = AZs) | `["10.0.0.0/24","10.0.1.0/24"]` |
| `private_subnet_cidrs` | CIDRs privados (orden = AZs) | `["10.0.10.0/24","10.0.11.0/24"]` |
| `single_nat_gateway` | Un único NAT compartido | `false` (prod) / `true` (nonprod) |
| `enable_interface_endpoints` | Crea Interface VPC Endpoints | `true` (prod) / `false` (nonprod) |
| `aws_region` | Región (para nombres de endpoint) | `eu-west-1` |
| `tags` | Tags comunes | `{ Project = "ringr-sip" }` |

## Outputs principales

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`public_subnets_by_az`, `private_subnets_by_az`.

## Pendiente / posibles mejoras

- Validado sintácticamente a mano; ejecutar `terraform init && terraform validate`
  en local antes de aplicar.
