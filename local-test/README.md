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
- `sox` (`sudo apt install sox` / `brew install sox`) — used to check both
  the duration and the amplitude of the recorded WAV file after the call.

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
- Prove that rtpengine sessions clean up on hangup. `rtpengine_delete()`
  on BYE does not appear to cleanly terminate sessions in this stack;
  `rtpengine-ctl list totals` shows them ending as `timed-out via
  TIMEOUT` rather than `regular terminated`. This is a pre-existing
  condition in `sip-server/kamailio.cfg.template` that this harness
  surfaced. Fixing it is out of scope for this harness, since
  `sip-server/` is off-limits here — the audio test works around it by
  terminating any leftover sessions before it takes its own baseline.

## Known timing quirk

Real media takes roughly 10 seconds to start flowing after the call
connects in this stack (root cause not isolated). `run-audio-test.sh`
works around this at the test level by defaulting `CALL_DURATION` to 20
seconds — a shorter call risks recording little more than the startup
gap and failing the silence check. If you override `CALL_DURATION`,
keep it well above 10s.

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
