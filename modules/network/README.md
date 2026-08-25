# Module: network

Creates the base network layer for the SIP platform: VPC, public/private subnets across
multiple AZs, Internet Gateway, NAT Gateway(s), route tables, and VPC Endpoints.

> Built with `hashicorp/aws` provider resources directly (not the community module
> `terraform-aws-modules/vpc`) to make network decisions explicit. In production it
> could be replaced with the official module.

## What it creates

- **VPC** with DNS support and DNS hostnames enabled (both required for Interface endpoints).
- **Default Security Group** managed with no rules so it cannot be accidentally used.
- **Public subnets** (one per AZ): host the NLB and NAT Gateways.
- **Private subnets** (one per AZ): host ECS Fargate, RDS, and internal services.
- **Internet Gateway** + default route for public subnets.
- **NAT Gateway**: one per AZ (HA) or a single shared one (cost saving), controlled by flag.
- **Private route tables, one per AZ**, each routing outbound traffic through the NAT in its own zone.
- **VPC Endpoints**: S3 (Gateway, free) + ECR, CloudWatch Logs, SSM, and Secrets Manager
  (Interface), so Fargate can operate without going out to the internet.

## Key decisions

- **`for_each` indexed by AZ** (not by numeric index) so that reordering the AZ list
  does not destroy and recreate subnets in the state.
- **`single_nat_gateway`**: materialises the cost saving in non-production environments
  without changing the architecture (false in prod, true in nonprod).
- **Private route table per AZ**: prevents an AZ failure from cutting outbound access
  for the rest when there is one NAT per zone.
- **Default SG locked down**: Terraform manages the default SG with no rules to prevent
  accidental use of the permissive AWS default.
- **Input validation**: `vpc_cidr` is validated against RFC 1918 ranges; `check` blocks
  enforce that the number of subnet CIDRs matches the number of AZs at plan time.

## Main variables

| Variable | Description | Example |
|---|---|---|
| `name_prefix` | Naming and tagging prefix | `ringr-sip-prod` |
| `vpc_cidr` | VPC CIDR block (RFC 1918 only) | `10.0.0.0/16` |
| `availability_zones` | AZs (minimum 2) | `["eu-west-1a","eu-west-1b"]` |
| `public_subnet_cidrs` | Public CIDRs (order matches AZs) | `["10.0.0.0/24","10.0.1.0/24"]` |
| `private_subnet_cidrs` | Private CIDRs (order matches AZs) | `["10.0.10.0/24","10.0.11.0/24"]` |
| `single_nat_gateway` | Single shared NAT Gateway | `false` (prod) / `true` (nonprod) |
| `enable_interface_endpoints` | Create Interface VPC Endpoints | `true` (prod) / `false` (nonprod) |
| `aws_region` | Region (for endpoint service names) | `eu-west-1` |
| `tags` | Common tags | `{ Project = "ringr-sip" }` |

## Main outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`public_subnets_by_az`, `private_subnets_by_az`.
