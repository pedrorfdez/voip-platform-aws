#!/bin/sh
set -e

# 1. Substitute DB credentials into the config template.
#    Kamailio's own variable syntax ($ru, $var(...), etc.) does not use ${} braces,
#    so envsubst only replaces the explicit list and leaves the rest untouched.
envsubst '${DB_HOST} ${DB_PORT} ${DB_NAME} ${RTPENGINE_HOST}' \
    < /etc/kamailio/kamailio.cfg.template \
    > /etc/kamailio/kamailio.cfg

# 2. Bootstrap the database schema.
#    Both SQL files are idempotent (CREATE TABLE IF NOT EXISTS / ON CONFLICT DO UPDATE)
#    so this is safe to run on every container start.
#    We wait briefly for RDS to accept connections in case the task starts before the DB is ready.
export PGPASSWORD="${DB_PASSWORD}"

echo "Waiting for database..."
until psql -h "${DB_HOST}" -p "${DB_PORT}" -U sipadmin -d "${DB_NAME}" -c "SELECT 1" > /dev/null 2>&1; do
    sleep 2
done
echo "Database ready. Running schema bootstrap..."

psql -h "${DB_HOST}" -p "${DB_PORT}" -U sipadmin -d "${DB_NAME}" -f /etc/kamailio/db/schema.sql
psql -h "${DB_HOST}" -p "${DB_PORT}" -U sipadmin -d "${DB_NAME}" -f /etc/kamailio/db/seed.sql

echo "Bootstrap complete. Starting Kamailio..."

# 3. Start Kamailio.
#    -DD : verbose debug (change to -D for less output once stable)
#    -E  : log to stderr (picked up by the ECS/CloudWatch log driver)
#    -e  : strip color codes (cleaner in CloudWatch)
exec kamailio -DD -E -e -f /etc/kamailio/kamailio.cfg
