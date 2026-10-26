-- Existing deployments only; fresh installations use schema.sql.
ALTER TABLE diagnostic_events ADD COLUMN mac_model VARCHAR(80) NOT NULL DEFAULT 'unknown';
CREATE INDEX diagnostic_events_time ON diagnostic_events (occurred_at);
