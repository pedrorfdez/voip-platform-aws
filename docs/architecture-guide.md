# Architecture Guide — Ringr SIP Platform on AWS

This document is a study guide, not a submission. It explains every component of this Terraform infrastructure in depth, maps it to each requirement of the technical assessment, and gives you the reasoning behind every decision so you can explain it yourself in your own words. Read it once fully, then use it as a reference when writing the final README.

---

## 0. The mental model before anything else

Before looking at any individual component, plant this image in your head:

```
THE INTERNET
     │
     │  (only SIP traffic, on specific ports)
     ▼
 [NLB — the front door]         ← sits in public subnets, has a stable public IP
     │
     │  (SIP traffic, forwarded internally)
     ▼
 [Kamailio on ECS Fargate]      ← sits in private subnets, no public IP at all
     │             │
     ▼             ▼
 [PostgreSQL]   [Internal services]   ← both in private subnets, no public IP
```

The core design principle is **defence in depth through network layering**: the internet reaches only the front door (NLB). Everything behind it has no public IP. Even if Kamailio were compromised, the attacker still cannot reach the database directly — a separate firewall rule blocks it.

---

## 1. SIP traffic reception — the Network Load Balancer

### The requirement

> Allow reception of SIP traffic from external systems. Expose the service publicly and in a controlled way. Support appropriate network protocols for this type of traffic.

### What SIP is and why it is different from web traffic

SIP (Session Initiation Protocol) is the signalling protocol of VoIP telephony. A SIP message looks similar to HTTP in structure (it has headers, methods like INVITE and REGISTER), but it is fundamentally different in two ways that govern every infrastructure decision:

**1. It uses UDP as well as TCP.** HTTP is always TCP. SIP can be either UDP, TCP, or TLS (on port 5060 for UDP/TCP, port 5061 for TLS). UDP has no connection: a client sends a packet and you have to figure out where to send the reply. This matters because most cloud load balancers only understand TCP.

**2. Connections are long-lived.** An HTTP request lasts milliseconds. A SIP registration lasts minutes or hours. A call lasts as long as the conversation. Infrastructure that kills idle connections after 60 seconds (common in web-tier load balancers) would destroy calls mid-conversation.

### Why the Network Load Balancer (NLB), not an Application Load Balancer (ALB)

This is the single most important decision in the architecture. The question of which load balancer to use might sound like a configuration detail, but it is the choice that makes everything else possible or impossible.

AWS offers two main load balancers:

| | ALB (Application Load Balancer) | NLB (Network Load Balancer) |
|---|---|---|
| Layer | Layer 7 — understands HTTP/HTTPS | Layer 4 — understands TCP/UDP |
| UDP support | **No** | **Yes** |
| Protocols | HTTP, HTTPS, gRPC | TCP, UDP, TLS, TCP_UDP |
| Connection lifetime | Typically 60s–3600s | Unlimited |
| Public IP | Dynamic (changes) | **Static Elastic IP per AZ** |
| Use case | Web apps, APIs | Anything that is not HTTP |

**ALB is ruled out because it does not support UDP.** If you tried to configure an ALB for SIP, you could handle TCP port 5060 (partially), but you could never accept SIP over UDP. Many SIP trunks and carriers send UDP by default. If you cannot receive UDP, you cannot serve a significant portion of the SIP world.

**NLB is the right choice because:**
- It supports UDP natively.
- It handles long-lived connections — a call that lasts two hours stays open.
- It gives you a **static Elastic IP per Availability Zone**. This is critical for telephony: SIP carriers (the operators who route calls to you) typically maintain IP whitelists. They say "I will only send traffic to these specific IPs". With an ALB, your IP address can change; with an NLB, you have a fixed IP that never changes, so carriers can whitelist it once and forget it.

### The Elastic IP addresses

In nonprod, this Terraform creates two Elastic IPs: one in `eu-west-1a` and one in `eu-west-1b`. An Elastic IP is simply a static public IP address that AWS reserves for you and does not change even if you recreate the NLB. The two IPs we got are `108.132.141.244` and `52.213.212.142`.

### The "controlled" part — restricting who can call us

The assessment says "expose publicly and **in a controlled way**". The controlled part comes from the NLB's Security Group. The `operator_cidrs` variable in `nonprod.tfvars` is currently `0.0.0.0/0` (open for testing), but in production it would be replaced with the specific IP addresses of your SIP carriers (e.g. `185.10.12.0/24`). This means the NLB firewall drops any packet arriving from an IP that is not on the whitelist, before it even reaches Kamailio. This is your first line of defence against the most common SIP attack: automated port scanning on port 5060, which is constant and aggressive on the internet.

### Port 5060 scanning and toll fraud — the security context

This is worth understanding because it is why "controlled exposure" matters so much for SIP specifically. Port 5060 is publicly documented as the SIP port. Every script kiddie, bot, and malicious actor on the internet scans for it continuously. If they can reach your SIP server and register a fake account, they can make calls that bill to you — this is called toll fraud, and it can generate thousands of euros in charges in hours. The carrier IP whitelist at the NLB is not optional security nicety; it is mandatory for any SIP system exposed to the internet.

### TLS on port 5061

The NLB also listens on TCP 5061 for TLS-encrypted SIP. In this Terraform, when `certificate_arn` is populated, port 5061 carries encrypted SIP signalling. In nonprod it is currently open without a certificate (passthrough mode). In production, you would provision an ACM (AWS Certificate Manager) certificate and put its ARN in the tfvars. The NLB passes TLS through to Kamailio, which terminates it. This is the recommended approach for any carrier-grade deployment.

---

## 2. Network architecture — VPC, subnets, NAT, endpoints

### The requirement

> Define an adequate network architecture. Control access to the service from the outside. Limit the exposure of internal resources.

### What a VPC is

A VPC (Virtual Private Cloud) is your own isolated section of the AWS network. Think of it as a virtual office building: the whole building is yours, you control who gets in, what rooms exist, and who can talk to whom. The "walls" of this building are invisible to the internet — traffic only enters where you explicitly open a door.

This Terraform creates a VPC with CIDR `10.1.0.0/16`. That means all IP addresses inside this VPC look like `10.1.x.x`. These are private IPs — they are not routable on the internet, they only exist inside the VPC.

Prod uses `10.0.0.0/16` (so `10.0.x.x`). The different ranges matter if you ever want to connect the two environments (via VPC Peering or Transit Gateway) — overlapping CIDRs would make that impossible.

### Public subnets vs private subnets

A subnet is a subdivision of the VPC. The key distinction is:

- **Public subnet**: Has a route to an **Internet Gateway**. Resources placed here can get a public IP and be reached from the internet.
- **Private subnet**: Has no route to the Internet Gateway. Resources placed here are invisible to the internet.

This Terraform creates four subnets:
- Two **public** subnets (`10.1.0.0/24` and `10.1.1.0/24`), one per Availability Zone — **only the NLB lives here**
- Two **private** subnets (`10.1.10.0/24` and `10.1.11.0/24`), one per Availability Zone — **Kamailio (ECS), PostgreSQL (RDS), and internal services live here**

This is the structural answer to "limit the exposure of internal resources": they live in a private subnet with no public IP. It is physically impossible for the internet to reach them directly, regardless of what firewall rules you set — the route simply does not exist.

### Availability Zones — why we use two

An Availability Zone (AZ) is a physically separate datacenter within an AWS region. Each AZ has its own power supply, cooling, and network. If a fire breaks out in `eu-west-1a`, `eu-west-1b` is unaffected.

By spreading resources across two AZs (`eu-west-1a` and `eu-west-1b`), the system survives the failure of one datacenter. The NLB has a node in each AZ. Kamailio tasks can run in either AZ. RDS in production has a standby in the second AZ that automatically takes over if the primary fails.

For a SIP platform, this matters practically: if a carrier calls your NLB during an AZ failure and your Kamailio task only existed in the dead AZ, every call would fail. With multi-AZ deployment, traffic is routed to the healthy AZ automatically.

### NAT Gateway — how private resources reach the internet

Private resources (Kamailio container, RDS) cannot receive traffic from the internet. But they sometimes need to *initiate* outbound connections: the Kamailio container needs to pull updates, or reach AWS APIs (CloudWatch, Secrets Manager).

A **NAT Gateway** solves this. It sits in the public subnet and acts as a translator: when a private resource sends a packet to the internet, the NAT Gateway replaces the private source IP with its own public IP, sends the packet, receives the reply, and forwards it back. The internet sees the NAT Gateway's IP, not the private resource's IP. Inbound connections from the internet are impossible through a NAT Gateway — it only handles outbound.

In nonprod (`single_nat_gateway = true`), there is one shared NAT Gateway, saving ~$32/month compared to having one per AZ. The trade-off: if the AZ containing the NAT Gateway fails, private resources in the other AZ lose outbound internet access. In prod, you would set `single_nat_gateway = false` to have one NAT Gateway per AZ.

### VPC Endpoints — avoiding the internet for AWS service calls

When a Kamailio container calls the AWS API (e.g. to fetch a secret from Secrets Manager, or to push logs to CloudWatch), the request would normally go: container → NAT Gateway → internet → AWS API. This means:
1. You pay NAT Gateway data transfer costs
2. The traffic traverses the public internet

A **VPC Interface Endpoint** creates a private tunnel directly from your VPC to a specific AWS service, bypassing the internet entirely. Traffic stays within the AWS backbone. This is both cheaper and more secure.

In nonprod (`enable_interface_endpoints = false`), endpoints are disabled to save ~$87/month in endpoint hourly fees — traffic goes via NAT instead. In prod, you would enable them. This is a documented cost/security trade-off.

---

## 3. Compute layer — ECS Fargate

### The requirement

> Provide an execution layer where the SIP component can be deployed. Allow scaling based on load. Be able to handle long-duration connections. The team prefers to avoid direct server management if reasonable.

### The constraint: long-running process on a socket

Kamailio is a SIP proxy. It starts, opens sockets on UDP/5060, TCP/5060, and TCP/5061, and then sits there processing SIP messages for as long as it runs. It maintains state in memory (active registrations, call sessions). This is fundamentally different from a web server handling discrete HTTP requests.

This constraint rules out one candidate immediately.

### Why not Lambda?

AWS Lambda is the canonical "serverless" compute. You give it a function, and AWS runs it when triggered. It is excellent for short, stateless tasks.

But Lambda cannot host Kamailio for three concrete reasons:

1. **No socket listening.** Lambda does not open a port. It responds to events (HTTP via API Gateway, queue messages, etc.). There is no way to have Lambda sit and accept inbound UDP/5060 connections.
2. **15-minute maximum execution time.** A call can last longer than 15 minutes. Kamailio needs to stay alive as long as there are active sessions.
3. **Cold starts.** Lambda instances start from scratch on each invocation (or after idle time). A SIP proxy that destroys its in-memory state between calls cannot work.

Lambda is the right answer for dozens of use cases; SIP proxy is not one of them.

### Why not bare EC2?

EC2 is a virtual machine. You could run Kamailio on an EC2 instance — it would work perfectly from a technical standpoint. The reason it was discarded is operational: the team wants to "avoid direct server management if reasonable."

Running on EC2 means:
- Patching the OS (security updates, kernel updates)
- Managing the Kamailio process supervisor (systemd, etc.)
- Scaling by launching and configuring new EC2 instances manually or with complex Auto Scaling Groups
- Handling instance health (what if the EC2 fails mid-call?)

These are not impossible problems, but they are significant operational overhead that does not add business value.

### Why ECS Fargate?

ECS (Elastic Container Service) is AWS's container orchestrator. You give it a Docker image, tell it how much CPU and memory you need, and it runs containers. **Fargate** is the execution mode where AWS manages the underlying servers — you never see or touch EC2 instances.

**Fargate gives you:**
- **No server management.** AWS patches, replaces, and scales the servers. You only think about your container.
- **Long-running containers.** Unlike Lambda, a Fargate task runs indefinitely until you stop it. Kamailio can stay alive for days or weeks.
- **TCP and UDP socket support.** A Fargate task is a container that can bind to any port — UDP/5060, TCP/5060, TCP/5061. No restrictions.
- **CPU-based Auto Scaling.** When CPU utilization across all Kamailio tasks crosses 80%, ECS automatically launches additional tasks (up to the configured maximum of 3 in nonprod). When load drops, it scales down.

The concise justification for the interview: *"Fargate is 'serverless in the way that matters': you get the execution model SIP requires (long-running process on a socket) without the operational overhead of managing servers."*

### The stateful scaling trade-off

This is the most important risk to understand and be able to articulate, because it is non-obvious.

Kamailio holds state in memory: active SIP registrations and call sessions. If you have 10 active calls and ECS decides to terminate a task (scale-in), those 10 calls are abruptly disconnected. The users hear silence, the call drops.

There are three standard mitigations:

1. **Externalise state to the database.** Kamailio writes registration data to PostgreSQL (`usrloc` module with `db_mode=2` in this config). This means if a task is killed, a new task can spin up and look up existing registrations. Call session state is harder to externalise.
2. **Connection draining.** Tell ECS to wait N seconds before terminating a task, giving in-flight calls time to complete naturally.
3. **Accept the limitation.** For a telephony platform at scale, pure stateless scaling is a hard problem. Many production systems use sticky routing (the same client always hits the same Kamailio instance) or implement a shared state store (Redis).

In this implementation, the `usrloc` module uses `db_mode=2` (write-through to PostgreSQL), which means registration state survives a task restart. Call session state is still in-memory. This is declared as a known limitation in `docs-backend.md`.

### How the ECS task is configured

Looking at `nonprod.tfvars`:
- `ecs_task_cpu = 256` — 0.25 vCPU (the minimum Fargate allows). Sufficient for a demo.
- `ecs_task_memory = 512` — 512 MB. Minimum for this CPU setting.
- `ecs_desired_count = 1` — starts one task.
- `ecs_min_capacity = 1`, `ecs_max_capacity = 3` — auto scaling range.
- `ecs_cpu_scale_target = 80` — scale out when average CPU hits 80%.

In prod, these numbers would be larger (more CPU, more memory, higher desired count, more aggressive scaling).

---

## 4. Security — Security Groups

### The requirement

> Define an adequate network architecture. Control access to the service from the outside. Limit the exposure of internal resources.

### What a Security Group is

A Security Group (SG) is a stateful firewall attached to an AWS resource. "Stateful" means: if you allow traffic IN on a port, the reply is automatically allowed OUT, without needing an explicit outbound rule. You only need to define what is allowed to enter and what is allowed to exit; AWS handles the bidirectional flow.

Every resource in this architecture has its own Security Group with rules that strictly define what it can receive.

### The four Security Groups and their rules

**1. NLB Security Group (`nlb`)**

- **Inbound:** SIP UDP/5060, TCP/5060, TCP/5061 from `operator_cidrs` only. In production, that is your carriers' IP ranges.
- **Outbound:** All traffic to the SIP Security Group. The NLB forwards everything it receives to the containers.

**2. SIP (Kamailio) Security Group (`sip`)**

- **Inbound from NLB SG:** TCP 5060 and TCP 5061 (for NLB health checks and proxied SIP traffic)
- **Inbound from operator_cidrs:** UDP/TCP 5060, TCP 5061 (because the NLB preserves the client IP for TCP connections — more on this below)
- **Outbound:** All. The container needs to reach PostgreSQL, internal services, AWS APIs (CloudWatch, Secrets Manager), and the internet (via NAT).

**3. RDS Security Group (`rds`)**

- **Inbound:** TCP 5432 from the SIP SG only. And TCP 5432 from the Internal Services SG.
- **Outbound:** None defined (RDS never initiates connections).

**4. Internal Services Security Group (`internal`)**

- **Inbound:** Currently all traffic from the SIP SG (placeholder — would be restricted to specific ports once services are defined).
- **Outbound:** All.

### Why chain Security Groups by reference, not by IP

This is the key insight about Security Group design. Look at the RDS rule: it does not say "allow TCP 5432 from `10.1.10.x` and `10.1.11.x`". It says "allow TCP 5432 from the Security Group named `sip`".

Why does this matter? When ECS Fargate scales out from 1 task to 3 tasks, those new tasks get new IP addresses in the private subnets. If the RDS rule were IP-based, the new tasks could not reach the database until you manually updated the rule. But because the rule references the SG, any resource attached to the SIP Security Group — regardless of its IP — is automatically allowed. This is the "auto-adapts to scaling" property.

This also makes the rules readable. Instead of a list of IP ranges, you have named objects: "RDS accepts PostgreSQL from the SIP component". The intent is clear; the implementation is automatic.

### The client IP preservation subtlety

There is one technical detail about the NLB that is important to understand. When the NLB receives a SIP packet and forwards it to a Kamailio task, it can optionally preserve the original client IP address (so Kamailio sees the carrier's IP, not the NLB's IP). This is called `preserve_client_ip`.

For TCP connections, the NLB enables `preserve_client_ip` by default (and cannot disable it for certain target group types). This means the Kamailio container sees the carrier's real IP as the source of the TCP connection. For this to work, the Kamailio SG must also allow the carrier's IPs directly — not just the NLB SG. This is why there is a separate `sip_from_operator` ingress rule on the SIP SG in addition to the `sip_tcp_from_nlb` rule.

---

## 5. Database — RDS PostgreSQL

### The requirement

> Provide a database to store basic operational information. Allow the SIP component and internal services to connect to it.

### What Kamailio stores in the database

Looking at `schema.sql`, there are two tables:

- **`subscriber`**: one row per SIP account (username, domain, hashed password). Used by Kamailio's `auth_db` module to verify SIP digest authentication. When alice tries to REGISTER, Kamailio looks her up here.
- **`location`**: one row per active SIP registration. When alice registers, her current IP and port are stored here. When someone calls alice, Kamailio looks up her current contact here and forwards the INVITE.
- **`version`**: metadata table required by Kamailio's module system to verify schema compatibility.

Both tables are managed by the `entrypoint.sh` script: every time a Kamailio container starts, it runs `schema.sql` (idempotent: `CREATE TABLE IF NOT EXISTS`) and `seed.sql` (upserts alice and bob). This means the database is always ready even if it was wiped and recreated.

### Why RDS, not self-managed PostgreSQL on EC2

Same principle as Fargate vs EC2 for compute: managed services eliminate operational overhead. With RDS:
- AWS patches the PostgreSQL engine for security vulnerabilities.
- Automated backups run daily with point-in-time recovery.
- Failover to a standby is automatic (in Multi-AZ mode).
- Storage can autoscale.
- Monitoring (CPU, connections, free storage) is built in.

Running PostgreSQL on an EC2 instance would work technically, but you would own all of the above.

### Why Multi-AZ matters in production (and why it is disabled in nonprod)

With `rds_multi_az = true` (production), RDS maintains a synchronous standby in the second AZ. If the primary database instance fails (hardware failure, AZ outage), RDS automatically promotes the standby. Clients reconnect to the same DNS endpoint and get the new primary. Downtime is typically 60–120 seconds.

In nonprod (`rds_multi_az = false`), there is a single instance. If its AZ has an outage, the database is unavailable until the AZ recovers. This is acceptable for a test environment. The cost difference: a `db.t3.micro` Multi-AZ costs twice as much as single-AZ.

### Two origins: SIP component and internal services

The RDS SG has two inbound rules:
1. TCP 5432 from the SIP SG (Kamailio reads/writes registrations and subscriber data)
2. TCP 5432 from the Internal SG (future internal services that need subscriber or call data)

Neither of these is a CIDR range — both reference Security Groups. This means any future service that is assigned the Internal SG gets database access automatically.

### The database is never on the internet

`rds_deletion_protection = false` in nonprod (allowing `terraform destroy` without extra steps). But crucially, the RDS instance has `publicly_accessible = false` (enforced in the RDS module). This means it has no public DNS entry and cannot be reached from outside the VPC, period. There is no route from the internet to the private subnet where it lives.

---

## 6. Incident access — SSM and ECS Exec

### The requirement

> The team wants to be able to access resources (compute and database) in case of incident.

### The problem

In a traditional infrastructure setup, you would SSH into a server to investigate a problem: view logs, check a running process, query the database. But in this architecture:
- Kamailio runs in a container in a private subnet with no public IP.
- The database is in a private subnet with no public IP.
- There is no port 22 open anywhere.

How do you get in when something goes wrong?

### The classic (bad) answer: bastion host

A **bastion host** is an EC2 instance in a public subnet with port 22 open. You SSH into the bastion, then SSH from there into private resources. This is the traditional solution.

Why it is bad for this use case:
1. **Attack surface.** Port 22 open to the internet is a constant target for brute force attacks, even with key-based auth.
2. **Management overhead.** The bastion is a server you must patch, monitor, and maintain.
3. **Contradiction.** The whole architecture is designed to eliminate public-facing ports and self-managed servers. A bastion reintroduces both.

### The modern answer: SSM Session Manager

**AWS Systems Manager Session Manager** lets you open a terminal to any EC2 instance or container through the AWS API, without any open ports. It works like this:

1. The container has an IAM role that allows it to call the SSM API.
2. The SSM agent inside the container maintains an outbound HTTPS connection to the AWS SSM service (over VPC endpoints or NAT).
3. When you run `aws ssm start-session --target <instance-id>`, your request goes to the SSM API, which forwards it to the agent through that existing HTTPS connection.
4. You get an interactive terminal.

No port 22. No key management. Access is controlled by IAM (you can restrict who can open sessions, to which resources, and log everything to CloudWatch). Every session is automatically logged.

### ECS Exec — SSM for containers

**ECS Exec** is the same mechanism applied specifically to ECS containers. You run:

```bash
aws ecs execute-command \
  --cluster ringr-sip-nonprod-cluster \
  --task <task-id> \
  --container kamailio \
  --command "/bin/sh" \
  --interactive
```

You get a shell inside the running Kamailio container. From there you can:
- View live logs with `tail -f`
- Run `sngrep` to inspect live SIP traffic (call-ID level filtering)
- Check what is registered: `kamctl ul dump`
- Query the database: `psql postgresql://sipadmin:...@<rds-host>:5432/kamailio`

The IAM role that enables this is in `modules/iam/`. The task role has `ssmmessages:CreateControlChannel`, `ssmmessages:OpenDataChannel`, and related permissions — these are the SSM API calls the agent uses to maintain its tunnel.

### Getting to the database specifically

Since the RDS instance has no shell (it is managed by AWS, you cannot SSH into it), you access it via the Kamailio container:

```bash
# 1. ECS Exec into the container
aws ecs execute-command --cluster ... --task ... --command "/bin/sh" --interactive

# 2. From inside the container, connect to PostgreSQL
psql "postgresql://sipadmin:${DB_PASSWORD}@${DB_HOST}:5432/kamailio"
```

The container is in the same VPC and its SG is allowed TCP 5432 to the RDS SG. This is the network path for incident access to the database.

Alternatively, for read-heavy investigation, SSM port forwarding can tunnel the RDS port to your local machine:

```bash
aws ssm start-session \
  --target <ec2-or-container> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["5432"],"localPortNumber":["5432"],"host":["<rds-endpoint>"]}'
```

Then your local `psql` connects to `localhost:5432` and it tunnels through SSM to the RDS instance.

---

## 7. Secrets — Secrets Manager

### The requirement

> (implied by security best practices)

### The problem with environment variables for secrets

The naive approach to giving Kamailio the database password is to put it in an environment variable in the ECS task definition. That task definition is stored as JSON in AWS, visible in the ECS console, and potentially logged. If someone gets read access to your AWS account, they get the password.

**AWS Secrets Manager** stores the password encrypted (using KMS) and gives resources access to it via IAM. In this Terraform:

1. The RDS module generates a random 32-character password and stores it in Secrets Manager automatically.
2. The ECS task definition references the secret ARN: `{ name = "DB_PASSWORD", valueFrom = "<secret-arn>:password::" }`.
3. At task startup, ECS fetches the secret from Secrets Manager and injects it as the `DB_PASSWORD` environment variable inside the container.
4. The plaintext password is in memory inside the container only. It is never stored in the task definition JSON, never in Terraform state in a readable form, never logged.

The IAM task execution role has `secretsmanager:GetSecretValue` on that specific ARN. Other resources cannot read this secret.

---

## 8. Internal services integration

### The requirement

> Allow the SIP component to communicate with internal services. Not necessary to implement these services, but contemplate their integration at network level.

### What "network prepared" means

The internal services that will eventually process SIP signalling (call routing logic, CDR generation, billing, etc.) are out of scope for this implementation. But the network foundation for them is already in place:

1. **An `internal` Security Group exists.** Any future internal service that is given this SG automatically gets:
   - Inbound traffic from the SIP component (Kamailio can call it).
   - Access to the PostgreSQL database (can read subscriber/call data).

2. **Private subnets are sized for additional resources.** The private subnets (`10.1.10.0/24` = 256 addresses each) have room for additional ECS services, ElastiCache clusters, or other compute.

3. **The SIP SG has unrestricted egress (`0.0.0.0/0`).** Kamailio can initiate connections to any internal service in the VPC. When an internal service is built, you add a specific inbound rule on its SG for the port it listens on.

### How you would extend this

Say a future service runs on port 8080 and needs to receive call events from Kamailio:

1. Create its ECS service with the `internal` SG.
2. Add an ingress rule to the `internal` SG: TCP 8080 from the SIP SG.
3. Configure Kamailio to call `http://internal-service:8080/event`.
4. Service discovery: use AWS Cloud Map or internal ALB to give the service a stable DNS name inside the VPC.

This is a pattern, not an implementation detail — but it matters because you should be able to describe it.

### Evolution to multi-VPC

If the internal services were in a separate AWS account (common in large organisations for isolation), you would connect the two VPCs with:
- **VPC Peering**: a direct connection between two VPCs in the same or different accounts. Simple, low-latency, but does not scale past a handful of VPCs.
- **Transit Gateway**: a central hub that all VPCs connect to. Scales to hundreds of VPCs across accounts. More complex and costly.

The non-overlapping VPC CIDRs (`10.1.x.x` for nonprod, `10.0.x.x` for prod) are specifically sized to allow future peering without address conflicts.

---

## 9. Environments — nonprod and prod

### The requirement

> Define what environments you would propose and how. Operations asks for independent deployment. Business asks to save costs in non-productive environments.

### The two environments

This Terraform has two environments:
- `environments/nonprod/` — deployed in `eu-west-1`, used for development and testing
- `environments/prod/` — the production environment

### How independence is achieved

Each environment has its own Terraform state file stored in S3 with a separate key:
- nonprod: `ringr-sip/nonprod/terraform.tfstate`
- prod: `ringr-sip/prod/terraform.tfstate`

Running `terraform apply` in `environments/nonprod/` cannot affect the prod state, even if they are in the same AWS account. The state files are completely separate. The `DynamoDB` table provides locking so that two people cannot apply to the same environment simultaneously.

In the architecture as designed, the recommendation is separate AWS accounts (stronger isolation), but separate state files in the same account already satisfies the "deploy independently" requirement.

### Same code, different parameters

Every value that differs between environments is a Terraform variable. The actual infrastructure code (all the modules in `modules/`) is identical. The difference is entirely in the `.tfvars` files:

| Parameter | nonprod | prod (expected) |
|---|---|---|
| RDS instance | `db.t3.micro` | `db.t3.medium` or larger |
| RDS Multi-AZ | `false` | `true` |
| ECS CPU/Memory | 256/512 (minimum) | 1024/2048 or more |
| ECS desired count | 1 | 2+ |
| Single NAT GW | `true` (saves $32/mo) | `false` (HA) |
| VPC Endpoints | `false` (saves $87/mo) | `true` (security + cost) |
| Backup retention | 1 day | 7+ days |
| Deletion protection | `false` | `true` |
| Alarm actions | none | SNS → PagerDuty/email |

This pattern guarantees parity: nonprod is genuinely representative of prod (same code paths, same Terraform modules, same security group logic) while being cheaper. A bug that exists in the nonprod Terraform will be caught before it reaches prod.

### Specific cost savings in nonprod

In nonprod, the following cost decisions are made explicitly (with comments in `nonprod.tfvars`):

- **Single NAT Gateway**: saves ~$32/month at the cost of one AZ losing outbound internet if that AZ fails.
- **No VPC Interface Endpoints**: saves ~$87/month; traffic goes via NAT instead of private endpoints.
- **No Multi-AZ RDS**: saves ~50% on RDS cost. Database is unavailable during an AZ failure.
- **db.t3.micro**: smallest RDS instance (~$14/month vs $50+ for production sizes).
- **256 CPU / 512 MB Fargate**: minimum task size (~$7/month per task vs much more for production).
- **Log retention 7 days**: vs 30+ days in prod. CloudWatch log storage costs accumulate.
- **No alarm notifications**: alarms still exist in CloudWatch, but do not send to SNS/PagerDuty.

---

## 10. Observability and monitoring

### CloudWatch Logs

Every Kamailio container sends its output to a CloudWatch Log Group (`/ecs/ringr-nonprod-sip`). The entrypoint starts Kamailio with `-E` (log to stderr) and `-e` (strip colour codes), which ECS's awslogs log driver picks up and sends to CloudWatch automatically.

The Kamailio config uses structured logging via `xlog`:
```
xlog("L_INFO", "REGISTERED user=$fU contact=$ct src=$si:$sp\n");
xlog("L_INFO", "INVITE caller=$fU callee=$rU callid=$ci src=$si:$sp\n");
```

Each log line has key=value pairs, making them filterable in CloudWatch Insights: `fields @message | filter @message like "REGISTERED"`.

### CloudWatch Alarms

The `modules/monitoring/` module creates alarms for:
- **NLB health**: unhealthy host count > 0 (Kamailio is down)
- **ECS CPU**: avg CPU > threshold (scale pressure)
- **RDS CPU**: high database load
- **RDS free storage**: disk almost full

In nonprod, `alarm_actions = []` — alarms are visible in the console but do not page anyone. In prod, you would point this at an SNS topic that sends to PagerDuty, email, or Slack.

---

## 11. The Terraform code structure

### Why modules?

Instead of writing all the Terraform in one giant file, the code is split into focused modules. Each module manages one logical component and exposes inputs (variables) and outputs. Modules can be reused across environments without copy-pasting.

The module tree:
```
modules/
├── network/         VPC, subnets, IGW, NAT GW, route tables, VPC endpoints
├── nlb/             NLB, listeners (5060 UDP, 5060 TCP, 5061 TCP), target groups
├── security_groups/ All SGs and their rules. Single source of truth for network rules.
├── ecs/             Cluster, task definition, services, auto scaling, log group
├── rds/             PostgreSQL instance, subnet group, parameter group, secret
├── iam/             Task execution role, task role (ECS Exec + Secrets Manager access)
├── ecr/             Container registry for the Kamailio image
└── monitoring/      CloudWatch alarms for NLB, ECS, RDS
```

### How an environment wires modules together

`environments/nonprod/main.tf` is where modules are assembled. It:
1. Instantiates each module, passing the outputs of one as inputs to the next.
2. Example: `module.network.vpc_id` (output of the network module) is passed to `module.security_groups` as `var.vpc_id`.
3. The `RTPENGINE_HOST` env var will be added here when rtpengine is implemented (the `container_environment` list already shows the pattern with `DB_HOST`).

### The remote backend

`environments/nonprod/backend.tf` configures Terraform to store state in S3 with DynamoDB locking. The backend block is currently commented out (so the code can run locally without AWS infrastructure), but the file documents exactly how to enable it. The S3 bucket and DynamoDB table must be created before the first `terraform init` (they cannot bootstrap themselves from Terraform — classic chicken-and-egg problem).

---

## 12. Key trade-offs to be able to articulate

These are the most likely interview follow-up questions. Know the trade-off, not just the decision.

**"Why not ALB?"** → ALB only supports HTTP. SIP uses UDP. The NLB is the only AWS load balancer that supports UDP. Full stop.

**"Why Fargate instead of Lambda?"** → Lambda cannot open a persistent socket, has a 15-minute maximum runtime, and destroys state between invocations. SIP requires a long-running process with persistent socket and session state. Fargate is the right model.

**"What happens to active calls when ECS scales in?"** → They drop, because Kamailio holds call session state in memory. Registration state is externalised to PostgreSQL (`db_mode=2`), so registrations survive. Call state would need a shared state store (Redis) or sticky routing to survive scale-in. This is a declared limitation.

**"Why is the database inaccessible from the internet?"** → It lives in a private subnet with no public IP. There is no Internet Gateway route for it. Even with no security group rules, no packet can reach it from outside the VPC. The security group is an additional layer, not the only layer.

**"What is the cost of having two environments in separate AWS accounts?"** → More operational overhead (two sets of credentials, two CloudTrail trails, two billing accounts). The benefit is total isolation: a `terraform destroy` in nonprod cannot affect prod. For a startup, a single account with separate state files is a reasonable simplification; for an enterprise, separate accounts are standard.

**"How would you handle carrier failover?"** → The NLB has EIPs in two AZs. Carriers would configure both IPs as their destination (primary and secondary SRV records in DNS). If one AZ fails, the NLB routes to the healthy AZ automatically. The carrier's SIP stack retries on the secondary IP.

---

## 13. What is out of scope and why

The assessment explicitly excludes several items. Know why each was excluded:

- **SIP routing/parsing logic**: this is Kamailio's job, not infrastructure. Infrastructure provides the execution platform; the application inside the container handles the protocol.
- **RTP/audio processing**: RTP uses a large range of UDP ports (10000–20000 typically) which creates challenges for load balancers (you cannot have 10,000 NLB listeners). This is a separate component (rtpengine) that would require its own EC2 instance with an Elastic IP. It is architecturally a different problem from SIP signalling.
- **Full Kamailio implementation**: the assessment asks for infrastructure design. Kamailio in this repo is used as a "black box" to prove the infrastructure works — to demonstrate that the NLB receives SIP, forwards it to a container, the container authenticates against the database, and registers a user. The SIP logic inside Kamailio is minimal and illustrative.
- **CI/CD pipelines**: deployment automation is out of scope. The current workflow is manual (`docker build`, `docker push`, `terraform apply`). A production system would add a pipeline (GitHub Actions, etc.), but that is separate work.
- **Backend services**: the services that consume SIP signalling (billing, call routing, CDR) are not implemented. Their network integration point is prepared (the `internal` SG and its database access rules).
