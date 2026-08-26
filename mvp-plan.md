# MVP Plan: Phone-to-Phone SIP Call

**Goal:** Two softphone apps (Linphone or Zoiper) register to the server and can call each other over the deployed AWS infrastructure.

**Terraform strategy:** No `terraform apply` until Phase 4. State stays local throughout development. The single apply at the end deploys everything at once (ECR repo, ECS tasks, all supporting infrastructure).

---

## Phase 1 — Close Infrastructure Gaps

- [x] Add ECR module to Terraform (`modules/ecr/`)
- [x] Wire the ECR module into `environments/nonprod/main.tf`
- [x] Add your home/mobile public IP to `operator_cidrs` in `nonprod.tfvars`
- [ ] `terraform plan` — verify the plan looks correct (do not apply yet)

---

## Phase 2 — SIP Server (Kamailio)

- [x] Create `sip-server/` directory at the repo root
- [x] Write `sip-server/Dockerfile`
  - [x] Base image: `kamailio/kamailio:5.7-bullseye` (official)
  - [x] Copy `kamailio.cfg.template` into the image
  - [x] Expose ports 5060/udp, 5060/tcp, 5061/tcp
- [x] Write `sip-server/kamailio.cfg.template`
  - [x] Set listen address to `0.0.0.0` (Fargate network namespace)
  - [x] Enable modules: `db_postgres`, `auth`, `auth_db`, `usrloc`, `registrar`, `tm`, `sl`, `rr`, `maxfwd`
  - [x] Read Postgres connection string from environment variables (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_PASSWORD`)
  - [x] Configure `auth_db` to authenticate against the `subscriber` table
  - [x] Configure `usrloc` to store registrations in the `location` table
  - [x] Configure routing: REGISTER → registrar, INVITE → lookup location → proxy
  - [x] Verify Kamailio listens on TCP 5060 (required for the NLB health check to pass)
- [x] Build the image locally and confirm it starts without errors

---

## Phase 3 — Database Bootstrap

- [x] Write `sip-server/db/schema.sql` — the Kamailio DDL (subscriber, location tables)
- [x] Write `sip-server/db/seed.sql` — insert two test accounts (alice, bob)
  - [x] Passwords stored as `ha1` hash: `MD5(username:domain:password)`
- [ ] Plan how to run the SQL against RDS (SSM session into VPC + psql, or a one-off ECS task)

> These scripts are written now but run after the first `terraform apply` in Phase 4.

---

## Phase 4 — First and Only `terraform apply`

- [ ] Update `container_image` in `nonprod.tfvars` with the ECR URI that will be created
  - Format: `<account-id>.dkr.ecr.<region>.amazonaws.com/ringr-sip-nonprod:v0.1.0`
- [ ] `terraform apply` — creates all AWS resources including the ECR repo
- [ ] Authenticate Docker to ECR: `aws ecr get-login-password | docker login ...`
- [ ] Build and push the image
  - `docker build -t ringr-sip:v0.1.0 sip-server/`
  - `docker tag ringr-sip:v0.1.0 <ecr-url>:v0.1.0`
  - `docker push <ecr-url>:v0.1.0`
- [ ] Force a new ECS deployment so tasks pull the image (or wait for the service to stabilise)
- [ ] Run the DB bootstrap SQL against RDS (Phase 3 scripts)
- [ ] Confirm ECS tasks reach RUNNING state in the console
- [ ] Confirm NLB target groups show targets as healthy
- [ ] Confirm Kamailio logs appear in CloudWatch (`/ecs/ringr-sip-nonprod`)

---

## Phase 5 — Softphone Test

- [ ] Install **Linphone** (or Zoiper) on two devices
- [ ] Get the NLB Elastic IP: `terraform output elastic_ip_addresses`
- [ ] Configure device A (alice)
  - [ ] SIP server: `<nlb-elastic-ip>`
  - [ ] Username: `alice`, Password: as set in Phase 3
  - [ ] Transport: TCP (more reliable through NAT than UDP for initial test)
- [ ] Configure device B (bob) — same server, username: `bob`
- [ ] Register device A → verify CloudWatch shows REGISTER 200 OK
- [ ] Register device B → same
- [ ] Call from A to B → verify INVITE → 200 OK → audio flows
- [ ] Hang up → verify BYE → 200 OK
- [ ] Repeat test over UDP 5060
- [ ] (Optional) Test TLS 5061 once an ACM certificate is attached

---

## Out of Scope for MVP

- PSTN / real phone numbers (requires a SIP trunk provider: Twilio, Telnyx, etc.)
- TLS certificates (ACM cert → attach to NLB listener 5061)
- S3 remote state backend (do this before adding a second team member or going to prod)
- CI/CD pipeline
- SNS alarm notifications (alarms exist but `alarm_actions = []`)
- Secrets Manager rotation Lambda
- NLB access logs
- VPC flow logs
- RDS enhanced monitoring
- Load testing

---

## Estimated Effort

| Phase | Estimate |
|---|---|
| 1 — Infrastructure gaps | ½ day |
| 2 — Kamailio config + Dockerfile | 1–2 days |
| 3 — DB schema + seed data | ½ day |
| 4 — Apply + build + push + bootstrap | ½ day |
| 5 — Softphone test | 1 hour |
| **Total** | **~3–4 days** |

The biggest variable is Phase 2: getting the Kamailio config right against a Postgres backend for the first time requires iteration.
