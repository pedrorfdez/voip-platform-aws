#!/usr/bin/env bash
# local-test/baresip/entrypoint.sh
# Start one baresip agent. The agent uses files for audio, not devices.
set -euo pipefail

SIP_PORT="${SIP_PORT:-5070}"
SOURCE_WAV="${SOURCE_WAV:-tone.wav}"
ANSWERMODE="${ANSWERMODE:-manual}"
CALL_TARGET="${CALL_TARGET:-}"
CALL_DURATION="${CALL_DURATION:-8}"
# Registration takes about 8 seconds. The caller must wait longer than that.
REGISTER_WAIT="${REGISTER_WAIT:-12}"
# baresip cannot find the default config path in this image. Set it here.
CONF_DIR="${CONF_DIR:-/root/.baresip}"

mkdir -p /audio "${CONF_DIR}"

# Find the directory that holds the baresip module files.
MODULE_PATH="${MODULE_PATH:-}"
if [[ -z "${MODULE_PATH}" ]]; then
    MODULE_PATH="$(dirname "$(find /usr/local -name 'g711.so' -print -quit)")"
fi
if [[ ! -f "${MODULE_PATH}/g711.so" ]]; then
    echo "ERROR: cannot find the baresip modules under /usr/local" >&2
    exit 1
fi
echo "==> module_path: ${MODULE_PATH}"

# 440Hz tone, 16-bit mono 8kHz. This matches audio_codecs PCMA/8000/1.
if [[ ! -f "/audio/${SOURCE_WAV}" ]]; then
    sox -n -r 8000 -c 1 -b 16 "/audio/${SOURCE_WAV}" synth "${CALL_DURATION}" sine 440
fi

export SIP_PORT SOURCE_WAV ANSWERMODE MODULE_PATH
envsubst '${SIP_USER} ${SIP_PASS} ${ANSWERMODE}' < /templates/accounts.template > "${CONF_DIR}/accounts"
envsubst '${SIP_PORT} ${SOURCE_WAV} ${MODULE_PATH}' < /templates/config.template > "${CONF_DIR}/config"

echo "==> accounts:"; cat "${CONF_DIR}/accounts"
echo "==> config:";   cat "${CONF_DIR}/config"

# The -t option is a guard. It stops baresip if a /quit command does not arrive.
if [[ -n "${CALL_TARGET}" ]]; then
    # Caller: register, dial, hold the call, hang up, then quit.
    MAX_RUNTIME=$((REGISTER_WAIT + CALL_DURATION + 10))
    ( sleep "${REGISTER_WAIT}"
      echo "/dial sip:${CALL_TARGET}@kamailio"
      sleep "${CALL_DURATION}"
      echo "/hangup"
      sleep 2
      echo "/quit" ) | baresip -f "${CONF_DIR}" -t "${MAX_RUNTIME}"
else
    # Callee: register and answer the inbound call automatically, then quit.
    MAX_RUNTIME=$((REGISTER_WAIT + CALL_DURATION + 16))
    ( sleep $((MAX_RUNTIME - 4)); echo "/quit" ) | baresip -f "${CONF_DIR}" -t "${MAX_RUNTIME}"
fi
