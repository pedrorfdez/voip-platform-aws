#!/usr/bin/env bash
# local-test/scripts/run-audio-test.sh
# Place one call from alice to bob through Kamailio and rtpengine.
# The test passes only on three independent signals:
#   1. rtpengine relayed a large number of RTP packets.
#   2. bob recorded an audio file that is long enough.
#   3. That audio holds real sound, not silence.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Stop Git Bash (MSYS) on Windows from rewriting container paths into host
# Windows paths before they reach docker. Other shells do not read this.
export MSYS_NO_PATHCONV=1

BOB_CONTAINER="local-test-bob"
ALICE_CONTAINER="local-test-alice"
# The call must be long enough for the media path to start. A short call can
# end before the first RTP packet arrives, which gives a silent recording.
CALL_DURATION="${CALL_DURATION:-20}"
# bob stops after REGISTER_WAIT + CALL_DURATION + 16 seconds. This script waits
# for bob to register, and alice then waits again before it dials. A large
# REGISTER_WAIT keeps bob alive for the whole call. bob is the callee, so this
# value only extends its lifetime. It does not delay the answer.
BOB_LIFETIME_PAD="${BOB_LIFETIME_PAD:-40}"
# The minimum audio length that proves media flowed for most of the call.
MIN_DURATION="${MIN_DURATION:-4.0}"
# The minimum sample level that proves the audio is not silence.
MIN_AMPLITUDE="${MIN_AMPLITUDE:-0.01}"
# The minimum packet count. RTCP alone gives about 5 packets, so a small
# count does not prove that media crossed the relay.
MIN_PACKETS="${MIN_PACKETS:-100}"
# The maximum time to wait for bob to register, in seconds.
REGISTER_TIMEOUT="${REGISTER_TIMEOUT:-60}"
# The maximum time to wait for bob to end the call, in seconds.
CALL_TIMEOUT="${CALL_TIMEOUT:-180}"

fail() {
    echo "FAIL [$1]: $2" >&2
    exit 1
}

cleanup() {
    docker rm -f "${BOB_CONTAINER}" "${ALICE_CONTAINER}" >/dev/null 2>&1 || true
}

# Print bob's last log lines when the test fails. They show why the call failed.
on_exit() {
    local code=$?
    if [[ ${code} -ne 0 ]]; then
        echo "==> Last lines from bob:" >&2
        docker logs --tail 20 "${BOB_CONTAINER}" >&2 2>&1 || true
    fi
    cleanup
}
trap on_exit EXIT

ctl() {
    docker compose exec -T rtpengine rtpengine-ctl "$@"
}

# Run a shell command inside a throwaway bob container. This gives access to
# the bob-audio volume and to the sox tools in the baresip image.
in_audio() {
    docker compose run --rm --entrypoint sh bob -c "$1"
}

# Count sessions rtpengine has cleanly deleted via BYE, as opposed to ones
# it only expired after a timeout. A session that never gets a real BYE
# (e.g. because Record-Route is unroutable and the UAs bypass the proxy)
# shows up here as zero, growing the timeout counters instead.
regular_terminated() {
    ctl list totals \
        | awk -F: '/^[[:space:]]*Total regular terminated sessions[[:space:]]*:/ { gsub(/[^0-9]/, "", $2); print $2; exit }'
}

# Count the packets that rtpengine relayed. "list totals" leaves out the
# sessions that still run, and rtpengine keeps a session for about 60 seconds
# after the call. So add the counters of the live sessions to the totals.
relayed_packets() {
    local totals live id
    totals="$(ctl list totals \
        | awk -F: '/^[[:space:]]*Total relayed packets[[:space:]]*:/ { gsub(/[^0-9]/, "", $2); print $2; exit }')"
    live=0
    for id in $(ctl list sessions all 2>/dev/null | awk '/^callid:/ { print $2 }'); do
        live=$(( live + $(ctl list sessions "${id}" 2>/dev/null \
            | grep -oE '[0-9]+ p,' | awk '{ s += $1 } END { print s + 0 }') ))
    done
    echo $(( ${totals:-0} + live ))
}

echo "==> Stage 1: checking that the stack is up..."
ctl list numsessions >/dev/null 2>&1 \
    || fail "stack" "rtpengine is not running. Run 'docker compose up -d --build' first."
docker compose ps --status running --services 2>/dev/null | grep -qx kamailio \
    || fail "stack" "kamailio is not running. Run 'docker compose up -d --build' first."

echo "==> Stage 2: clearing the state of any earlier run..."
# The bob-audio volume keeps its content between runs. A stale file here
# would make this test pass without a call. Delete it before the call.
in_audio 'rm -f /audio/received.wav' >/dev/null \
    || fail "clean" "cannot delete the old /audio/received.wav."
in_audio 'test ! -e /audio/received.wav' >/dev/null 2>&1 \
    || fail "clean" "/audio/received.wav still exists after the delete."
# Drop the sessions that an earlier call left open, so the packet counters
# below measure this call only.
ctl terminate all >/dev/null 2>&1 || true

BASELINE_PACKETS="$(relayed_packets)"
echo "  rtpengine relayed packets before the call: ${BASELINE_PACKETS}"
BASELINE_TERMINATED="$(regular_terminated)"

echo "==> Stage 3: starting bob and waiting for it to register..."
cleanup
docker compose run -d \
    -e REGISTER_WAIT="${BOB_LIFETIME_PAD}" \
    -e CALL_DURATION="${CALL_DURATION}" \
    --name "${BOB_CONTAINER}" bob >/dev/null \
    || fail "bob-start" "cannot start the bob agent."

# Wait for bob's own registration confirmation. A fixed sleep is not reliable.
REGISTERED=0
for _ in $(seq 1 "${REGISTER_TIMEOUT}"); do
    if docker logs "${BOB_CONTAINER}" 2>&1 | grep -q "useragent registered successfully"; then
        REGISTERED=1
        break
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "${BOB_CONTAINER}" 2>/dev/null)" != "true" ]]; then
        break
    fi
    sleep 1
done
[[ "${REGISTERED}" -eq 1 ]] \
    || fail "bob-register" "bob did not register within ${REGISTER_TIMEOUT}s."
echo "  bob is registered and answers calls automatically."

echo "==> Stage 4: placing the call from alice to bob..."
# A stuck agent must fail the test. It must not block the script forever.
ALICE_TIMEOUT="${ALICE_TIMEOUT:-$(( CALL_DURATION + 120 ))}"
ALICE_RUN=(docker compose run --rm --name "${ALICE_CONTAINER}" -e CALL_DURATION="${CALL_DURATION}" alice)
if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${ALICE_TIMEOUT}" "${ALICE_RUN[@]}" \
        || fail "alice" "the alice agent failed or did not stop within ${ALICE_TIMEOUT}s."
else
    "${ALICE_RUN[@]}" \
        || fail "alice" "the alice agent exited with an error."
fi

echo "==> Stage 5: waiting for bob to finish..."
for _ in $(seq 1 "${CALL_TIMEOUT}"); do
    [[ "$(docker inspect -f '{{.State.Running}}' "${BOB_CONTAINER}" 2>/dev/null)" == "true" ]] || break
    sleep 1
done
[[ "$(docker inspect -f '{{.State.Running}}' "${BOB_CONTAINER}" 2>/dev/null)" != "true" ]] \
    || fail "bob-stop" "bob did not stop within ${CALL_TIMEOUT}s."

echo "==> Stage 6: checking that rtpengine relayed real packets..."
PACKETS="$(relayed_packets)"
RELAYED=$(( PACKETS - BASELINE_PACKETS ))
echo "  rtpengine relayed ${RELAYED} packets for this call."
[[ "${RELAYED}" -ge "${MIN_PACKETS}" ]] \
    || fail "rtpengine" "rtpengine relayed ${RELAYED} packets, fewer than ${MIN_PACKETS}. Little or no media crossed the relay."

echo "==> Stage 7: checking the length of bob's recording..."
in_audio 'test -s /audio/received.wav' >/dev/null 2>&1 \
    || fail "audio-file" "bob never wrote /audio/received.wav. The call did not connect."
# soxi is in the baresip image, so probe the file where the volume is mounted.
DURATION="$(docker compose run --rm --entrypoint soxi bob -D /audio/received.wav | tr -d '\r')" \
    || fail "audio-probe" "soxi cannot read /audio/received.wav."
echo "  Recorded duration: ${DURATION}s"
awk -v d="${DURATION}" -v m="${MIN_DURATION}" 'BEGIN { exit !(d >= m) }' \
    || fail "audio-duration" "the audio is shorter than ${MIN_DURATION}s. The call dropped early."

echo "==> Stage 8: checking that the recording holds sound, not silence..."
# baresip writes the file for the whole call, even when no RTP arrives.
# Without this check a silent file of the right length would pass.
AMPLITUDE="$(in_audio 'sox /audio/received.wav -n stat 2>&1' \
    | awk -F: '/Maximum amplitude/ { gsub(/[^0-9.eE+-]/, "", $2); print $2; exit }')"
echo "  Maximum amplitude: ${AMPLITUDE:-none}"
[[ -n "${AMPLITUDE}" ]] \
    || fail "audio-probe" "sox cannot report the amplitude of /audio/received.wav."
awk -v a="${AMPLITUDE}" -v m="${MIN_AMPLITUDE}" 'BEGIN { exit !(a >= m) }' \
    || fail "audio-silence" "the recording is silence. Media never reached bob."

echo "==> Stage 9: checking that the session ended via a real BYE, not a timeout..."
# rtpengine needs up to ~60s to fold a just-ended session into "list totals".
# Poll instead of checking once, so this doesn't race the call's own hangup.
TERMINATED_DELTA=0
for _ in $(seq 1 60); do
    TERMINATED_DELTA=$(( $(regular_terminated) - BASELINE_TERMINATED ))
    [[ "${TERMINATED_DELTA}" -ge 1 ]] && break
    sleep 1
done
[[ "${TERMINATED_DELTA}" -ge 1 ]] \
    || fail "rtpengine-cleanup" "rtpengine never recorded a regular-terminated session for this call — BYE likely never reached Kamailio (check Record-Route: 'docker compose logs kamailio' should show 'RELAY method=BYE')."

echo "PASS: rtpengine relayed ${RELAYED} packets, cleanly terminated the session via BYE, and bob recorded ${DURATION}s of audio at amplitude ${AMPLITUDE}."
