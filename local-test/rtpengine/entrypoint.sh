#!/usr/bin/env bash
set -euo pipefail

export RTPENGINE_IP="$(hostname -i | awk '{print $1}')"
export RTP_PORT_MIN="${RTP_PORT_MIN:-40000}"
export RTP_PORT_MAX="${RTP_PORT_MAX:-40100}"

envsubst '${RTPENGINE_IP} ${RTP_PORT_MIN} ${RTP_PORT_MAX}' \
    < /etc/rtpengine/rtpengine.conf.template \
    > /etc/rtpengine/rtpengine.conf

echo "==> rtpengine.conf:"
cat /etc/rtpengine/rtpengine.conf

exec rtpengine --config-file=/etc/rtpengine/rtpengine.conf
