FROM debian:bookworm-slim

# Same non-free repo addition and package as modules/rtpengine/user_data.sh.tpl,
# so a pass here is evidence the production EC2 install path also works.
# The base image ships apt sources in deb822 format with an explicit
# Signed-By keyring. A plain one-line entry for the same URI without
# Signed-By is treated by apt as a conflicting duplicate source, so this
# entry sets the same keyring explicitly.
RUN echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm contrib non-free non-free-firmware" \
      > /etc/apt/sources.list.d/non-free.list \
 && apt-get update -y \
 && apt-get install -y --no-install-recommends rtpengine gettext-base \
 && rm -rf /var/lib/apt/lists/*

COPY rtpengine.conf.template /etc/rtpengine/rtpengine.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 2223/udp
ENTRYPOINT ["/entrypoint.sh"]
