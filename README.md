# Ringr — SIP Ingestion Platform on AWS

Production-grade SIP signalling infrastructure on AWS: Network Load Balancer → ECS Fargate (Kamailio 5.7.5) → RDS PostgreSQL, fully provisioned with parameterised Terraform across two environments (nonprod / prod).

→ Design decisions and trade-offs: [docs-backend.md](docs-backend.md)

---

## Testing

- `./scripts/local-test.sh` — signaling + real RTP audio, entirely local,
  no AWS spend. See [local-test/README.md](local-test/README.md).
- `./scripts/verify.sh` — signaling smoke test against the deployed AWS
  environment (requires `./scripts/up.sh` first).

---

## Architecture

```
External SIP clients (softphones, SIP trunks)
          │  SIP UDP/TCP 5060  ·  TLS 5061
          ▼
 ┌──────────────────────────────────────┐
 │   Network Load Balancer (NLB)        │  ← Public subnets, 2 AZs
 │   Elastic IPs per AZ (static)        │    Fixed IPs for carrier whitelists
 └───────────────┬──────────────────────┘
                 │
                 ▼
 ┌──────────────────────────────────────┐
 │   ECS Fargate — Kamailio 5.7.5       │  ← Private subnets, 2 AZs
 │   CPU-based Auto Scaling             │    No EC2 instances to manage
 └──────────┬───────────────┬───────────┘
            │               │
            ▼               ▼
 ┌──────────────┐  ┌─────────────────────┐
 │ RDS Postgres │  │  Internal services   │  ← Private subnets only
 │ (Multi-AZ)   │  │  (network prepared)  │    No public internet access
 └──────────────┘  └─────────────────────┘
```

Cross-cutting: NAT Gateway + VPC Endpoints (private egress to AWS APIs without internet), SSM / ECS Exec (shell access to containers during incidents, no SSH or bastion), Secrets Manager (DB credentials injected at runtime), CloudWatch (structured logs + alarms).

---

## SIP flow

The included probe script (`sip-server/sip_probe.py`, stdlib only) exercises the full authentication flow over TCP against any deployed endpoint:

```bash
python sip-server/sip_probe.py <nlb-ip> alice alicepass
```

```
============================================================
SIP probe => <nlb-ip>:5060  user=alice
============================================================

[1] OPTIONS — basic connectivity

--- SENT ---
OPTIONS sip:<nlb-ip> SIP/2.0
Via: SIP/2.0/TCP <nlb-ip>:5060;branch=z9hG4bKa1b2c3d4
From: <sip:probe@<nlb-ip>>;tag=e5f6a7b8
To: <sip:<nlb-ip>>
Call-ID: 9c8d7e6f5a4b3c2d1e0f
CSeq: 1 OPTIONS
Max-Forwards: 70
Content-Length: 0

--- RECEIVED ---
SIP/2.0 405 Method Not Allowed
...

=> OPTIONS result: SIP/2.0 405 Method Not Allowed

[2] REGISTER — expect 401 Unauthorized (auth challenge)

--- SENT ---
REGISTER sip:<nlb-ip> SIP/2.0
...
Expires: 3600

--- RECEIVED ---
SIP/2.0 401 Unauthorized
WWW-Authenticate: Digest realm="ringr.local", nonce="abc123..."

=> REGISTER (no auth) result: SIP/2.0 401 Unauthorized

[3] REGISTER — with digest credentials, expect 200 OK

--- SENT ---
REGISTER sip:<nlb-ip> SIP/2.0
...
Authorization: Digest username="alice", realm="ringr.local", nonce="abc123...", response="..."

--- RECEIVED ---
SIP/2.0 200 OK
...

=> REGISTER (with auth) result: SIP/2.0 200 OK

============================================================
SUMMARY
  OPTIONS            : SIP/2.0 405 Method Not Allowed
  REGISTER (no auth) : SIP/2.0 401 Unauthorized
  REGISTER (with auth): SIP/2.0 200 OK
============================================================
```

What this confirms end-to-end: TCP connectivity through the NLB → Kamailio receives and parses SIP → auth_db module challenges with a digest nonce → subscriber record found in RDS → credentials validated → registration accepted.

---

## Repository structure

```
.
├── sip-server/                  # Kamailio container
│   ├── Dockerfile
│   ├── kamailio.cfg.template    # envsubst-rendered at container start
│   ├── entrypoint.sh            # schema bootstrap + Kamailio launch
│   ├── db/
│   │   ├── schema.sql           # subscriber + location tables (idempotent)
│   │   └── seed.sql             # alice and bob test accounts
│   └── sip_probe.py             # standalone SIP test script (stdlib only)
│
├── modules/                     # Reusable Terraform modules
│   ├── network/                 # VPC, subnets, NAT GW, VPC Endpoints
│   ├── nlb/                     # Network Load Balancer + target groups
│   ├── security_groups/         # Chained SGs: NLB → SIP → RDS → internal
│   ├── ecs/                     # Fargate service + CPU auto scaling
│   ├── rds/                     # PostgreSQL Multi-AZ
│   ├── iam/                     # ECS task execution + ECS Exec roles
│   ├── ecr/                     # Container registry
│   └── monitoring/              # CloudWatch dashboards + alarms
│
└── environments/
    ├── nonprod/                 # eu-west-1, cost-optimised (single NAT GW, smaller instances)
    └── prod/                    # Production-sized parameters (Multi-AZ RDS, larger Fargate tasks)
```

---

## Design decisions

Full rationale and trade-off analysis: [docs-backend.md](docs-backend.md). Short version:

| Need | Choice | Why |
|---|---|---|
| Public SIP ingress | **NLB** | Only AWS LB with UDP support and static EIPs per AZ; ALB is HTTP-only |
| Compute | **ECS Fargate** | Long-running UDP/TCP process without server management; CPU auto-scaling |
| Database | **RDS PostgreSQL Multi-AZ** | Managed, HA, private subnet only — never reachable from the internet |
| Network isolation | **VPC public/private, 2 AZs** | NLB in public; compute and DB in private with no public IPs |
| Firewall | **Chained Security Groups** | SG-to-SG references auto-adapt as tasks scale; carrier IP restriction blocks mass port-5060 scanning |
| Incident access | **SSM / ECS Exec** | No SSH port, no bastion host — shell access via IAM, fully audited in CloudWatch |
| Credentials | **Secrets Manager** | DB password injected at container start; never in code or tfvars |
| Environment parity | **Two parameterised envs** | Same Terraform, different `.tfvars`; nonprod saves cost without changing architecture shape |

---

## Deploy to AWS

**Prerequisites:** AWS CLI, Terraform ≥ 1.6, Docker.

```bash
# 1. Push the Kamailio image to ECR
cd sip-server
docker build -t <ecr-repo-url>:v0.1.0 .
docker push <ecr-repo-url>:v0.1.0

# 2. First time: create S3 bucket + DynamoDB table for remote state.
#    See environments/nonprod/backend.tf for the backend configuration.
#    Uncomment the backend block after creating these resources.

# 3. Deploy nonprod
cd environments/nonprod
terraform init
terraform apply -var-file=nonprod.tfvars
```

After apply (~5 min), run `sip_probe.py <nlb-eip> alice alicepass` to confirm end-to-end.
