-- Kamailio schema for MVP: subscriber (auth) and location (registrations).
-- Run once after terraform apply, before starting ECS tasks.
-- Compatible with Kamailio 6.x + PostgreSQL.

-- -----------------------------------------------------------------------
-- version — Kamailio schema-version registry; checked at startup per module
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS version (
    table_name    VARCHAR(32) NOT NULL,
    table_version INT         NOT NULL DEFAULT 0,
    CONSTRAINT version_table_name_idx UNIQUE (table_name)
);

-- usrloc module expects location at version 9; auth_db expects subscriber at version 7.
INSERT INTO version (table_name, table_version) VALUES ('location',   9) ON CONFLICT (table_name) DO NOTHING;
INSERT INTO version (table_name, table_version) VALUES ('subscriber', 7) ON CONFLICT (table_name) DO NOTHING;

-- -----------------------------------------------------------------------
-- subscriber — one row per SIP account; used by auth_db for DIGEST auth
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriber (
    id          SERIAL PRIMARY KEY,
    username    VARCHAR(64)  NOT NULL,
    domain      VARCHAR(128) NOT NULL DEFAULT '',
    password    VARCHAR(64)  NOT NULL DEFAULT '',
    ha1         VARCHAR(64)  NOT NULL DEFAULT '',
    ha1b        VARCHAR(64)  NOT NULL DEFAULT '',
    CONSTRAINT subscriber_account UNIQUE (username, domain)
);

-- -----------------------------------------------------------------------
-- location — one row per active SIP registration; managed by usrloc
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS location (
    id          SERIAL PRIMARY KEY,
    ruid        VARCHAR(64)  NOT NULL DEFAULT '',
    username    VARCHAR(64)  NOT NULL DEFAULT '',
    domain      VARCHAR(128)          DEFAULT NULL,
    contact     VARCHAR(512) NOT NULL DEFAULT '',
    received    VARCHAR(128)          DEFAULT NULL,
    path        VARCHAR(512)          DEFAULT NULL,
    expires     TIMESTAMP    NOT NULL DEFAULT '2030-05-28 21:32:15',
    q           REAL         NOT NULL DEFAULT 1.0,
    callid      VARCHAR(255) NOT NULL DEFAULT 'Default-Call-ID',
    cseq        INTEGER      NOT NULL DEFAULT 1,
    last_modified TIMESTAMP  NOT NULL DEFAULT '2000-01-01 00:00:01',
    flags       INTEGER      NOT NULL DEFAULT 0,
    cflags      INTEGER      NOT NULL DEFAULT 0,
    user_agent  VARCHAR(255) NOT NULL DEFAULT '',
    socket      VARCHAR(64)           DEFAULT NULL,
    methods     INTEGER               DEFAULT NULL,
    instance    VARCHAR(255)          DEFAULT NULL,
    reg_id      INTEGER      NOT NULL DEFAULT 0,
    server_id   INTEGER      NOT NULL DEFAULT 0,
    connection_id INTEGER    NOT NULL DEFAULT 0,
    keepalive   INTEGER      NOT NULL DEFAULT 0,
    partition   INTEGER      NOT NULL DEFAULT 0,
    CONSTRAINT location_ruid UNIQUE (ruid)
);

CREATE INDEX IF NOT EXISTS location_account_idx ON location (username, domain);
CREATE INDEX IF NOT EXISTS location_expires_idx ON location (expires);
