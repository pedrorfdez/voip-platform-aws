-- Seed two test SIP accounts: alice and bob.
-- Run after schema.sql. Safe to re-run (ON CONFLICT DO UPDATE).
--
-- Domain is 'ringr.local' — an internal label only.
-- Because kamailio.cfg sets use_domain=0, Kamailio matches subscribers by
-- username only, so the domain stored here does not need to match the NLB IP.
--
-- calculate_ha1=1 in kamailio.cfg means Kamailio hashes the plaintext
-- password at auth time. The ha1 column is unused but required by the schema.
--
-- Change the passwords here before seeding a real environment.

INSERT INTO subscriber (username, domain, password, ha1, ha1b)
VALUES
    ('alice', 'ringr.local', 'alicepass', '', ''),
    ('bob',   'ringr.local', 'bobpass',   '', '')
ON CONFLICT (username, domain) DO UPDATE
    SET password = EXCLUDED.password,
        ha1      = EXCLUDED.ha1;
