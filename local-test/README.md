# Local Media Test Harness

Proves that a real SIP call survives the Kamailio -> rtpengine relay and
that RTP audio actually flows, entirely on your machine. No AWS
credentials, no Terraform apply.

## Run it

    ./scripts/local-test.sh

This builds and starts Postgres, Kamailio, and rtpengine locally, runs the
same SIPp signaling scenarios `scripts/verify.sh` runs against real AWS,
then places a real SIP call between two `baresip` agents (alice, bob) and
asserts that rtpengine actually relayed RTP packets, that bob recorded an
audio file long enough to matter, and that the recording holds real sound
rather than silence.

The full run takes a few minutes: Docker image builds (unless cached from
an earlier run) plus a roughly 20-30 second live call.

## Host prerequisites

- Docker with Compose v2 (`docker compose version`)
- `bash` and `awk`

The host does not need `sox`. Every `sox`/`soxi` invocation runs inside the
`baresip` container image, not on the host, to check the duration and the
amplitude of the recorded WAV file after the call.

## What this does and does not prove

Does: that Kamailio's `rtpengine_manage()` wiring and the rtpengine
`interface` config correctly rewrite SDP and relay a real negotiated
G.711 call between two SIP user agents, with audible, non-silent audio
arriving at the callee.

Does not:

- Prove two-way audio. Only alice's tone reaching bob is verified — bob
  does not send RTP back. Treat "two-way" as the eventual goal of this
  harness, not its current, implemented behaviour.
- Prove NAT traversal across a real internet path — there is no NAT
  locally. That is only proven by `scripts/verify.sh` against the
  deployed AWS environment (see the root `README.md`).

## Fixed: rtpengine sessions were not cleaning up on hangup

This harness originally found that `rtpengine-ctl list totals` showed
sessions ending as `timed-out via TIMEOUT` rather than `regular
terminated` — meaning `rtpengine_delete()` never actually fired on BYE.
Root cause: Kamailio was listening on the wildcard address
`0.0.0.0` with no `advertise` address, so `record_route()` inserted a
literally unroutable `Record-Route: <sip:0.0.0.0;...>`. SIP UAs then sent
BYE (and other in-dialog requests) directly to each other instead of back
through Kamailio, so the BYE branch that calls `rtpengine_delete()` never
ran. Fixed in `sip-server/kamailio.cfg.template` by discovering the
container's real IP at startup (`sip-server/entrypoint.sh`) and adding
`advertise ${KAMAILIO_IP}:<port>` to each `listen` line. Confirmed fixed:
`rtpengine-ctl list totals` now shows `Total regular terminated
sessions: 1` per call instead of a timeout.

This also fixed Kamailio's operational logging: `debug=1` was silently
suppressing every `xlog("L_INFO", ...)` line (REGISTER, INVITE, RELAY,
BYE, CANCEL) — there was no per-call visibility at all, locally or in
CloudWatch. Raised to `debug=2` so those lines are actually visible.

## Known timing quirk

Real media takes roughly 5-10 seconds to start flowing after the call
connects in this stack. Root cause isolated to `baresip`'s own `aufile`
audio-source pipeline on the caller side — confirmed independently via
rtpengine's own packet counters (zero packets received from alice for the
first several seconds of every call), not by Kamailio's SDP handling or
rtpengine's relay path. This is a property of the `baresip` test tooling
in `local-test/baresip/`, not a defect in `sip-server/` or the rtpengine
Terraform module. `run-audio-test.sh` works around it at the test level by
defaulting `CALL_DURATION` to 20 seconds — a shorter call risks recording
little more than the startup gap and failing the silence check. If you
override `CALL_DURATION`, keep it well above 10s.

## Debugging a failure

- Signaling test fails: same debugging path as `scripts/verify.sh` —
  check `docker compose logs kamailio`.
- Audio test fails at the rtpengine-packet check (Stage 6): the bug is
  in `sip-server/kamailio.cfg.template`'s rtpengine wiring or
  `local-test/rtpengine/rtpengine.conf.template`.
- Audio test fails at the WAV-duration check (Stage 7) but packet counts
  are non-zero: the call likely dropped early; check
  `local-test/baresip/config.template` (codec/answermode) and the
  `CALL_DURATION` value.
- Audio test fails at the silence check (Stage 8) with a non-zero packet
  count: media reached rtpengine but not bob's recording; check the
  timing quirk above before assuming a code bug.
