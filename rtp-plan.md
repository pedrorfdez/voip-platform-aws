# RTP Media Plane — Full VoIP Stack Plan

**Goal:** Real audio on calls. Alice and Bob, registered via softphone, can hear each other
through the AWS infrastructure — not just exchange SIP signaling.

**What exists today:** Kamailio handles SIP signaling end-to-end (REGISTER, INVITE, 200 OK,
BYE). The SDP body in those messages carries RTP connection details (IP + port), but Kamailio
currently passes them unchanged. If both softphones are behind NAT (home broadband, mobile),
the IPs in the SDP are private and unreachable — audio never flows.

---

## Why a new component is needed

```
TODAY (signaling only):

Alice ──SIP──► NLB ──► Kamailio ──► NLB ──► Bob
                                                    ✗ RTP blocked by NAT
Alice ◄╌╌╌╌╌╌╌╌╌╌╌ no audio path ╌╌╌╌╌╌╌╌╌╌╌╌► Bob


AFTER THIS PLAN:

Alice ──SIP──► NLB ──► Kamailio (rewrites SDP) ──► NLB ──► Bob
                              │ ng protocol (UDP 2223)
                              ▼
                         rtpengine (EC2 + EIP)
                              │
Alice ◄──RTP UDP──────────────┤──────────────── RTP UDP──► Bob
       (EIP:10000)            │            (EIP:10002)
                         relays audio both ways
```

Kamailio intercepts each INVITE and 200 OK, asks rtpengine to allocate a port pair, and
rewrites the SDP connection address to the rtpengine EIP. Each softphone sends audio to
rtpengine, which forwards it to the other side. Neither client ever needs to reach the other
directly.

---

## Why EC2 for rtpengine, not Fargate

rtpengine needs to receive RTP on a large port range (UDP 10000–20000, one port pair per
active call). An NLB listener covers exactly one port — adding 10,000 listeners at
$0.008/listener/hour costs ~$1,700/month and AWS caps NLBs at 50 listeners. EC2 with an
Elastic IP sidesteps this: the EIP is reachable directly, no load balancer needed for the
media plane. A t3.micro (~$8/month) is more than enough for a demo with tens of concurrent
calls. This is a deliberate, justified exception to the "no EC2" principle for the
signaling plane.

---

## What stays the same

- NLB, ECS Fargate, Kamailio, RDS — untouched
- The `subscriber` and `location` tables — untouched
- Existing security groups — extended, not replaced
- Both environments (nonprod / prod) stay in sync via the same parameterised module

---

## Phase 1 — New Terraform module: `modules/rtpengine`

- [ ] Create `modules/rtpengine/main.tf`
  - [ ] `aws_iam_role` + `aws_iam_instance_profile` — SSM access only, no SSH
  - [ ] `aws_security_group` `rtpengine`:
    - Inbound UDP 10000–20000 from `operator_cidrs` (RTP from clients)
    - Inbound UDP 2223 from the SIP security group (ng control from Kamailio)
    - Outbound: all
  - [ ] `aws_instance` (t3.micro, Amazon Linux 2023 or Debian 12)
    - `user_data`: installs rtpengine, writes `/etc/rtpengine/rtpengine.conf`, enables systemd service
    - `iam_instance_profile`: SSM profile above
    - Placed in a **private** subnet (the EIP provides the public address; the instance itself
      does not need a public IP)
  - [ ] `aws_eip` — stable public IP for the RTP plane
  - [ ] `aws_eip_association` — attach EIP to the EC2 instance
- [ ] `modules/rtpengine/variables.tf`
  - `name_prefix`, `vpc_id`, `private_subnet_id`, `operator_cidrs`, `sip_sg_id`,
    `rtp_port_min` (default 10000), `rtp_port_max` (default 20000), `instance_type`
    (default t3.micro), `tags`
- [ ] `modules/rtpengine/outputs.tf`
  - `private_ip` — used by Kamailio to reach the ng socket
  - `public_ip` — the EIP; informational output

---

## Phase 2 — Security group changes in `modules/security_groups`

- [ ] Add a new output `rtpengine_sg_id` — passed into the rtpengine module
- [ ] Add a rule: SIP SG → rtpengine SG, UDP 2223 (ng control channel)
  - This allows Kamailio Fargate tasks to reach rtpengine even as tasks scale

---

## Phase 3 — rtpengine installation and config (user_data)

The `user_data` script on the EC2 instance must:

- [ ] Install rtpengine from the OS package manager or compile from source
- [ ] Write `/etc/rtpengine/rtpengine.conf`:
  ```
  [rtpengine]
  interface = PRIVATE_IP!EIP          # listen on private, advertise EIP in SDP
  listen-ng = PRIVATE_IP:2223         # control socket, reachable from Kamailio VPC IP
  port-min = 10000
  port-max = 20000
  log-level = 6
  log-facility = local0
  foreground = false
  pidfile = /run/rtpengine/rtpengine.pid
  ```
  The `PRIVATE_IP!EIP` syntax tells rtpengine: "bind locally on PRIVATE_IP but tell
  clients to send RTP to EIP". This is the line that fixes NAT traversal.
- [ ] Enable and start the `rtpengine` systemd service
- [ ] Enable CloudWatch agent (optional but recommended — sends rtpengine logs to
  `/rtpengine/nonprod`)

The PRIVATE_IP and EIP values are injected at instance launch via Terraform
`templatefile()` in user_data.

---

## Phase 4 — Pass rtpengine address into Kamailio

- [ ] Add `rtpengine_private_ip` output from `modules/rtpengine`
- [ ] In `environments/nonprod/main.tf`, add to `container_environment`:
  ```hcl
  { name = "RTPENGINE_HOST", value = module.rtpengine.private_ip }
  ```
- [ ] Same change in `environments/prod/main.tf` when prod is ready

---

## Phase 5 — Kamailio config changes (`sip-server/kamailio.cfg.template`)

Three areas to change:

**5a — Load the rtpengine module**
```
loadmodule "rtpengine.so"
modparam("rtpengine", "rtpengine_sock", "udp:${RTPENGINE_HOST}:2223")
```

**5b — Rewrite caller SDP on INVITE (request_route)**

After `auth_check` succeeds and `lookup` finds the callee, before `route(RELAY)`:
```
rtpengine_manage("replace-origin replace-session-connection");
t_on_reply("MANAGE_REPLY");
```
`replace-origin` and `replace-session-connection` tell rtpengine to rewrite the `o=`
and `c=` lines in the SDP with the rtpengine EIP. `t_on_reply` registers the reply
route so the 200 OK is also intercepted.

**5c — Rewrite callee SDP on 200 OK (new onreply_route)**
```
onreply_route[MANAGE_REPLY] {
    if (t_check_status("200")) {
        rtpengine_manage("replace-origin replace-session-connection");
    }
}
```
This rewrites the callee's SDP in the 200 OK the same way — the address the caller
receives for incoming audio becomes the rtpengine EIP, not the callee's private IP.

**5d — Release rtpengine resources on BYE**

In the `has_totag()` / `loose_route()` in-dialog block, add before `route(RELAY)`:
```
if ($rm == "BYE") {
    rtpengine_delete();
}
```
Without this, rtpengine keeps the port pair allocated indefinitely after the call ends.

---

## Phase 6 — Wire rtpengine into environments

- [ ] `environments/nonprod/main.tf` — add `module "rtpengine"` block
- [ ] `environments/nonprod/variables.tf` — add `rtpengine_instance_type` (default t3.micro)
- [ ] `environments/nonprod/nonprod.tfvars` — no new values needed (all defaults acceptable)
- [ ] `environments/prod/main.tf` — same module block, but prod vars: larger instance type,
  higher port range, CloudWatch logs enabled

---

## Phase 7 — Rebuild and deploy

- [ ] `docker build` the Kamailio image (picks up the new `rtpengine` module in the config)
- [ ] Push to ECR with new tag (e.g. `v0.2.0`)
- [ ] Update `container_image` in `nonprod.tfvars`
- [ ] `terraform apply` — creates EC2, EIP, new SG rules; updates ECS task definition
- [ ] Verify rtpengine is running: ECS Exec into Kamailio container and check
  `nc -u RTPENGINE_HOST 2223` responds to a ping command
- [ ] Confirm Kamailio logs show `"connected to rtpengine"` on startup

---

## Phase 8 — Softphone test with audio

- [ ] Register alice and bob (two devices or MicroSIP + Linphone on same PC)
- [ ] Verify both show as registered in CloudWatch (`REGISTERED user=alice`, `REGISTERED user=bob`)
- [ ] Alice calls `bob@<nlb-eip>` — verify INVITE → 200 OK in CloudWatch
- [ ] Confirm audio flows both ways (speak and listen)
- [ ] Check rtpengine stats via SSM into the EC2 instance:
  ```
  rtpengine-ctl list calls
  ```
  Should show one active call with packet counters incrementing on both legs
- [ ] Hang up — verify BYE → 200 OK in CloudWatch and call disappears from rtpengine stats
- [ ] Configure both softphones to use **G.711 (PCMA or PCMU)** only — avoids any
  transcoding edge case during initial testing

---

## Codec note

rtpengine in passthrough mode does not transcode — it forwards whatever codec the
softphones negotiate. Both MicroSIP and Linphone support G.711 natively. For the initial
test, disable all codecs except PCMU/PCMA in the softphone settings to keep SDP simple
and eliminate codec mismatch as a failure mode. Wideband (G.722, Opus) can be tested once
the basic path is confirmed.

---

## Estimated effort

| Phase | Estimate |
|---|---|
| 1–2 — Terraform module + SG changes | 1 day |
| 3 — rtpengine EC2 user_data + config | 0.5 day |
| 4 — Pass env var through Terraform | 0.5 day |
| 5 — Kamailio config changes | 1 day |
| 6 — Environment wiring | 0.5 day |
| 7 — Build, push, apply | 0.5 day |
| 8 — Testing + debugging | 1 day |
| **Total** | **~5 days** |

The biggest variable is Phase 5 and 8: SDP rewriting and the `onreply_route` are the
trickiest parts of Kamailio to get right. The rtpengine `PRIVATE_IP!EIP` interface
configuration is the second most common source of first-time failures.

---

## Out of scope for this plan

- DTMF relay (can be added to rtpengine flags later)
- Call recording (rtpengine supports it natively, one flag to enable)
- Transcoding (requires rtpengine compiled with codec support; t3.micro is CPU-limited)
- SRTP / media encryption (requires TLS on signaling side too; Phase 2 of prod hardening)
- RTP auto-scaling (rtpengine is stateful; scaling requires session handoff or sticky routing)
