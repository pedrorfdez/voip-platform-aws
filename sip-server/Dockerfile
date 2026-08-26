FROM ghcr.io/kamailio/kamailio:5.7.5-bullseye

# gettext-base      — envsubst for config template substitution
# postgresql-client — psql used by entrypoint.sh to bootstrap the DB schema on first start
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gettext-base \
       postgresql-client \
       kamailio-extra-modules \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY kamailio.cfg.template /etc/kamailio/kamailio.cfg.template
COPY db/ /etc/kamailio/db/

RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp
EXPOSE 5060/tcp
EXPOSE 5061/tcp

ENTRYPOINT ["/entrypoint.sh"]
